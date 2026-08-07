import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/screen_background.dart';
import 'package:file_picker/file_picker.dart';
import 'package:meal_of_record/services/backup_config_service.dart';
import 'package:meal_of_record/services/nas_backup_service.dart';
import 'package:meal_of_record/services/background_backup_worker.dart';
import 'package:intl/intl.dart';
import 'package:meal_of_record/utils/ui_utils.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';

class DataManagementScreen extends StatefulWidget {
  final NasBackupService? nasBackupService;
  final BackupConfigService? backupConfigService;

  const DataManagementScreen({
    super.key,
    this.nasBackupService,
    this.backupConfigService,
  });

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool _isRestoring = false;

  // NAS Backup State
  bool _isAutoBackupEnabled = false;
  int _retentionCount = 7;
  bool _isNasConfigured = false;
  String? _nasDisplayAddress;
  String? _nasConnectionNote;
  DateTime? _lastBackupTime;
  bool _isLoadingSettings = true;

  // Local Backup State
  bool _isLocalBackupEnabled = false;
  String? _localBackupPath;
  DateTime? _localBackupLastTime;
  (int, int)? _localBackupScheduledTime;

  late final NasBackupService _nasService;
  late final BackupConfigService _backupConfigService;

  @override
  void initState() {
    super.initState();
    _nasService = widget.nasBackupService ?? NasBackupService.instance;
    _backupConfigService =
        widget.backupConfigService ?? BackupConfigService.instance;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final config = _backupConfigService;

    final enabled = await config.isAutoBackupEnabled();
    final retention = await config.getRetentionCount();
    final lastTime = await config.getLastBackupTime();
    final configured = await config.isNasConfigured();

    // Local backup settings
    final localEnabled = await config.isLocalBackupEnabled();
    final localPath = await config.getLocalBackupPath();
    final localLastTime = await config.getLocalBackupLastTime();
    final localSchedule = await config.getLocalBackupScheduledTime();

    String? displayAddr;
    String? connNote;
    if (configured) {
      final host = await config.getNasHost();
      final port = await config.getNasPort();
      final path = await config.getNasPath();
      final useHttps = await config.getNasUseHttps();
      final allowSelfSigned = await config.getNasAllowSelfSigned();

      final portStr = port != null ? ':$port' : '';
      displayAddr = '$host$portStr$path';

      if (!useHttps) {
        connNote = 'HTTP';
      } else if (allowSelfSigned) {
        connNote = 'HTTPS (self-signed certificate)';
      } else {
        connNote = 'HTTPS';
      }
    }

    if (mounted) {
      setState(() {
        _isAutoBackupEnabled = enabled;
        _retentionCount = retention;
        _lastBackupTime = lastTime;
        _isNasConfigured = configured;
        _nasDisplayAddress = displayAddr;
        _nasConnectionNote = connNote;
        _isLoadingSettings = false;
        _isLocalBackupEnabled = localEnabled;
        _localBackupPath = localPath;
        _localBackupLastTime = localLastTime;
        _localBackupScheduledTime = localSchedule;
      });
    }
  }

