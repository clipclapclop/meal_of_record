# Development

## Project check

Run the repository-owned aggregate check before proposing a change:

```sh
./scripts/check
```

The check resolves only versions allowed by `pubspec.lock`, requires a clean analyzer run, and runs the complete Flutter test suite. It was established with Flutter 3.44.0 and Dart 3.12.0. Upgrade the toolchain and resulting compatibility files deliberately rather than allowing an unrelated change to rewrite them.

Dependency resolution runs offline so the same command works in Repflow's network-isolated exact-revision sandbox. Populate the trusted host's Pub cache deliberately with `flutter pub get --enforce-lockfile` before running the check when required; do not give the sandbox network access or credentials as a shortcut.

Repository-wide formatting debt is tracked separately. Do not mix a bulk formatting pass into a behavioral change.

## Stale Flutter artifacts

After changing Flutter SDK versions, local generated artifacts can become incompatible with the new engine. A symptom seen in widget tests is a shader error similar to:

```text
Unsupported runtime stages format version
```

This is a generated-cache problem, not a reason to weaken the test. Clear and recreate ignored artifacts, then rerun the check:

```sh
flutter clean
flutter pub get --enforce-lockfile
./scripts/check
```

If the locked dependency resolution is no longer valid for the chosen SDK, handle the SDK and lockfile update as an explicit toolchain change.
