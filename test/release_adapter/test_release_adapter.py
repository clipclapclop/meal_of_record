import importlib.util
import io
import sys
import tarfile
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).parents[2] / "scripts" / "meal_of_record_release.py"
SPEC = importlib.util.spec_from_file_location("meal_of_record_release", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
release = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release
SPEC.loader.exec_module(release)


class SemVerTest(unittest.TestCase):
    def test_semantic_version_order(self):
        ordered = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
            "1.0.1",
        ]
        parsed = [release.SemVer.parse(value) for value in ordered]
        self.assertEqual(parsed, sorted(reversed(parsed)))

    def test_rejects_invalid_semantic_versions(self):
        for value in ("1.0", "01.0.0", "1.0.0-01", "v1.0.0", "1.0.0+2"):
            with self.subTest(value=value), self.assertRaises(release.ReleaseError):
                release.SemVer.parse(value)


class AndroidBuildToolsTest(unittest.TestCase):
    def test_ignores_preview_build_tools_directories(self):
        with tempfile.TemporaryDirectory() as temporary:
            sdk = Path(temporary)
            stable = sdk / "build-tools" / "35.0.0"
            preview = sdk / "build-tools" / "36.0.0-rc1"
            for directory in (stable, preview):
                directory.mkdir(parents=True)
                (directory / "aapt").touch()
                (directory / "apksigner").touch()
            self.assertEqual(release.find_build_tools(sdk), (stable / "apksigner", stable / "aapt"))


class PullRequestMetadataTest(unittest.TestCase):
    def test_uses_forgejo_merge_base_when_present(self):
        self.assertEqual(
            release.derive_merge_base({"merge_base": "A" * 40}, []),
            "a" * 40,
        )

    def test_falls_back_to_first_pull_request_commit_parent(self):
        commits = [{"sha": "b" * 40, "parents": [{"sha": "a" * 40}]}]
        self.assertEqual(release.derive_merge_base({}, commits), "a" * 40)

    def test_rejects_missing_or_invalid_base_evidence(self):
        self.assertIsNone(release.derive_merge_base({}, []))
        self.assertIsNone(release.derive_merge_base({"merge_base": "master"}, [{"parents": []}]))


class MetadataTest(unittest.TestCase):
    def test_parses_pubspec_version_and_build_number(self):
        result = release.parse_pubspec("name: example\nversion: 1.2.3-rc.1+2042\n")
        self.assertEqual(result.name, "1.2.3-rc.1")
        self.assertEqual(result.code, 2042)
        self.assertTrue(result.semver.prerelease)

    def test_requires_android_build_number(self):
        with self.assertRaises(release.ReleaseError):
            release.parse_pubspec("version: 1.2.3\n")

    def test_extracts_exact_changelog_section(self):
        text = (
            "# Changelog\n\n"
            "## [Unreleased]\n\nPending.\n\n"
            "## [1.2.3] - 2026-04-01\n\n- First.\n- Second.\n\n"
            "## [1.2.2] - 2026-03-01\n\n- Older.\n"
        )
        self.assertEqual(release.changelog_notes(text, "1.2.3"), "- First.\n- Second.")

    def test_release_body_includes_verification_values(self):
        version = release.parse_pubspec("version: 1.2.3+2042\n")
        body = release.release_body("- Notes.", version, "release.apk", "a" * 64)
        self.assertIn("Android version code: `2042`", body)
        self.assertIn("SHA-256 (`release.apk`): `" + "a" * 64 + "`", body)


class ArchiveTest(unittest.TestCase):
    def test_extracts_regular_files_without_archive_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "source.tar.gz"
            with tarfile.open(archive, "w:gz") as bundle:
                data = b"version: 1.2.3+4\n"
                member = tarfile.TarInfo("repository/pubspec.yaml")
                member.size = len(data)
                member.mode = 0o644
                bundle.addfile(member, io.BytesIO(data))
            destination = release.safe_extract_tar(archive, root / "source")
            self.assertEqual((destination / "pubspec.yaml").read_bytes(), data)

    def test_rejects_archive_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "source.tar.gz"
            with tarfile.open(archive, "w:gz") as bundle:
                data = b"unsafe"
                member = tarfile.TarInfo("repository/../../outside")
                member.size = len(data)
                bundle.addfile(member, io.BytesIO(data))
            with self.assertRaises(release.ReleaseError):
                release.safe_extract_tar(archive, root / "source")

    def test_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "source.tar.gz"
            with tarfile.open(archive, "w:gz") as bundle:
                member = tarfile.TarInfo("repository/link")
                member.type = tarfile.SYMTYPE
                member.linkname = "/tmp/elsewhere"
                bundle.addfile(member)
            with self.assertRaises(release.ReleaseError):
                release.safe_extract_tar(archive, root / "source")

    def test_rejects_archive_that_expands_beyond_limit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "source.tar.gz"
            with tarfile.open(archive, "w:gz") as bundle:
                data = b"large"
                member = tarfile.TarInfo("repository/file")
                member.size = len(data)
                bundle.addfile(member, io.BytesIO(data))
            with mock.patch.object(release, "SOURCE_EXTRACT_LIMIT", len(data) - 1):
                with self.assertRaises(release.ReleaseError):
                    release.safe_extract_tar(archive, root / "source")


