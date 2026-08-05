# Android release signing recovery

Android updates must be signed by the same key as the installed application. Losing the key or its credentials would prevent future versions from updating existing installations.

This procedure intentionally contains no real paths, aliases, passwords, fingerprints, or key material.

## Recovery set

A complete recovery set consists of:

- the release keystore;
- the keystore password;
- the key alias; and
- the private-key password, if it differs from the keystore password.

The ignored `android/key.properties` file contains these details on the release machine. Keep them in a protected, recoverable location rather than relying on memory. Never put them in Git, Forgejo, CI settings, logs, or release notes.

Keep a secondary keystore copy on the NAS. Restrict it to the release owner and trusted NAS administrators using NAS access controls, encryption, or both. NAS snapshots and replication should retain equivalent protection.

## Local protection

The ignored signing configuration and its configured keystore must be readable and writable only by their owner:

```text
chmod 600 android/key.properties /path/to/release-key.jks
```

Both `key.properties` and common Android keystore extensions are ignored by Git. Signing files may remain outside the repository or in an ignored local location.

## Read-only recovery check

Use `keytool` directly against the NAS backup. It prompts for the keystore password and does not modify the file:

```text
read -r -s -p "Backup keystore path: " backup_keystore; echo
read -r -s -p "Key alias: " key_alias; echo
keytool -list -v -keystore "$backup_keystore" -alias "$key_alias"
unset backup_keystore key_alias
```

Download the exact published release APK from Forgejo rather than using a newly rebuilt APK as the reference. Print its signer certificate identity with Android SDK `apksigner`:

```text
apksigner verify --print-certs /path/to/published-release.apk
```

Compare the signer's SHA-256 certificate digest with the `SHA256` certificate fingerprint reported by `keytool`. The hexadecimal values must match; capitalization and colon separators do not matter.

Repeat this read-only check whenever the signing key or its backup changes.

## Recover after loss of the release machine

1. Install Flutter, Java, the Android SDK build tools, Python 3, and `keytool` on the replacement machine.
2. Clone the repository without adding signing data to Git.
3. Copy the protected keystore backup from the NAS to a local ignored location.
4. Restore `android/key.properties` using the securely recorded password and alias details.
5. Set both restored files to mode `600`.
6. Compare the restored keystore certificate fingerprint with the published reference APK.
7. Build through `./scripts/build_android_release`.

## Local release automation

`./scripts/build_android_release` checks that `android/key.properties` and its configured keystore exist and have owner-only permissions. It then invokes the project's Gradle wrapper and Flutter build integration.

Signing remains an explicit operation on the protected release machine. Do not copy the keystore or `key.properties` into the repository, a build artifact, or Forgejo Actions.