  Future<void> _toggleAutoBackup(bool value) async {
    if (value && !_isNasConfigured) {
      // Need to configure first
      final configured = await _showNasConfigDialog();
      if (configured != true) return;
    }

    setState(() => _isLoadingSettings = true);

    try {
      await _backupConfigService.setAutoBackupEnabled(value);

      if (value) {
        // Perform first backup immediately
        tryAutoBackup(force: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('NAS backup enabled!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('NAS backup disabled.')),
          );
        }
      }

      await _loadSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update backup settings: $e')),
        );
        setState(() => _isLoadingSettings = false);
      }
    }
  }

  Future<void> _updateRetention(double value) async {
    final intVal = value.toInt();
    setState(() => _retentionCount = intVal);
    await _backupConfigService.setRetentionCount(intVal);
  }

  Future<void> _testConnection() async {
    setState(() => _isRestoring = true);
    try {
      final error = await _nasService.testConnection();
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection successful!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<bool?> _showNasConfigDialog() async {
    final config = _backupConfigService;
    final hostController = TextEditingController(
      text: await config.getNasHost() ?? '',
    );
    final portText = await config.getNasPort();
    final portController = TextEditingController(
      text: portText?.toString() ?? '',
    );
    final pathController = TextEditingController(
      text: await config.getNasPath() ?? '/backups/meal_of_record',
    );
    final (existingUser, existingPass) = await config.getNasCredentials();
    final usernameController = TextEditingController(
      text: existingUser ?? '',
    );
    final passwordController = TextEditingController(
      text: existingPass ?? '',
    );
    var useHttps = await config.getNasUseHttps();
    var allowSelfSigned = await config.getNasAllowSelfSigned();

    if (!mounted) return null;

    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('NAS Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: hostController,
                  decoration: const InputDecoration(
                    labelText: 'Server Address',
                    hintText: '192.168.1.100 or nas.local',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portController,
                  decoration: InputDecoration(
                    labelText: 'Port (optional)',
                    hintText: useHttps ? '443' : '80',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pathController,
                  decoration: const InputDecoration(
                    labelText: 'Backup Folder',
                    hintText: '/backups/meal_of_record',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Use HTTPS'),
                  value: useHttps,
                  onChanged: (v) => setDialogState(() => useHttps = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (useHttps)
                  SwitchListTile(
                    title: const Text('Allow self-signed certificate'),
                    value: allowSelfSigned,
                    onChanged: (v) =>
                        setDialogState(() => allowSelfSigned = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.wifi_find, size: 18),
                    label: const Text('Test Connection'),
                    onPressed: () async {
                      // Save temporarily to test
                      await _saveNasConfig(
                        hostController.text,
                        portController.text,
                        pathController.text,
                        usernameController.text,
                        passwordController.text,
                        useHttps,
                        allowSelfSigned,
                      );
                      final error = await _nasService.testConnection();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(error ?? 'Connection successful!'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () async {
                await _saveNasConfig(
                  hostController.text,
                  portController.text,
                  pathController.text,
                  usernameController.text,
                  passwordController.text,
                  useHttps,
                  allowSelfSigned,
                );
                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNasConfig(
    String host,
    String portStr,
    String path,
    String username,
    String password,
    bool useHttps,
    bool allowSelfSigned,
  ) async {
    final config = _backupConfigService;
    await config.setNasHost(host.trim());
    final port = int.tryParse(portStr.trim());
    await config.setNasPort(port);
    await config.setNasPath(path.trim());
    await config.setNasUseHttps(useHttps);
    await config.setNasAllowSelfSigned(allowSelfSigned);
    if (username.isNotEmpty && password.isNotEmpty) {
      await config.saveNasCredentials(username.trim(), password);
    }
  }

  Future<void> _toggleLocalBackup(bool value) async {
    if (value) {
      if (!await _ensureStoragePermission()) return;
      if (_localBackupPath == null) {
        final picked = await _pickLocalFolder();
        if (picked == null) return;
      }
    }
    await _backupConfigService.setLocalBackupEnabled(value);
    if (value) {
      tryAutoLocalBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Local backup enabled!')),
        );
      }
    }
    await _loadSettings();
  }

  Future<String?> _pickLocalFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Local Backup Folder',
    );
    if (path != null) {
      await _backupConfigService.setLocalBackupPath(path);
      await _loadSettings();
    }
    return path;
  }

  Future<void> _showLocalBackupTimePicker() async {
    final current = _localBackupScheduledTime;
    final initialTime = current != null
        ? TimeOfDay(hour: current.$1, minute: current.$2)
        : const TimeOfDay(hour: 8, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Schedule daily backup time',
    );

    if (picked != null) {
      await _backupConfigService.setLocalBackupScheduledTime(
        picked.hour,
        picked.minute,
      );
      await _loadSettings();
    }
  }

  Future<void> _clearLocalBackupSchedule() async {
    await _backupConfigService.setLocalBackupScheduledTime(null, null);
    await _loadSettings();
  }

  /// Returns true if the app has (or was just granted) storage write permission.
  /// On non-Android platforms always returns true.
  Future<bool> _ensureStoragePermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Storage permission required. Grant "All files access" in Settings.',
          ),
        ),
      );
    }
    return false;
  }

  Future<void> _backupToLocalNow() async {
    if (_localBackupPath == null) return;
    if (!await _ensureStoragePermission()) return;
    setState(() => _isRestoring = true);
    try {
      final zipFile = await DatabaseService.instance.exportBackupAsZip();
      try {
        final destDir = Directory(_localBackupPath!);
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        final destFile = File('$_localBackupPath/meal_of_record.zip');
        await zipFile.copy(destFile.path);
      } finally {
        try { await zipFile.parent.delete(recursive: true); } catch (_) {}
      }
      await _backupConfigService.clearDirty();
      await _backupConfigService.updateLocalBackupLastTime();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local backup successful!')),
      );
      await _loadSettings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Local backup failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _exportBackup() async {
    if (_localBackupPath == null) return;
    if (!await _ensureStoragePermission()) return;
    try {
      setState(() => _isRestoring = true);
      final zipFile = await DatabaseService.instance.exportBackupAsZip();
      try {
        final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
        final destFile = File('$_localBackupPath/meal_of_record_$dateStr.zip');
        await zipFile.copy(destFile.path);
      } finally {
        try { await zipFile.parent.delete(recursive: true); } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export successful!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _backupToNas() async {
    try {
      setState(() => _isRestoring = true);
      final zipFile = await DatabaseService.instance.exportBackupAsZip();

      final retention = await _backupConfigService.getRetentionCount();
      final success = await _nasService.uploadBackup(
        zipFile,
        retentionCount: retention,
      );

      // Clean up temp zip and its temp directory
      try {
        await zipFile.parent.delete(recursive: true);
      } catch (_) {}

      if (success) {
        await _backupConfigService.clearDirty();
        await _backupConfigService.updateLastBackupTime();
        await _backupConfigService.recordBackupSuccess();
        final lastTime = await _backupConfigService.getLastBackupTime();
        if (mounted) {
          setState(() => _lastBackupTime = lastTime);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('NAS backup successful!')),
          );
        }
      } else {
        await _backupConfigService.recordBackupFailure();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('NAS backup upload failed.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NAS backup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (!mounted) return;

    if (result != null && result.files.single.path != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Backup?'),
          content: const Text(
            'This will overwrite all your current logs and recipes. This action cannot be undone unless you have another backup.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('RESTORE', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (confirmed == true) {
        setState(() => _isRestoring = true);
        final goalsProvider = context.read<GoalsProvider>();
        try {
          final backupFile = File(result.files.single.path!);
          await DatabaseService.instance.restoreDatabase(backupFile);
          // Reload goal settings from restored SharedPreferences
          await goalsProvider.reload();
          if (mounted) {
            await UiUtils.showAutoDismissDialog(
              context,
              'Backup restored successfully!',
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
          }
        } finally {
          if (mounted) setState(() => _isRestoring = false);
        }
      }
    }
  }

  Future<void> _restoreFromNas() async {
    setState(() => _isRestoring = true);
    try {
      final backups = await _nasService.listBackups();

      if (backups.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No NAS backups found.')),
          );
        }
        return;
      }

      if (!mounted) return;

      final selectedBackup = await showDialog<NasBackupFile>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select NAS Backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backups.length,
              itemBuilder: (context, index) {
                final b = backups[index];
                final date = b.modified != null
                    ? DateFormat('MM/dd/yyyy HH:mm').format(b.modified!)
                    : 'Unknown Date';
                final size = b.size != null
                    ? '${(b.size! / 1024).toStringAsFixed(1)} KB'
                    : 'Unknown Size';

                return ListTile(
                  title: Text(date),
                  subtitle: Text(size),
                  onTap: () => Navigator.pop(context, b),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (selectedBackup != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restore NAS Backup?'),
            content: const Text(
              'This will overwrite all your current logs and recipes. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'RESTORE',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (confirmed == true) {
          final goalsProvider = context.read<GoalsProvider>();
          final tempFile = await _nasService.downloadBackup(
            selectedBackup.href,
          );
          if (tempFile != null) {
            await DatabaseService.instance.restoreDatabase(tempFile);
            await tempFile.delete();
            // Reload goal settings from restored SharedPreferences
            await goalsProvider.reload();
            if (mounted) {
              await UiUtils.showAutoDismissDialog(
                context,
                'NAS backup restored successfully!',
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Download failed.')));
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      appBar: AppBar(
        title: const Text('Data Management'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      child: _isRestoring
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildNasBackupCard(),
                const SizedBox(height: 10),
                _buildLocalBackupCard(),
                const SizedBox(height: 10),
                const Text(
                  'Manual Backup',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.grey[900],
                  child: ListTile(
                    leading: Icon(Icons.file_upload,
                        color: _localBackupPath != null ? Colors.blue : Colors.grey),
                    title: const Text('Export Now'),
                    subtitle: Text(
                      _localBackupPath != null
                          ? 'Save a dated backup to your local backup folder.'
                          : 'Select a local backup folder above first.',
                      style: TextStyle(
                        color: _localBackupPath != null ? null : Colors.grey,
                      ),
                    ),
                    onTap: _localBackupPath != null ? _exportBackup : null,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.grey[900],
                  child: ListTile(
                    leading: const Icon(
                      Icons.file_download,
                      color: Colors.green,
                    ),
                    title: const Text('Restore from File'),
                    subtitle: const Text(
                      'Import from a backup .zip or .db file.',
                    ),
                    onTap: _importBackup,
                  ),
                ),
                if (_isNasConfigured) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.grey[900],
                    child: ListTile(
                      leading: const Icon(
                        Icons.cloud_upload,
                        color: Colors.orange,
                      ),
                      title: const Text('Backup to NAS'),
                      subtitle: const Text(
                        'Upload a backup to your NAS now.',
                      ),
                      onTap: _backupToNas,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.grey[900],
                    child: ListTile(
                      leading: const Icon(
                        Icons.cloud_download,
                        color: Colors.orange,
                      ),
                      title: const Text('Restore from NAS'),
                      subtitle: const Text(
                        'Select a backup to restore from your NAS.',
                      ),
                      onTap: _restoreFromNas,
                    ),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'Note: Restoring data will replace your current recipes and food logs. Make sure you have a backup of your current data if you still need it.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLocalBackupCard() {
    if (_isLoadingSettings) return const SizedBox.shrink();

    final schedule = _localBackupScheduledTime;
    final scheduleLabel = schedule != null
        ? TimeOfDay(hour: schedule.$1, minute: schedule.$2).format(context)
        : null;

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_special, color: Colors.teal),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Local Backup',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _isLocalBackupEnabled,
                  onChanged: _toggleLocalBackup,
                  activeThumbColor: Colors.teal,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28.0, top: 4.0),
              child: Text(
                'Overwrites a single file — pair with Syncthing for versioning.',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 28.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: Text(
                      _localBackupPath != null ? 'Change Folder' : 'Select Folder',
                    ),
                    onPressed: _pickLocalFolder,
                  ),
                  if (_isLocalBackupEnabled)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.backup, size: 16),
                      label: const Text('Backup Now'),
                      onPressed: _backupToLocalNow,
                    ),
                ],
              ),
            ),
            if (_localBackupPath != null) ...[
              Padding(
                padding: const EdgeInsets.only(left: 28.0, top: 6.0),
                child: Text(
                  _localBackupPath!,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ],
            if (_isLocalBackupEnabled) ...[
              const Divider(color: Colors.white24),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scheduleLabel != null
                          ? 'Scheduled daily at $scheduleLabel'
                          : 'Runs once a day when app opens',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  TextButton(
                    onPressed: _showLocalBackupTimePicker,
                    child: Text(
                      scheduleLabel != null ? 'Change' : 'Set Time',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (scheduleLabel != null)
                    TextButton(
                      onPressed: _clearLocalBackupSchedule,
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ],
            if (_localBackupLastTime != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Last backup: ${DateFormat('MM/dd HH:mm').format(_localBackupLastTime!)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNasBackupCard() {
    if (_isLoadingSettings) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns, color: Colors.orange),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'NAS Backup',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _isAutoBackupEnabled,
                  onChanged: _toggleAutoBackup,
                  activeThumbColor: Colors.orange,
                ),
              ],
            ),

            if (!_isNasConfigured)
              Padding(
                padding: const EdgeInsets.only(left: 28.0, top: 8.0),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Configure NAS'),
                  onPressed: () async {
                    final result = await _showNasConfigDialog();
                    if (result == true) await _loadSettings();
                  },
                ),
              ),

            if (_isNasConfigured) ...[
              Padding(
                padding: const EdgeInsets.only(left: 28.0, top: 4.0),
                child: Text(
                  _nasDisplayAddress ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              if (_nasConnectionNote != null)
                Padding(
                  padding: const EdgeInsets.only(left: 28.0),
                  child: Text(
                    _nasConnectionNote!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 28.0, top: 8.0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        final result = await _showNasConfigDialog();
                        if (result == true) await _loadSettings();
                      },
                      child: const Text('Edit Settings'),
                    ),
                    OutlinedButton(
                      onPressed: _testConnection,
                      child: const Text('Test Connection'),
                    ),
                  ],
                ),
              ),
            ],

            if (_isAutoBackupEnabled) ...[
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              const Text(
                'Retention Policy',
                style: TextStyle(color: Colors.grey),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _retentionCount.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '$_retentionCount backups',
                      activeColor: Colors.orange,
                      onChanged: _updateRetention,
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '$_retentionCount',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const Text(
                'Backups exceeding this count will be deleted (oldest first).',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Backs up when app opens (at most once per day)',
                style: TextStyle(color: Colors.grey),
              ),
            ],

            if (_lastBackupTime != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Last successful backup: ${DateFormat('MM/dd HH:mm').format(_lastBackupTime!)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
