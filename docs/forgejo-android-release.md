# Forgejo Android releases

Meal of Record releases are built and published only from the trusted development machine through Repflow's manually authorized `release` stage. The process publishes one signed `arm64-v8a` APK to Forgejo for Obtainium. It does not invoke Zapstore, migrate historical GitHub assets, or release ordinary feature pull requests.

## Release contract

A releasable pull request must change exactly these two files:

- `pubspec.yaml`, with a higher semantic version and a higher Android build number; and
- `CHANGELOG.md`, with one nonempty `## [version]` section matching the pubspec version.

The version PR must be merged before anyone explicitly authorizes `repflow release`. The adapter receives that pull request's exact merged revision from Repflow, downloads that revision from Forgejo into host-owned state, and builds it without trusting the current checkout.

Tags and assets use these names:

```text
v<version>
meal-of-record-v<version>-arm64-v8a.apk
```

A semantic prerelease suffix such as `-adapter-test.1` creates a Forgejo prerelease. A normal semantic version creates a normal release.

The adapter refuses versions at or below the historical published APK floor. The historical GitHub asset tagged `v0.1.1` internally identifies itself as Android version name `1.0.0` and version code `2001`; the first future version PR must exceed both values. Every later version PR must also exceed its base revision and every semantic Forgejo release.

## Host-owned installation

The reviewed adapter source is `scripts/meal_of_record_release.py`. Install a copy outside Git and create its private state directory:

```text
install -d -m 700 ~/.local/libexec
install -m 700 scripts/meal_of_record_release.py ~/.local/libexec/meal-of-record-release
install -d -m 700 ~/.local/state/meal-of-record-release
install -d -m 700 ~/.config/meal-of-record-release
```

`REPFLOW.md` pins the installed executable and state directory by absolute path. After a reviewed adapter change reaches the protected branch, reinstall that protected copy before using it. Do not install an unreviewed pull-request copy for a release.

Repflow and the adapter both serialize local operations. Repflow retains its own operation recovery record, while adapter state is stored under:

```text
~/.local/state/meal-of-record-release/operations/
```

Do not delete or transfer either recovery state while an operation is incomplete or uncertain.

## Dedicated Forgejo credential

Create a separate Forgejo access token for release automation. Restrict it to the `chad/meal_of_record` repository and the repository-write scope needed to create tags, releases, and assets; grant no organization, administration, package, or user scope. This is separate from Repflow implementation, review, and merge credentials.

Store only the token in this owner-only file, without adding it to shell startup files or Git:

```text
~/.config/meal-of-record-release/forgejo-token
```

Set the file to mode `600`. Never pass the token on a command line or paste it into an issue, log, release note, or adapter output.

Create owner-only `~/.config/meal-of-record-release/config.json` with this structure and host-specific absolute paths:

```json
{
  "forgejo_url": "https://git.oorangy.com",
  "repository": "chad/meal_of_record",
  "token_file": "/absolute/path/to/forgejo-token",
  "signing_properties": "/absolute/path/to/android/key.properties",
  "expected_certificate_sha256": "host-pinned-64-character-certificate-digest",
  "minimum_version_name": "1.0.0",
  "minimum_version_code": 2001,
  "android_sdk": "/absolute/path/to/Android/Sdk",
  "flutter_executable": "/absolute/path/to/flutter",
  "java_home": "/absolute/path/to/a/supported/JDK",
  "state_directory": "/home/chad/.local/state/meal-of-record-release"
}
```

Set this file to mode `600`. Pin the expected certificate digest from the already-published reference APK, independently of the APK being built. Keep the real digest and signing paths outside Git and Forgejo. The signing configuration and keystore must remain owner-only as described in [Android release signing recovery](android-release-signing.md).

Validate host configuration without building or publishing:

```text
~/.local/libexec/meal-of-record-release doctor
```

The doctor result is bounded and does not print the credential, signing paths, certificate digest, or account identity.

## Build and publication checks

Execution fails closed unless all of these conditions hold:

- Repflow supplies the configured repository, exact merged revision, pull request, and stable operation ID;
- the pull request is merged at that revision and changes only the two release metadata files;
- source and base archives resolve to the exact Forgejo commit IDs;
- semantic version and Android build number increase monotonically;
- release notes match the exact version;
- signing configuration and credential files are regular, owner-only files;
- the build produces exactly the expected arm64 APK path;
- APK signing verifies and its signer matches the independently pinned certificate;
- application ID is `com.clipclapclop.meal_of_record`;
- APK version name and code match `pubspec.yaml`;
- native libraries contain only `arm64-v8a`; and
- the local and downloaded Forgejo asset SHA-256 checksums match.

Execution persists the intended checksum before creating a Forgejo release. A retry with the same operation ID reconciles an existing tag, release, or asset rather than replacing it. A conflicting tag, duplicate asset, changed operation binding, or publication without matching local recovery state fails closed.

The adapter returns only one small JSON object to Repflow. It suppresses build output and never includes credentials, local sensitive paths, or certificate values in its summary.

## Test prerelease and first production release

Release authority is loaded from a pull request's protected pre-merge policy base. Therefore the pull request that first adds this adapter cannot release itself.

After this policy is merged:

1. Reinstall the adapter from the protected branch.
2. Validate the credential and host configuration with `doctor`.
3. Create a dedicated version pull request changing only `pubspec.yaml` and `CHANGELOG.md`. Use a version above the historical floor, such as `1.0.1-adapter-test.1+2002`.
4. Merge that pull request through Repflow.
5. Explicitly authorize `repflow release` for the merged test pull request.
6. Confirm Forgejo shows a prerelease with one APK and that Repflow reports verified status.
7. For the first production release, use a version and build number above the test release, such as `1.0.1+2003`.

The test prerelease is retained as publication evidence. The adapter has no rollback command and never deletes or replaces a tag, release, or asset because that behavior is not demonstrably safe for installed Android updates.

## Recovery

Retry an interrupted or uncertain operation through Repflow using the same merged pull request and the same local Repflow recovery state. Repflow preserves the stable operation ID, and the adapter reconciles its persisted intent with Forgejo.

Do not manually create, delete, rename, or replace the operation's tag, release, or asset during recovery. If local state is lost or Forgejo conflicts with it, stop and investigate; do not create a new operation to bypass the conflict. There is intentionally no automatic rollback.
