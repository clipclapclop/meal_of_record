# Data integrity and release smoke test

This document defines the persisted-state inventory, supported upgrade paths, and the short data-integrity check required before a version release.

## Persisted-state inventory

| State | Storage | Backup behavior |
| --- | --- | --- |
| Custom/imported foods, historical food versions, portions, barcodes | `live.db` | Included |
| Recipes, nested recipe relationships, categories, ordering, and links | `live.db` | Included |
| Food and recipe logs | `live.db` | Included |
| Weight history | `live.db` | Included |
| Containers | `live.db` | Included |
| Food, recipe, and container image references | `live.db` | Included |
| App-owned image files | `app_images/` | Included |
| Goal settings and current macro targets | Shared preferences | Included |
| Historical target snapshots | Shared preferences | Included |
| Welcome state and QR image-sharing preference | Shared preferences | Included |
| NAS credentials | Secure storage | Excluded intentionally; credentials stay device-owned |
| NAS/local destination, retention, schedule, failure count, and last-run state | Shared preferences | Excluded intentionally; these settings describe the restoring device and backup transport |
| Bundled reference foods | `assets/reference.db` | Excluded intentionally; the app version supplies this read-only database |
| Log queue and current screen state | Memory only | Not persisted and therefore not backed up |

A restore replaces the live database, app-owned images, and portable preferences as one validated operation. Missing portable preferences are cleared rather than mixed with values from the destination device. Legacy `.db` imports replace only the database because they never contained images or preferences.

## Schema and format coverage

The current live schema is **v14**. The only prior schemas shipped in tagged production releases (`v0.1.0` and `v0.1.1`) were **v13**, so the supported production upgrade range is v13 → v14.

Coverage is maintained as follows:

- `test/fixtures/live_schema_v13.sql` is a representative, non-personal production fixture.
- `test/services/live_database_migration_test.dart` performs the real Drift migration and checks every persisted table, relationships, integrity, and an historical logged-food snapshot.
- `test/services/database_backup_restore_test.dart` covers current-format round trips across databases, images, foods, recipes, nested relationships, logs, weights, goals, target history, containers, barcodes, and preferences.
- The backup tests also verify safe rejection of interrupted, malformed, incomplete, path-unsafe, future-format, and future-schema input.

Schemas v1–v12 were development-only snapshots, were not present in a tagged production release, and do not have a complete non-destructive migration chain. Restore rejects them before replacing live data. A future schema is also rejected by an older app.

Backup zip format v2 is current. Zips created by the prior unversioned/v1 exporter remain accepted when they contain a supported database and `settings.json`. New-format backups additionally require `manifest.json`; a zip missing any portable settings is rejected instead of mixing data from two devices.

## Required regression updates

Whenever the live schema changes:

1. Add a non-personal fixture for every newly supported prior production schema.
2. Run the fixture through the actual `LiveDatabase` migration, not copied migration SQL.
3. Assert row counts, foreign keys, relationships, and historical nutritional meaning.
4. Update `currentSchemaVersion`, the coverage statement above, and the smoke test if needed.

Whenever the backup format or persisted-state inventory changes:

1. Bump `backupFormatVersion` for an incompatible format change.
2. Extend the round-trip fixture and assertions for every new state item.
3. Add backward-compatibility or explicit safe-rejection coverage.
4. Keep malformed, incomplete, interrupted, incompatible, size-bound, duplicate-entry, and path-traversal cases covered.

Never derive fixtures from personal databases, backups, settings, credentials, or images.

## Pre-release data-integrity smoke test

Use only synthetic data on a test device or emulator.

1. Install the previous tagged release and create two versions of one food with different nutrition; log the old version.
2. Create a recipe using that food, a nested recipe, category, barcode, weight, container, goals, and target history. Attach distinct food, recipe, and container images.
3. Export a backup and keep a copy outside app storage.
4. Upgrade in place to the release candidate. Confirm the old log still uses the old nutrition, while search shows the current food version. Open both recipes and confirm ingredient/category/order relationships, goals, weights, containers, barcodes, and images.
5. Add one post-upgrade log, export again, then change or delete representative data and restore that export. Repeat the checks from step 4 and confirm the post-upgrade log returns.
6. Attempt to restore a truncated copy and a non-zip file. Confirm both are rejected and the verified live data remains unchanged.
7. Run `./scripts/check` from a clean checkout.
