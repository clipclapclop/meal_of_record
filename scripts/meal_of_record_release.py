#!/usr/bin/env python3
"""Host-installed Repflow release adapter for Meal of Record."""

from __future__ import annotations

import fcntl
import hashlib
import http.client
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, BinaryIO

APP_ID = "com.clipclapclop.meal_of_record"
ASSET_LIMIT = 500 * 1024 * 1024
SOURCE_LIMIT = 100 * 1024 * 1024
SOURCE_EXTRACT_LIMIT = 500 * 1024 * 1024
SOURCE_MEMBER_LIMIT = 100_000
RELEASE_FILES = {"CHANGELOG.md", "pubspec.yaml"}
VERSION_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)


class ReleaseError(Exception):
    """A definite, secret-free adapter failure."""


class UncertainError(Exception):
    """A transient or ambiguous result that must retain Repflow recovery state."""


@dataclass(frozen=True)
class SemVer:
    major: int
    minor: int
    patch: int
    prerelease: tuple[str, ...] = ()

    @classmethod
    def parse(cls, value: str) -> "SemVer":
        match = VERSION_RE.fullmatch(value)
        if not match:
            raise ReleaseError("The pubspec version name is not semantic versioning.")
        prerelease = tuple(match.group(4).split(".")) if match.group(4) else ()
        for identifier in prerelease:
            if identifier.isdigit() and len(identifier) > 1 and identifier.startswith("0"):
                raise ReleaseError("The pubspec prerelease version is not canonical semantic versioning.")
        return cls(int(match.group(1)), int(match.group(2)), int(match.group(3)), prerelease)

    def __lt__(self, other: "SemVer") -> bool:
        base = (self.major, self.minor, self.patch)
        other_base = (other.major, other.minor, other.patch)
        if base != other_base:
            return base < other_base
        if not self.prerelease:
            return False
        if not other.prerelease:
            return True
        for left, right in zip(self.prerelease, other.prerelease):
            if left == right:
                continue
            left_numeric = left.isdigit()
            right_numeric = right.isdigit()
            if left_numeric and right_numeric:
                return int(left) < int(right)
            if left_numeric != right_numeric:
                return left_numeric
            return left < right
        return len(self.prerelease) < len(other.prerelease)

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, SemVer):
            return NotImplemented
        return (
            self.major,
            self.minor,
            self.patch,
            self.prerelease,
        ) == (
            other.major,
            other.minor,
            other.patch,
            other.prerelease,
        )

    def __le__(self, other: "SemVer") -> bool:
        return self == other or self < other


@dataclass(frozen=True)
class VersionInfo:
    name: str
    code: int
    semver: SemVer


@dataclass(frozen=True)
class ApkInfo:
    application_id: str
    version_name: str
    version_code: int
    architectures: frozenset[str]
    certificate_sha256: str
    checksum_sha256: str


@dataclass(frozen=True)
class Config:
    forgejo_url: str
    repository: str
    token_file: Path
    signing_properties: Path
    expected_certificate_sha256: str
    minimum_version_name: str
    minimum_version_code: int
    android_sdk: Path
    flutter_executable: Path
    java_home: Path
    state_directory: Path

    @classmethod
    def load(cls) -> "Config":
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        path = config_home / "meal-of-record-release" / "config.json"
        require_private_file(path, "Release adapter configuration")
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise ReleaseError("Release adapter configuration is unreadable.") from error
        required = {
            "forgejo_url",
            "repository",
            "token_file",
            "signing_properties",
            "expected_certificate_sha256",
            "minimum_version_name",
            "minimum_version_code",
            "android_sdk",
            "flutter_executable",
            "java_home",
            "state_directory",
        }
        if not isinstance(raw, dict) or set(raw) != required:
            raise ReleaseError("Release adapter configuration has unexpected fields.")
        string_fields = required - {"minimum_version_code"}
        if any(not isinstance(raw[field], str) or not raw[field] for field in string_fields):
            raise ReleaseError("Release adapter configuration contains an invalid string value.")
        if not isinstance(raw["minimum_version_code"], int) or raw["minimum_version_code"] < 1:
            raise ReleaseError("Release adapter minimum version code is invalid.")

        parsed_url = urllib.parse.urlsplit(raw["forgejo_url"])
        if parsed_url.scheme != "https" or not parsed_url.netloc or parsed_url.path not in ("", "/"):
            raise ReleaseError("The configured Forgejo URL must be an HTTPS origin.")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", raw["repository"]):
            raise ReleaseError("The configured Forgejo repository is invalid.")
        fingerprint = normalize_fingerprint(raw["expected_certificate_sha256"])
        SemVer.parse(raw["minimum_version_name"])

        absolute_paths: dict[str, Path] = {}
        for field in (
            "token_file",
            "signing_properties",
            "android_sdk",
            "flutter_executable",
            "java_home",
            "state_directory",
        ):
            candidate = Path(raw[field]).expanduser()
            if not candidate.is_absolute():
                raise ReleaseError(f"Configured {field} must be an absolute path.")
            absolute_paths[field] = candidate

        require_private_file(absolute_paths["token_file"], "Forgejo release credential")
        validate_signing_inputs(absolute_paths["signing_properties"])
        try:
            token = absolute_paths["token_file"].read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError) as error:
            raise ReleaseError("Forgejo release credential is unreadable.") from error
        if not token or any(character.isspace() for character in token):
            raise ReleaseError("Forgejo release credential is invalid.")
        del token

        sdk = absolute_paths["android_sdk"]
        flutter = absolute_paths["flutter_executable"]
        java_home = absolute_paths["java_home"]
        state_directory = absolute_paths["state_directory"]
        if not sdk.is_dir():
            raise ReleaseError("The configured Android SDK does not exist.")
        if not flutter.is_file() or not os.access(flutter, os.X_OK):
            raise ReleaseError("The configured Flutter executable is unavailable.")
        java = java_home / "bin" / "java"
        if not java.is_file() or not os.access(java, os.X_OK):
            raise ReleaseError("The configured Java runtime is unavailable.")
        ensure_private_directory(state_directory)

        return cls(
            forgejo_url=raw["forgejo_url"].rstrip("/"),
            repository=raw["repository"],
            token_file=absolute_paths["token_file"],
            signing_properties=absolute_paths["signing_properties"],
            expected_certificate_sha256=fingerprint,
            minimum_version_name=raw["minimum_version_name"],
            minimum_version_code=raw["minimum_version_code"],
            android_sdk=sdk,
            flutter_executable=flutter,
            java_home=java_home,
            state_directory=state_directory,
        )

    def token(self) -> str:
        require_private_file(self.token_file, "Forgejo release credential")
        token = self.token_file.read_text(encoding="utf-8").strip()
        if not token or any(character.isspace() for character in token):
            raise ReleaseError("Forgejo release credential is invalid.")
        return token


