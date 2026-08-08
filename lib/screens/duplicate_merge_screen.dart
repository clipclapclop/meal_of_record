import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:meal_of_record/screens/duplicate_merge_manual_tab.dart';
import 'package:meal_of_record/screens/duplicate_merge_suggested_tab.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/screen_background.dart';

class DuplicateMergeScreen extends StatefulWidget {
  const DuplicateMergeScreen({super.key});

  @override
  State<DuplicateMergeScreen> createState() => _DuplicateMergeScreenState();
}

class _DuplicateMergeScreenState extends State<DuplicateMergeScreen> {
  String? _backupPath;
  DateTime? _backupTime;
  Object? _backupError;
  bool _backingUp = true;

  @override
  void initState() {
    super.initState();
    _createSessionBackup();
  }

  Future<void> _createSessionBackup() async {
    try {
      final zip = await DatabaseService.instance.exportBackupAsZip();
      try {
        final docs = await getApplicationDocumentsDirectory();
        final sessionsDir = Directory('${docs.path}/merge_sessions');
        if (!await sessionsDir.exists()) {
          await sessionsDir.create(recursive: true);
        }
        final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
        final dest = File('${sessionsDir.path}/merge_session_$stamp.zip');
        await zip.copy(dest.path);
        if (!mounted) return;
        setState(() {
          _backupPath = dest.path;
          _backupTime = DateTime.now();
          _backingUp = false;
        });
      } finally {
        try {
          await zip.parent.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backupError = e;
        _backingUp = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ScreenBackground(
        appBar: AppBar(
          title: const Text('Clean up duplicates'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Suggested'),
              Tab(text: 'Manual'),
            ],
          ),
        ),
        child: Column(
          children: [
            _buildBackupBanner(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupBanner() {
    if (_backingUp) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: Colors.amber.withValues(alpha: 0.15),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Creating session backup…')),
          ],
        ),
      );
    }
    if (_backupError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: Colors.red.withValues(alpha: 0.15),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Session backup failed: $_backupError. Merging is disabled.',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }
    final time = DateFormat('HH:mm:ss').format(_backupTime!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.green.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Session backup created at $time',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy backup path',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _backupPath!));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Backup path copied')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final canMerge = !_backingUp && _backupError == null;
    return TabBarView(
      children: [
        DuplicateMergeSuggestedTab(canMerge: canMerge),
        DuplicateMergeManualTab(canMerge: canMerge),
      ],
    );
  }
}
