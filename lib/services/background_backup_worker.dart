import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:meal_of_record/services/backup_config_service.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/nas_backup_service.dart';

/// Attempts an automatic NAS backup if enabled, configured, and the 24-hour
/// cooldown has elapsed.
///
/// If [force] is true, skips the cooldown check (used when the user first
/// enables auto-backup).
///
/// Runs silently — logs via debugPrint but never throws.
Future<bool> tryAutoBackup({
  BackupConfigService? configService,
  NasBackupService? nasService,
  bool force = false,
}) async {
  final config = configService ?? BackupConfigService.instance;
  final nas = nasService ?? NasBackupService.instance;

  try {
    final isEnabled = await config.isAutoBackupEnabled();
    if (!isEnabled) {
      debugPrint('tryAutoBackup: Auto backup disabled. Skipping.');
      return false;
    }

    if (!force) {
      final lastBackup = await config.getLastBackupTime();
      if (lastBackup != null) {
        final elapsed = DateTime.now().difference(lastBackup);
        if (elapsed < const Duration(hours: 24)) {
          debugPrint(
            'tryAutoBackup: Last backup was ${elapsed.inHours}h ago. Skipping.',
          );
          return false;
        }
      }
    }

    final isConfigured = await config.isNasConfigured();
    if (!isConfigured) {
      debugPrint('tryAutoBackup: NAS not configured. Skipping.');
      return false;
    }

    debugPrint('tryAutoBackup: Starting backup...');
    final zipFile = await DatabaseService.instance.exportBackupAsZip();

    final retention = await config.getRetentionCount();
    final success = await nas.uploadBackup(zipFile, retentionCount: retention);

    // Clean up temp zip and its temp directory
    try {
      await zipFile.parent.delete(recursive: true);
    } catch (_) {}

    if (success) {
      await config.clearDirty();
      await config.updateLastBackupTime();
      await config.recordBackupSuccess();
      debugPrint('tryAutoBackup: Backup successful!');
      return true;
    } else {
      await config.recordBackupFailure();
      debugPrint('tryAutoBackup: Upload failed.');
      return false;
    }
  } catch (e) {
    debugPrint('tryAutoBackup: Error: $e');
    try {
      await config.recordBackupFailure();
    } catch (_) {}
    return false;
  }
}

/// Attempts an automatic local folder backup if enabled and configured.
///
/// Writes a fixed filename `meal_of_record.zip`, overwriting any previous
/// backup so that external tools (e.g. Syncthing) handle versioning.
/// Because this is just a cheap file copy, there is no cooldown — every
/// debounce trigger produces a fresh backup.
///
/// Runs silently — logs via debugPrint but never throws.
Future<bool> tryAutoLocalBackup({BackupConfigService? configService}) async {
  final config = configService ?? BackupConfigService.instance;

  try {
    final isEnabled = await config.isLocalBackupEnabled();
    if (!isEnabled) {
      debugPrint('tryAutoLocalBackup: Local backup disabled. Skipping.');
      return false;
    }

    final isConfigured = await config.isLocalBackupConfigured();
    if (!isConfigured) {
      debugPrint('tryAutoLocalBackup: No backup path configured. Skipping.');
      return false;
    }

    final backupPath = await config.getLocalBackupPath();
    if (backupPath == null) return false;

    debugPrint('tryAutoLocalBackup: Starting backup...');
    final zipFile = await DatabaseService.instance.exportBackupAsZip();

    try {
      final destDir = Directory(backupPath);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final destFile = File('$backupPath/meal_of_record.zip');
      await zipFile.copy(destFile.path);
    } finally {
      try {
        await zipFile.parent.delete(recursive: true);
      } catch (_) {}
    }

    await config.clearDirty();
    await config.updateLocalBackupLastTime();
    debugPrint('tryAutoLocalBackup: Backup successful!');
    return true;
  } catch (e) {
    debugPrint('tryAutoLocalBackup: Error: $e');
    return false;
  }
}