def normalize_fingerprint(value: str) -> str:
    normalized = value.replace(":", "").strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", normalized):
        raise ReleaseError("The expected signing certificate fingerprint is invalid.")
    return normalized


def require_private_file(path: Path, description: str) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ReleaseError(f"{description} is missing.") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise ReleaseError(f"{description} must be a regular file.")
    if metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
        raise ReleaseError(f"{description} must be owner-only.")


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or path.is_symlink():
        raise ReleaseError("Release state directory must be a regular directory.")
    if metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
        raise ReleaseError("Release state directory must be owner-only.")
    path.chmod(0o700)


def validate_signing_inputs(properties_path: Path) -> None:
    require_private_file(properties_path, "Android signing configuration")
    try:
        lines = properties_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise ReleaseError("Android signing configuration is unreadable.") from error
    values: dict[str, str] = {}
    for line in lines:
        if "=" in line and not line.lstrip().startswith(("#", "!")):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    required = {"storeFile", "storePassword", "keyPassword", "keyAlias"}
    if any(not values.get(key) for key in required):
        raise ReleaseError("Android signing configuration is incomplete.")
    keystore = Path(values["storeFile"]).expanduser()
    if not keystore.is_absolute():
        raise ReleaseError("The release adapter requires an absolute Android keystore path.")
    require_private_file(keystore, "Android release keystore")


def derive_merge_base(pull_request: dict[str, Any], commits: list[Any]) -> str | None:
    merge_base = str(pull_request.get("merge_base", "")).lower()
    if re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", merge_base):
        return merge_base
    if not commits or not isinstance(commits[0], dict):
        return None
    parents = commits[0].get("parents")
    if not isinstance(parents, list) or not parents or not isinstance(parents[0], dict):
        return None
    parent = str(parents[0].get("sha", "")).lower()
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", parent):
        return None
    return parent


def parse_pubspec(text: str) -> VersionInfo:
    matches = re.findall(r"(?m)^version:\s*([^\s+#]+)(?:\+([0-9]+))?\s*$", text)
    if len(matches) != 1 or not matches[0][1]:
        raise ReleaseError("pubspec.yaml must contain one semantic version and Android build number.")
    name, code_text = matches[0]
    semver = SemVer.parse(name)
    code = int(code_text)
    if code < 1:
        raise ReleaseError("The Android build number must be positive.")
    return VersionInfo(name=name, code=code, semver=semver)


def changelog_notes(text: str, version: str) -> str:
    heading = re.compile(rf"(?m)^## \[{re.escape(version)}\](?: - [^\r\n]+)?\s*$")
    matches = list(heading.finditer(text))
    if len(matches) != 1:
        raise ReleaseError("CHANGELOG.md must contain one heading for the release version.")
    start = matches[0].end()
    next_heading = re.search(r"(?m)^## ", text[start:])
    end = start + next_heading.start() if next_heading else len(text)
    notes = text[start:end].strip()
    if not notes:
        raise ReleaseError("The changelog entry for the release version is empty.")
    if len(notes.encode("utf-8")) > 32768:
        raise ReleaseError("The changelog entry for the release version is too large.")
    return notes


