import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackupConfigService {
  static const String _keyAutoBackupEnabled = 'backup_auto_enabled';
  static const String _keyRetentionCount = 'backup_retention_count';
  static const String _keyLastBackupTime = 'backup_last_time';
  static const String _keyIsDirty = 'backup_is_dirty';

  // NAS configuration keys
  static const String _keyNasHost = 'nas_host';
  static const String _keyNasPort = 'nas_port';
  static const String _keyNasPath = 'nas_path';
  static const String _keyNasUseHttps = 'nas_use_https';
  static const String _keyNasAllowSelfSigned = 'nas_allow_self_signed';

  // Failure tracking
  static const String _keyConsecutiveFailures = 'backup_consecutive_failures';

  // Local backup configuration keys
  static const String _keyLocalBackupEnabled = 'local_backup_enabled';
  static const String _keyLocalBackupPath = 'local_backup_path';
  static const String _keyLocalBackupLastTime = 'local_backup_last_time';
  static const String _keyLocalBackupScheduledHour =
      'local_backup_scheduled_hour';
  static const String _keyLocalBackupScheduledMinute =
      'local_backup_scheduled_minute';

  // Secure storage keys
  static const String _keyNasUsername = 'nas_username';
  static const String _keyNasPassword = 'nas_password';

  /// How long to wait after the last write before triggering a backup.
  static const Duration debounceDuration = Duration(seconds: 30);

  // Singleton instance
  static final BackupConfigService instance = BackupConfigService._();
  BackupConfigService._();

  // Allow injecting a custom FlutterSecureStorage for testing
  FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  set secureStorage(FlutterSecureStorage storage) => _secureStorage = storage;

  /// Called when the debounce timer fires after data changes settle.
  /// Wired in main.dart to trigger backup attempts.
  VoidCallback? onDebouncedDirty;

  Timer? _debounceTimer;

  /// Cancel any pending debounce timer. Useful in tests to avoid
  /// "Timer is still pending" failures.
  void cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoBackupEnabled, enabled);
  }

  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoBackupEnabled) ?? false;
  }

  Future<void> setRetentionCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRetentionCount, count);
  }

  Future<int> getRetentionCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyRetentionCount) ?? 7; // Default to 7
  }

  Future<void> markDirty() async {
    final prefs = await SharedPreferences.getInstance();
    // Only write if not already dirty to save IO
    if (prefs.getBool(_keyIsDirty) != true) {
      await prefs.setBool(_keyIsDirty, true);
    }

    // Reset the debounce timer. When writes stop for 30 seconds, fire backup.
    // Only start the timer if a callback is registered (avoids pending-timer
    // issues in tests where no backup wiring exists).
    if (onDebouncedDirty != null) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounceDuration, () {
        debugPrint('BackupConfigService: Debounce fired — triggering backups.');
        onDebouncedDirty?.call();
      });
    }
  }

  Future<void> clearDirty() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsDirty, false);
  }

  Future<bool> isDirty() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsDirty) ?? false;
  }

  Future<void> updateLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyLastBackupTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyLastBackupTime);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  // --- NAS Configuration ---

  Future<void> setNasHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNasHost, host);
  }

  Future<String?> getNasHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNasHost);
  }

  Future<void> setNasPort(int? port) async {
    final prefs = await SharedPreferences.getInstance();
    if (port != null) {
      await prefs.setInt(_keyNasPort, port);
    } else {
      await prefs.remove(_keyNasPort);
    }
  }

  Future<int?> getNasPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyNasPort);
  }

  Future<void> setNasPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNasPath, path);
  }

  Future<String?> getNasPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNasPath);
  }

  Future<void> setNasUseHttps(bool useHttps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNasUseHttps, useHttps);
  }

  Future<bool> getNasUseHttps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNasUseHttps) ?? true;
  }

  Future<void> setNasAllowSelfSigned(bool allow) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNasAllowSelfSigned, allow);
  }

  Future<bool> getNasAllowSelfSigned() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNasAllowSelfSigned) ?? false;
  }

  // --- Failure Tracking ---

  Future<void> recordBackupFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyConsecutiveFailures) ?? 0;
    await prefs.setInt(_keyConsecutiveFailures, current + 1);
  }

  Future<void> recordBackupSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyConsecutiveFailures, 0);
  }

  Future<int> getConsecutiveFailures() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyConsecutiveFailures) ?? 0;
  }

  // --- NAS Credentials (Secure Storage) ---

  Future<void> saveNasCredentials(String username, String password) async {
    await _secureStorage.write(key: _keyNasUsername, value: username);
    await _secureStorage.write(key: _keyNasPassword, value: password);
  }

  Future<(String?, String?)> getNasCredentials() async {
    final username = await _secureStorage.read(key: _keyNasUsername);
    final password = await _secureStorage.read(key: _keyNasPassword);
    return (username, password);
  }

  Future<void> clearNasCredentials() async {
    await _secureStorage.delete(key: _keyNasUsername);
    await _secureStorage.delete(key: _keyNasPassword);
  }

  // --- Local Backup Configuration ---

  Future<void> setLocalBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLocalBackupEnabled, enabled);
  }

  Future<bool> isLocalBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLocalBackupEnabled) ?? false;
  }

  Future<void> setLocalBackupPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString(_keyLocalBackupPath, path);
    } else {
      await prefs.remove(_keyLocalBackupPath);
    }
  }

  Future<String?> getLocalBackupPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocalBackupPath);
  }

  Future<void> updateLocalBackupLastTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyLocalBackupLastTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<DateTime?> getLocalBackupLastTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyLocalBackupLastTime);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Set scheduled time for local backup. Pass null to clear (run on any open).
  Future<void> setLocalBackupScheduledTime(int? hour, int? minute) async {
    final prefs = await SharedPreferences.getInstance();
    if (hour != null && minute != null) {
      await prefs.setInt(_keyLocalBackupScheduledHour, hour);
      await prefs.setInt(_keyLocalBackupScheduledMinute, minute);
    } else {
      await prefs.remove(_keyLocalBackupScheduledHour);
      await prefs.remove(_keyLocalBackupScheduledMinute);
    }
  }

  /// Returns (hour, minute) or null if no scheduled time is set.
  Future<(int, int)?> getLocalBackupScheduledTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_keyLocalBackupScheduledHour);
    final minute = prefs.getInt(_keyLocalBackupScheduledMinute);
    if (hour != null && minute != null) return (hour, minute);
    return null;
  }

  Future<bool> isLocalBackupConfigured() async {
    final path = await getLocalBackupPath();
    return path != null && path.isNotEmpty;
  }

  /// Returns true if local backup should run now based on the schedule.
  /// If no scheduled time, uses 24-hour cooldown. If scheduled, runs once
  /// after the scheduled time each day.
  Future<bool> shouldRunLocalBackup() async {
    final lastBackup = await getLocalBackupLastTime();
    final schedule = await getLocalBackupScheduledTime();

    if (schedule == null) {
      // No schedule: use 24-hour cooldown
      if (lastBackup == null) return true;
      return DateTime.now().difference(lastBackup) >= const Duration(hours: 24);
    }

    final (hour, minute) = schedule;
    final now = DateTime.now();
    final scheduledToday = DateTime(now.year, now.month, now.day, hour, minute);

    // Haven't reached scheduled time today
    if (now.isBefore(scheduledToday)) return false;

    // Run if we've never backed up, or last backup was before today's schedule
    if (lastBackup == null) return true;
    return lastBackup.isBefore(scheduledToday);
  }

  /// Returns true if host, path, and credentials are all set.
  Future<bool> isNasConfigured() async {
    final host = await getNasHost();
    final path = await getNasPath();
    final (username, password) = await getNasCredentials();
    return host != null &&
        host.isNotEmpty &&
        path != null &&
        path.isNotEmpty &&
        username != null &&
        username.isNotEmpty &&
        password != null &&
        password.isNotEmpty;
  }
}