class ReleaseOrderingTest(unittest.TestCase):
    class FakeApi:
        def __init__(self, releases):
            self.releases = releases

        def request_json(self, method, path, query=None):
            assert method == "GET"
            assert path == "/releases"
            return self.releases if query["page"] == 1 else []

    def adapter(self, releases):
        adapter = object.__new__(release.ReleaseAdapter)
        adapter.api = self.FakeApi(releases)
        adapter.config = types.SimpleNamespace(minimum_version_name="1.0.0")
        return adapter

    def test_requires_version_and_code_after_existing_release(self):
        existing = [{"tag_name": "v1.2.3", "body": "Android version code: `42`"}]
        adapter = self.adapter(existing)
        adapter._require_newest_version(release.parse_pubspec("version: 1.2.4+43\n"), "v1.2.4")
        with self.assertRaises(release.ReleaseError):
            adapter._require_newest_version(release.parse_pubspec("version: 1.2.2+44\n"), "v1.2.2")
        with self.assertRaises(release.ReleaseError):
            adapter._require_newest_version(release.parse_pubspec("version: 1.2.4+42\n"), "v1.2.4")

    def test_allows_same_tag_during_retry(self):
        existing = [{"tag_name": "v1.2.4", "body": "Android version code: `43`"}]
        self.adapter(existing)._require_newest_version(
            release.parse_pubspec("version: 1.2.4+43\n"), "v1.2.4"
        )

    def test_uses_pinned_floor_for_legacy_release_without_adapter_footer(self):
        legacy = [{"tag_name": "v0.1.1", "body": ""}]
        self.adapter(legacy)._require_newest_version(
            release.parse_pubspec("version: 1.0.1+2002\n"), "v1.0.1"
        )


class ReleaseMetadataTest(unittest.TestCase):
    class FakeApi:
        def __init__(self, references):
            self.references = references

        def request_json(self, method, path):
            assert method == "GET"
            assert path == "/git/refs/tags/v1.2.3"
            return self.references

    def adapter(self, references):
        adapter = object.__new__(release.ReleaseAdapter)
        adapter.api = self.FakeApi(references)
        adapter.operation = types.SimpleNamespace(revision="a" * 40)
        return adapter

    def test_verifies_exact_lightweight_tag(self):
        references = [{"ref": "refs/tags/v1.2.3", "object": {"sha": "a" * 40}}]
        forgejo_release = {
            "tag_name": "v1.2.3",
            "target_commitish": "a" * 40,
            "draft": False,
            "prerelease": False,
            "name": "Meal of Record 1.2.3",
            "body": "expected notes",
        }
        self.adapter(references)._verify_release_metadata(
            forgejo_release,
            "v1.2.3",
            release.parse_pubspec("version: 1.2.3+43\n"),
            False,
            "expected notes",
        )

    def test_rejects_changed_release_body(self):
        references = [{"ref": "refs/tags/v1.2.3", "object": {"sha": "a" * 40}}]
        forgejo_release = {
            "tag_name": "v1.2.3",
            "target_commitish": "a" * 40,
            "draft": False,
            "prerelease": False,
            "name": "Meal of Record 1.2.3",
            "body": "changed notes",
        }
        with self.assertRaises(release.ReleaseError):
            self.adapter(references)._verify_release_metadata(
                forgejo_release,
                "v1.2.3",
                release.parse_pubspec("version: 1.2.3+43\n"),
                False,
                "expected notes",
            )

    def test_rejects_ambiguous_tag_response(self):
        forgejo_release = {
            "tag_name": "v1.2.3",
            "target_commitish": "a" * 40,
            "draft": False,
            "prerelease": False,
            "name": "Meal of Record 1.2.3",
            "body": "expected notes",
        }
        with self.assertRaises(release.ReleaseError):
            self.adapter([])._verify_release_metadata(
                forgejo_release,
                "v1.2.3",
                release.parse_pubspec("version: 1.2.3+43\n"),
                False,
                "expected notes",
            )


class StateTest(unittest.TestCase):
    def valid_release_state(self):
        return {
            "version_name": "1.2.3-rc.1",
            "version_code": 43,
            "tag": "v1.2.3-rc.1",
            "asset_name": "meal-of-record-v1.2.3-rc.1-arm64-v8a.apk",
            "prerelease": True,
            "checksum_sha256": "a" * 64,
            "release_body": "expected notes",
        }

    def test_validates_persisted_release_state_types_and_consistency(self):
        version = release.validate_release_state(self.valid_release_state())
        self.assertEqual((version.name, version.code), ("1.2.3-rc.1", 43))

    def test_rejects_corrupt_persisted_release_state(self):
        for field, value in (
            ("version_code", "43"),
            ("version_code", True),
            ("tag", "v1.2.4"),
            ("prerelease", False),
            ("checksum_sha256", "invalid"),
            ("release_body", None),
        ):
            state = self.valid_release_state()
            state[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(release.ReleaseError):
                release.validate_release_state(state)

    def test_atomic_state_is_owner_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "operation" / "state.json"
            release.atomic_json(path, {"revision": "a" * 40})
            self.assertEqual(release.load_json(path), {"revision": "a" * 40})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