def safe_extract_tar(archive: Path, destination: Path) -> Path:
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True, mode=0o700)
    root_name: str | None = None
    extracted_size = 0
    member_count = 0
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle:
            member_count += 1
            if member_count > SOURCE_MEMBER_LIMIT:
                raise ReleaseError("The Forgejo source archive contains too many entries.")
            if member.size < 0:
                raise ReleaseError("The Forgejo source archive contains an invalid entry size.")
            extracted_size += member.size
            if extracted_size > SOURCE_EXTRACT_LIMIT:
                raise ReleaseError("The Forgejo source archive expands beyond the allowed size.")
            pure = PurePosixPath(member.name)
            if pure.is_absolute() or ".." in pure.parts or not pure.parts:
                raise ReleaseError("The Forgejo source archive contains an unsafe path.")
            if root_name is None:
                root_name = pure.parts[0]
            if pure.parts[0] != root_name:
                raise ReleaseError("The Forgejo source archive has multiple roots.")
            relative_parts = pure.parts[1:]
            if not relative_parts:
                continue
            target = destination.joinpath(*relative_parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True, mode=0o755)
                continue
            if not member.isfile():
                raise ReleaseError("The Forgejo source archive contains a non-file entry.")
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            source = bundle.extractfile(member)
            if source is None:
                raise ReleaseError("The Forgejo source archive is incomplete.")
            with source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
            target.chmod(0o755 if member.mode & 0o100 else 0o644)
    if root_name is None:
        raise ReleaseError("The Forgejo source archive is empty.")
    return destination


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(value, output, sort_keys=True, separators=(",", ":"))
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        directory_descriptor = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        if temporary.exists():
            temporary.unlink()


def load_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    require_private_file(path, "Release operation state")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ReleaseError("Release operation state is unreadable.") from error
    if not isinstance(value, dict):
        raise ReleaseError("Release operation state is invalid.")
    return value


class ForgejoApi:
    def __init__(self, config: Config):
        self.base_url = config.forgejo_url
        self.repository = config.repository
        self._token = config.token()

    def _url(self, path: str, query: dict[str, Any] | None = None) -> str:
        owner, repository = self.repository.split("/", 1)
        encoded_owner = urllib.parse.quote(owner, safe="")
        encoded_repository = urllib.parse.quote(repository, safe="")
        url = f"{self.base_url}/api/v1/repos/{encoded_owner}/{encoded_repository}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        return url

    def request_json(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        query: dict[str, Any] | None = None,
        allow_404: bool = False,
    ) -> Any:
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {
            "Accept": "application/json",
            "Authorization": f"token {self._token}",
            "User-Agent": "meal-of-record-release-adapter/1",
        }
        if payload is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(self._url(path, query), data=payload, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read(2 * 1024 * 1024 + 1)
        except urllib.error.HTTPError as error:
            if allow_404 and error.code == 404:
                return None
            if error.code >= 500:
                raise UncertainError("Forgejo is temporarily unavailable.") from error
            raise ReleaseError(f"Forgejo rejected a release request (HTTP {error.code}).") from error
        except (OSError, urllib.error.URLError) as error:
            raise UncertainError("The Forgejo request result is uncertain.") from error
        if len(data) > 2 * 1024 * 1024:
            raise ReleaseError("Forgejo returned an oversized API response.")
        try:
            return json.loads(data)
        except (UnicodeError, json.JSONDecodeError) as error:
            raise UncertainError("Forgejo returned an unreadable API response.") from error

    def download(self, path: str, destination: Path, limit: int) -> None:
        self._download_url(self._url(path), destination, limit)

    def download_asset(self, asset: dict[str, Any], destination: Path) -> None:
        url = asset.get("browser_download_url")
        if not isinstance(url, str):
            raise ReleaseError("Forgejo returned an invalid release asset URL.")
        expected_origin = urllib.parse.urlsplit(self.base_url)
        actual = urllib.parse.urlsplit(url)
        if (
            actual.scheme != expected_origin.scheme
            or actual.netloc != expected_origin.netloc
            or not actual.path.startswith("/attachments/")
            or actual.query
            or actual.fragment
        ):
            raise ReleaseError("Forgejo returned an unexpected release asset URL.")
        self._download_url(url, destination, ASSET_LIMIT)

    def _download_url(self, url: str, destination: Path, limit: int) -> None:
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/octet-stream",
                "Authorization": f"token {self._token}",
                "User-Agent": "meal-of-record-release-adapter/1",
            },
        )
        temporary = destination.with_name(f".{destination.name}.{os.getpid()}.download")
        total = 0
        try:
            with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    total += len(chunk)
                    if total > limit:
                        raise ReleaseError("Forgejo returned an oversized artifact.")
                    output.write(chunk)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, destination)
        except urllib.error.HTTPError as error:
            if error.code >= 500:
                raise UncertainError("Forgejo is temporarily unavailable.") from error
            raise ReleaseError(f"Forgejo rejected an artifact request (HTTP {error.code}).") from error
        except ReleaseError:
            raise
        except (OSError, urllib.error.URLError) as error:
            raise UncertainError("The Forgejo artifact transfer is uncertain.") from error
        finally:
            if temporary.exists():
                temporary.unlink()

    def upload_asset(self, release_id: int, name: str, source: Path) -> dict[str, Any]:
        parsed = urllib.parse.urlsplit(self.base_url)
        owner, repository = self.repository.split("/", 1)
        path = (
            f"/api/v1/repos/{urllib.parse.quote(owner, safe='')}/"
            f"{urllib.parse.quote(repository, safe='')}/releases/{release_id}/assets?"
            + urllib.parse.urlencode({"name": name})
        )
        boundary = f"mor-{uuid.uuid4().hex}"
        prefix = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="attachment"; filename="{name}"\r\n'
            "Content-Type: application/vnd.android.package-archive\r\n\r\n"
        ).encode("ascii")
        suffix = f"\r\n--{boundary}--\r\n".encode("ascii")
        content_length = len(prefix) + source.stat().st_size + len(suffix)
        connection_class = http.client.HTTPSConnection
        connection = connection_class(parsed.hostname, parsed.port or 443, timeout=120)
        try:
            connection.putrequest("POST", path)
            connection.putheader("Authorization", f"token {self._token}")
            connection.putheader("Accept", "application/json")
            connection.putheader("User-Agent", "meal-of-record-release-adapter/1")
            connection.putheader("Content-Type", f"multipart/form-data; boundary={boundary}")
            connection.putheader("Content-Length", str(content_length))
            connection.endheaders()
            connection.send(prefix)
            with source.open("rb") as apk:
                while chunk := apk.read(1024 * 1024):
                    connection.send(chunk)
            connection.send(suffix)
            response = connection.getresponse()
            data = response.read(2 * 1024 * 1024 + 1)
        except (OSError, http.client.HTTPException) as error:
            raise UncertainError("The Forgejo asset upload result is uncertain.") from error
        finally:
            connection.close()
        if response.status >= 500:
            raise UncertainError("The Forgejo asset upload result is uncertain.")
        if response.status not in (200, 201):
            raise ReleaseError(f"Forgejo rejected the release asset (HTTP {response.status}).")
        if len(data) > 2 * 1024 * 1024:
            raise UncertainError("Forgejo returned an oversized upload response.")
        try:
            result = json.loads(data)
        except (UnicodeError, json.JSONDecodeError) as error:
            raise UncertainError("Forgejo returned an unreadable upload response.") from error
        if not isinstance(result, dict):
            raise UncertainError("Forgejo returned an invalid upload response.")
        return result


def find_build_tools(android_sdk: Path) -> tuple[Path, Path]:
    root = android_sdk / "build-tools"
    candidates: list[tuple[tuple[int, ...], Path]] = []
    if root.is_dir():
        for child in root.iterdir():
            if child.is_dir() and re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", child.name):
                numbers = tuple(int(value) for value in child.name.split("."))
                candidates.append((numbers, child))
    for _, directory in sorted(candidates, reverse=True):
        apksigner = directory / "apksigner"
        aapt = directory / "aapt"
        if apksigner.is_file() and aapt.is_file():
            return apksigner, aapt
    raise ReleaseError("Android SDK build tools with apksigner and aapt are unavailable.")


def run_checked(command: list[str], cwd: Path | None = None, env: dict[str, str] | None = None) -> str:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3300,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ReleaseError("A local release verification command failed.") from error
    if result.returncode != 0:
        raise ReleaseError("A local release verification command failed.")
    return result.stdout


def inspect_apk(path: Path, config: Config) -> ApkInfo:
    if not path.is_file() or path.stat().st_size <= 0 or path.stat().st_size > ASSET_LIMIT:
        raise ReleaseError("The Android release artifact is missing or oversized.")
    apksigner, aapt = find_build_tools(config.android_sdk)
    signature = run_checked([str(apksigner), "verify", "--verbose", "--print-certs", str(path)])
    certificate_match = re.search(
        r"(?m)^Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F:]+)\s*$", signature
    )
    if not certificate_match:
        raise ReleaseError("The APK signing certificate could not be determined.")
    certificate = normalize_fingerprint(certificate_match.group(1))
    badging = run_checked([str(aapt), "dump", "badging", str(path)])
    package_match = re.search(
        r"(?m)^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", badging
    )
    if not package_match:
        raise ReleaseError("The APK package metadata could not be determined.")
    native_match = re.search(r"(?m)^native-code:\s*(.*)$", badging)
    architectures = frozenset(re.findall(r"'([^']+)'", native_match.group(1))) if native_match else frozenset()
    try:
        with zipfile.ZipFile(path) as apk:
            invalid = apk.testzip()
            library_architectures = {
                parts[1]
                for name in apk.namelist()
                if len(parts := PurePosixPath(name).parts) >= 3 and parts[0] == "lib" and name.endswith(".so")
            }
    except (OSError, zipfile.BadZipFile) as error:
        raise ReleaseError("The APK archive is invalid.") from error
    if invalid is not None:
        raise ReleaseError("The APK archive failed its integrity check.")
    if architectures != {"arm64-v8a"} or library_architectures != {"arm64-v8a"}:
        raise ReleaseError("The APK does not contain only arm64-v8a native code.")
    digest = hashlib.sha256()
    with path.open("rb") as apk_file:
        while chunk := apk_file.read(1024 * 1024):
            digest.update(chunk)
    checksum = digest.hexdigest()
    return ApkInfo(
        application_id=package_match.group(1),
        version_code=int(package_match.group(2)),
        version_name=package_match.group(3),
        architectures=architectures,
        certificate_sha256=certificate,
        checksum_sha256=checksum,
    )


def verify_apk(info: ApkInfo, version: VersionInfo, config: Config, checksum: str | None = None) -> None:
    if info.application_id != APP_ID:
        raise ReleaseError("The APK application ID is incorrect.")
    if info.version_name != version.name or info.version_code != version.code:
        raise ReleaseError("The APK version does not match pubspec.yaml.")
    if info.certificate_sha256 != config.expected_certificate_sha256:
        raise ReleaseError("The APK signing certificate is not the expected release certificate.")
    if checksum is not None and info.checksum_sha256 != checksum:
        raise ReleaseError("The published APK checksum does not match the built artifact.")


def release_body(notes: str, version: VersionInfo, asset_name: str, checksum: str) -> str:
    return (
        f"{notes}\n\n"
        "---\n"
        f"Android version code: `{version.code}`  \n"
        f"SHA-256 (`{asset_name}`): `{checksum}`"
    )


def validate_release_state(state: dict[str, Any]) -> VersionInfo:
    required = {
        "version_name",
        "version_code",
        "tag",
        "asset_name",
        "prerelease",
        "checksum_sha256",
        "release_body",
    }
    if any(key not in state for key in required):
        raise ReleaseError("Release execution state is incomplete.")
    name = state["version_name"]
    code = state["version_code"]
    if not isinstance(name, str) or not isinstance(code, int) or isinstance(code, bool) or code < 1:
        raise ReleaseError("Release execution state contains an invalid version.")
    semver = SemVer.parse(name)
    if state["tag"] != f"v{name}" or state["asset_name"] != f"meal-of-record-v{name}-arm64-v8a.apk":
        raise ReleaseError("Release execution state contains inconsistent artifact names.")
    if not isinstance(state["prerelease"], bool) or state["prerelease"] != bool(semver.prerelease):
        raise ReleaseError("Release execution state contains an invalid publication mode.")
    checksum = state["checksum_sha256"]
    body = state["release_body"]
    if not isinstance(checksum, str) or not re.fullmatch(r"[0-9a-f]{64}", checksum):
        raise ReleaseError("Release execution state contains an invalid checksum.")
    if not isinstance(body, str) or not body or len(body.encode("utf-8")) > 65536:
        raise ReleaseError("Release execution state contains invalid release notes.")
    return VersionInfo(name=name, code=code, semver=semver)


@dataclass(frozen=True)
class Operation:
    phase: str
    revision: str
    operation_id: str
    pull_request: int
    repository: str

    @classmethod
    def from_environment(cls) -> "Operation":
        required = {
            name: os.environ.get(name, "")
            for name in (
                "REPFLOW_STAGE",
                "REPFLOW_PHASE",
                "REPFLOW_REVISION",
                "REPFLOW_OPERATION_ID",
                "REPFLOW_PULL_REQUEST",
                "REPFLOW_REPOSITORY",
            )
        }
        if required["REPFLOW_STAGE"] != "release":
            raise ReleaseError("The adapter only supports the Repflow release stage.")
        phase = required["REPFLOW_PHASE"]
        if phase not in ("execute", "verify"):
            raise ReleaseError("The adapter only supports execute and verify phases.")
        revision = required["REPFLOW_REVISION"].lower()
        if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", revision):
            raise ReleaseError("Repflow supplied an invalid merged revision.")
        operation_id = required["REPFLOW_OPERATION_ID"]
        if not operation_id or len(operation_id) > 512 or any(ord(value) < 32 for value in operation_id):
            raise ReleaseError("Repflow supplied an invalid operation ID.")
        try:
            pull_request = int(required["REPFLOW_PULL_REQUEST"])
        except ValueError as error:
            raise ReleaseError("Repflow supplied an invalid pull request.") from error
        if pull_request < 1:
            raise ReleaseError("Repflow supplied an invalid pull request.")
        repository = required["REPFLOW_REPOSITORY"]
        if not repository:
            raise ReleaseError("Repflow supplied an invalid repository.")
        return cls(phase, revision, operation_id, pull_request, repository)


class ReleaseAdapter:
    def __init__(self, config: Config, operation: Operation, api: ForgejoApi):
        self.config = config
        self.operation = operation
        self.api = api
        if operation.repository != config.repository:
            raise ReleaseError("Repflow repository does not match the adapter configuration.")
        operation_key = hashlib.sha256(operation.operation_id.encode("utf-8")).hexdigest()
        self.operation_directory = config.state_directory / "operations" / operation_key
        ensure_private_directory(self.operation_directory)
        self.state_path = self.operation_directory / "state.json"
        self.source_archive = self.operation_directory / "source.tar.gz"
        self.source_directory = self.operation_directory / "source"
        self.apk_path = self.operation_directory / "release.apk"

    def _state(self) -> dict[str, Any]:
        state = load_json(self.state_path)
        binding = {
            "operation_id": self.operation.operation_id,
            "revision": self.operation.revision,
            "pull_request": self.operation.pull_request,
            "repository": self.operation.repository,
        }
        if state is None:
            state = dict(binding)
            atomic_json(self.state_path, state)
        elif any(state.get(key) != value for key, value in binding.items()):
            raise ReleaseError("Release operation state belongs to a different operation.")
        return state

    def _save(self, state: dict[str, Any]) -> None:
        atomic_json(self.state_path, state)

    def _pull_request(self) -> dict[str, Any]:
        pull_request = self.api.request_json("GET", f"/pulls/{self.operation.pull_request}")
        if not isinstance(pull_request, dict) or pull_request.get("merged") is not True:
            raise ReleaseError("The release pull request is not merged.")
        if str(pull_request.get("merge_commit_sha", "")).lower() != self.operation.revision:
            raise ReleaseError("The release pull request does not match the merged revision.")
        files: set[str] = set()
        for page in range(1, 11):
            changed = self.api.request_json(
                "GET", f"/pulls/{self.operation.pull_request}/files", query={"page": page, "limit": 50}
            )
            if not isinstance(changed, list):
                raise ReleaseError("Forgejo returned an invalid pull-request file list.")
            for item in changed:
                if not isinstance(item, dict) or not isinstance(item.get("filename"), str):
                    raise ReleaseError("Forgejo returned an invalid changed file.")
                files.add(item["filename"])
            if len(changed) < 50:
                break
        else:
            raise ReleaseError("The release pull request changes too many files.")
        if files != RELEASE_FILES:
            raise ReleaseError("A release requires a dedicated pubspec.yaml and CHANGELOG.md version pull request.")
        base_revision = derive_merge_base(pull_request, [])
        if base_revision is None:
            commits = self.api.request_json(
                "GET", f"/pulls/{self.operation.pull_request}/commits", query={"page": 1, "limit": 50}
            )
            if not isinstance(commits, list):
                raise ReleaseError("Forgejo returned an invalid pull-request commit list.")
            base_revision = derive_merge_base(pull_request, commits)
        if base_revision is None:
            raise ReleaseError("Forgejo did not provide a verifiable pull-request base revision.")
        result = dict(pull_request)
        result["release_base_revision"] = base_revision
        return result

    def _download_source(self, revision: str, archive: Path, destination: Path) -> Path:
        commit = self.api.request_json("GET", f"/git/commits/{revision}")
        if not isinstance(commit, dict) or str(commit.get("sha", "")).lower() != revision:
            raise ReleaseError("Forgejo did not resolve the exact requested revision.")
        if not archive.exists():
            self.api.download(f"/archive/{revision}.tar.gz", archive, SOURCE_LIMIT)
            archive.chmod(0o600)
        return safe_extract_tar(archive, destination)

    def _release_inputs(self) -> tuple[VersionInfo, str, str, str, bool]:
        pull_request = self._pull_request()
        source = self._download_source(self.operation.revision, self.source_archive, self.source_directory)
        try:
            pubspec_text = (source / "pubspec.yaml").read_text(encoding="utf-8")
            changelog_text = (source / "CHANGELOG.md").read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            raise ReleaseError("The exact revision is missing release metadata.") from error
        version = parse_pubspec(pubspec_text)
        notes = changelog_notes(changelog_text, version.name)

        base_revision = str(pull_request.get("release_base_revision", "")).lower()
        if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", base_revision):
            raise ReleaseError("Forgejo returned an invalid pull-request base revision.")
        base_archive = self.operation_directory / "base.tar.gz"
        base_source = self.operation_directory / "base"
        self._download_source(base_revision, base_archive, base_source)
        try:
            base_version = parse_pubspec((base_source / "pubspec.yaml").read_text(encoding="utf-8"))
        except (OSError, UnicodeError) as error:
            raise ReleaseError("The release pull-request base has no valid pubspec version.") from error
        if version.semver <= base_version.semver or version.code <= base_version.code:
            raise ReleaseError("The release version and Android build number must both increase.")
        floor = SemVer.parse(self.config.minimum_version_name)
        if version.semver <= floor or version.code <= self.config.minimum_version_code:
            raise ReleaseError("The release version is not newer than the configured published-version floor.")

        tag = f"v{version.name}"
        asset_name = f"meal-of-record-v{version.name}-arm64-v8a.apk"
        return version, notes, tag, asset_name, bool(version.semver.prerelease)

    def _find_release(self, tag: str) -> dict[str, Any] | None:
        encoded = urllib.parse.quote(tag, safe="")
        release = self.api.request_json("GET", f"/releases/tags/{encoded}", allow_404=True)
        if release is not None and not isinstance(release, dict):
            raise ReleaseError("Forgejo returned invalid release metadata.")
        return release

    @staticmethod
    def _find_asset(release: dict[str, Any], name: str) -> dict[str, Any] | None:
        assets = release.get("assets", [])
        if not isinstance(assets, list):
            raise ReleaseError("Forgejo returned invalid release assets.")
        if not assets:
            return None
        if len(assets) != 1 or not isinstance(assets[0], dict) or assets[0].get("name") != name:
            raise ReleaseError("The Forgejo release must contain exactly the expected APK asset.")
        return assets[0]

    def _verify_release_metadata(
        self,
        release: dict[str, Any],
        tag: str,
        version: VersionInfo,
        prerelease: bool,
        expected_body: str,
    ) -> None:
        if release.get("tag_name") != tag or release.get("target_commitish") != self.operation.revision:
            raise ReleaseError("The Forgejo release tag targets a different revision.")
        if release.get("draft") is not False or release.get("prerelease") is not prerelease:
            raise ReleaseError("The Forgejo release publication mode is incorrect.")
        encoded_ref = urllib.parse.quote(f"tags/{tag}", safe="/")
        reference_response = self.api.request_json("GET", f"/git/refs/{encoded_ref}")
        if isinstance(reference_response, dict):
            references = [reference_response]
        elif isinstance(reference_response, list):
            references = reference_response
        else:
            raise ReleaseError("Forgejo returned invalid release-tag metadata.")
        exact_references = [
            reference
            for reference in references
            if isinstance(reference, dict) and reference.get("ref") == f"refs/tags/{tag}"
        ]
        if len(exact_references) != 1:
            raise ReleaseError("Forgejo did not return one exact release tag.")
        target = exact_references[0].get("object")
        if not isinstance(target, dict) or str(target.get("sha", "")).lower() != self.operation.revision:
            raise ReleaseError("The Forgejo release tag does not resolve to the merged revision.")
        if release.get("name") != f"Meal of Record {version.name}":
            raise ReleaseError("The Forgejo release title is incorrect.")
        if release.get("body") != expected_body:
            raise ReleaseError("The Forgejo release notes do not match the persisted release intent.")

    def _require_newest_version(self, version: VersionInfo, tag: str) -> None:
        published_floor = SemVer.parse(self.config.minimum_version_name)
        for page in range(1, 11):
            releases = self.api.request_json("GET", "/releases", query={"page": page, "limit": 50})
            if not isinstance(releases, list):
                raise ReleaseError("Forgejo returned an invalid release list.")
            for release in releases:
                if not isinstance(release, dict):
                    raise ReleaseError("Forgejo returned invalid release metadata.")
                other_tag = release.get("tag_name")
                if other_tag == tag:
                    continue
                if not isinstance(other_tag, str) or not other_tag.startswith("v"):
                    continue
                try:
                    other_version = SemVer.parse(other_tag[1:])
                except ReleaseError:
                    continue
                if other_version <= published_floor:
                    continue
                body = release.get("body")
                code_match = (
                    re.search(r"(?m)^Android version code: `([0-9]+)`\s*$", body)
                    if isinstance(body, str)
                    else None
                )
                if code_match is None:
                    raise ReleaseError("A prior semantic Forgejo release has no verifiable Android build number.")
                if version.semver <= other_version or version.code <= int(code_match.group(1)):
                    raise ReleaseError("The release is not newer than every existing Forgejo release.")
            if len(releases) < 50:
                return
        raise ReleaseError("Forgejo has too many releases to establish a monotonic version.")

    def _build(self, version: VersionInfo) -> ApkInfo:
        signing_link = self.source_directory / "android" / "key.properties"
        if signing_link.exists() or signing_link.is_symlink():
            raise ReleaseError("The exact source revision unexpectedly contains signing configuration.")
        signing_link.symlink_to(self.config.signing_properties)
        build_script = self.source_directory / "scripts" / "build_android_release"
        if not build_script.is_file() or not os.access(build_script, os.X_OK):
            raise ReleaseError("The exact source revision has no executable Android release builder.")
        environment = os.environ.copy()
        environment["ANDROID_HOME"] = str(self.config.android_sdk)
        environment["ANDROID_SDK_ROOT"] = str(self.config.android_sdk)
        environment["JAVA_HOME"] = str(self.config.java_home)
        environment["PATH"] = (
            f"{self.config.java_home / 'bin'}:{self.config.flutter_executable.parent}:"
            f"{environment.get('PATH', '')}"
        )
        try:
            result = subprocess.run(
                [str(build_script)],
                cwd=self.source_directory,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3300,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ReleaseError("The exact Android release build failed.") from error
        finally:
            if signing_link.is_symlink():
                signing_link.unlink()
        if result.returncode != 0:
            raise ReleaseError("The exact Android release build failed.")
        output = self.source_directory / "build" / "release" / "meal-of-record-arm64-v8a.apk"
        if not output.is_file():
            raise ReleaseError("The Android release build did not produce the expected arm64-v8a APK.")
        shutil.copyfile(output, self.apk_path)
        self.apk_path.chmod(0o600)
        info = inspect_apk(self.apk_path, self.config)
        verify_apk(info, version, self.config)
        return info

    def execute(self) -> dict[str, str]:
        state = self._state()
        version, notes, tag, asset_name, prerelease = self._release_inputs()
        self._require_newest_version(version, tag)
        metadata = {
            "version_name": version.name,
            "version_code": version.code,
            "tag": tag,
            "asset_name": asset_name,
            "prerelease": prerelease,
        }
        for key, value in metadata.items():
            if key in state and state[key] != value:
                raise ReleaseError("Release operation metadata changed across a retry.")
            state[key] = value
        self._save(state)

        release = self._find_release(tag)
        body: str | None = None
        if release is not None:
            checksum = state.get("checksum_sha256")
            if not isinstance(checksum, str):
                raise ReleaseError("A Forgejo release exists without matching local recovery state.")
            body = release_body(notes, version, asset_name, checksum)
            if "release_body" in state and state["release_body"] != body:
                raise ReleaseError("Release notes changed across a retry.")
            state["release_body"] = body
            self._save(state)
            self._verify_release_metadata(release, tag, version, prerelease, body)
            asset = self._find_asset(release, asset_name)
            if asset is not None:
                remote = self.operation_directory / "published.apk"
                self.api.download_asset(asset, remote)
                info = inspect_apk(remote, self.config)
                verify_apk(info, version, self.config, checksum)
                state["release_id"] = release.get("id")
                state["published"] = True
                self._save(state)
                return {
                    "status": "succeeded",
                    "summary": f"Reconciled Forgejo release {tag} with its verified arm64-v8a APK.",
                    "externalId": f"release:{release.get('id')}",
                }

        if self.apk_path.exists() and isinstance(state.get("checksum_sha256"), str):
            info = inspect_apk(self.apk_path, self.config)
            verify_apk(info, version, self.config, state["checksum_sha256"])
        else:
            info = self._build(version)
            if "checksum_sha256" in state and state["checksum_sha256"] != info.checksum_sha256:
                raise ReleaseError("A rebuilt APK does not match the persisted release intent.")
            state["checksum_sha256"] = info.checksum_sha256
            state["built"] = True
            self._save(state)

        body = release_body(notes, version, asset_name, state["checksum_sha256"])
        if "release_body" in state and state["release_body"] != body:
            raise ReleaseError("Release notes changed across a retry.")
        state["release_body"] = body
        self._save(state)
        if release is None:
            release = self.api.request_json(
                "POST",
                "/releases",
                body={
                    "tag_name": tag,
                    "target_commitish": self.operation.revision,
                    "name": f"Meal of Record {version.name}",
                    "body": body,
                    "draft": False,
                    "prerelease": prerelease,
                    "hide_archive_links": False,
                },
            )
            if not isinstance(release, dict) or not isinstance(release.get("id"), int):
                raise UncertainError("Forgejo returned invalid release creation metadata.")
            self._verify_release_metadata(release, tag, version, prerelease, body)
            state["release_id"] = release["id"]
            self._save(state)

        asset = self._find_asset(release, asset_name)
        if asset is None:
            try:
                self.api.upload_asset(release["id"], asset_name, self.apk_path)
            except (ReleaseError, UncertainError):
                reconciled = self._find_release(tag)
                if reconciled is not None and self._find_asset(reconciled, asset_name) is not None:
                    release = reconciled
                else:
                    raise
        release = self._find_release(tag)
        if release is None:
            raise UncertainError("The published Forgejo release could not be reconciled.")
        self._verify_release_metadata(release, tag, version, prerelease, body)
        asset = self._find_asset(release, asset_name)
        if asset is None:
            raise UncertainError("The published Forgejo asset could not be reconciled.")
        remote = self.operation_directory / "published.apk"
        self.api.download_asset(asset, remote)
        remote_info = inspect_apk(remote, self.config)
        verify_apk(remote_info, version, self.config, state["checksum_sha256"])
        state["release_id"] = release["id"]
        state["published"] = True
        self._save(state)
        return {
            "status": "succeeded",
            "summary": f"Published Forgejo release {tag} with one verified arm64-v8a APK.",
            "externalId": f"release:{release['id']}",
        }

    def verify(self) -> dict[str, str]:
        state = self._state()
        version = validate_release_state(state)
        release = self._find_release(str(state["tag"]))
        if release is None:
            raise ReleaseError("The Forgejo release is missing.")
        self._verify_release_metadata(
            release,
            str(state["tag"]),
            version,
            bool(state["prerelease"]),
            str(state["release_body"]),
        )
        asset = self._find_asset(release, str(state["asset_name"]))
        if asset is None:
            raise ReleaseError("The Forgejo release APK is missing.")
        remote = self.operation_directory / "verified.apk"
        self.api.download_asset(asset, remote)
        info = inspect_apk(remote, self.config)
        verify_apk(info, version, self.config, str(state["checksum_sha256"]))
        state["verified"] = True
        self._save(state)
        return {
            "status": "passed",
            "summary": (
                f"Verified {state['tag']}: exact merged tag, expected signer, application ID, "
                f"version, arm64-v8a architecture, and SHA-256 asset checksum."
            ),
            "externalId": f"release:{release['id']}",
        }


def doctor(config: Config) -> dict[str, str]:
    find_build_tools(config.android_sdk)
    api = ForgejoApi(config)
    repository = api.request_json("GET", "")
    if not isinstance(repository, dict) or repository.get("full_name") != config.repository:
        raise ReleaseError("The release credential cannot read the configured repository.")
    permissions = repository.get("permissions")
    if not isinstance(permissions, dict) or permissions.get("push") is not True:
        raise ReleaseError("The release credential lacks repository-write permission.")
    return {
        "status": "passed",
        "summary": "Release adapter configuration, local tools, signing inputs, and Forgejo access are available.",
    }


def emit(result: dict[str, str]) -> None:
    encoded = json.dumps(result, sort_keys=True, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > 65536:
        raise RuntimeError("adapter result too large")
    print(encoded)


def main() -> int:
    try:
        config = Config.load()
        if len(sys.argv) == 2 and sys.argv[1] == "doctor":
            emit(doctor(config))
            return 0
        if len(sys.argv) != 1:
            raise ReleaseError("The release adapter received unsupported arguments.")
        operation = Operation.from_environment()
        if Path.cwd().resolve() != config.state_directory.resolve():
            raise ReleaseError("The release adapter is running outside its configured working directory.")
        lock_path = config.state_directory / "adapter.lock"
        lock_descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(lock_descriptor, fcntl.LOCK_EX)
            adapter = ReleaseAdapter(config, operation, ForgejoApi(config))
            result = adapter.execute() if operation.phase == "execute" else adapter.verify()
        finally:
            os.close(lock_descriptor)
        emit(result)
        return 0
    except ReleaseError as error:
        if len(sys.argv) == 2 and sys.argv[1] == "doctor":
            emit({"status": "failed", "summary": str(error)})
            return 1
        phase = os.environ.get("REPFLOW_PHASE")
        status = "failed"
        emit({"status": status, "summary": str(error)})
        return 1
    except UncertainError as error:
        print(str(error), file=sys.stderr)
        return 2
    except Exception:
        print("The release adapter stopped with an unexpected secret-free failure.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
