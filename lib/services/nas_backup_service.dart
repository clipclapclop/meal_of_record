import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:meal_of_record/services/backup_config_service.dart';
import 'package:xml/xml.dart';

/// A simple model representing a backup file on the NAS.
class NasBackupFile {
  final String name;
  final String href;
  final int? size;
  final DateTime? modified;

  NasBackupFile({
    required this.name,
    required this.href,
    this.size,
    this.modified,
  });
}

class NasBackupService {
  // Singleton pattern
  NasBackupService._();
  static final NasBackupService instance = NasBackupService._();

  final BackupConfigService _config = BackupConfigService.instance;

  /// Tests the connection to the configured NAS WebDAV server.
  /// Returns a message: null on success, or an error description.
  Future<String?> testConnection() async {
    try {
      final client = await _createHttpClient();
      final uri = await _buildUri('');

      final request = await client.openUrl('PROPFIND', uri);
      request.headers.set('Depth', '0');
      request.headers.contentType = ContentType('application', 'xml');
      request.write(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:">'
        '<d:prop><d:resourcetype/></d:prop>'
        '</d:propfind>',
      );

      final response = await request.close();
      client.close();

      if (response.statusCode == 207) {
        return null; // Success
      } else if (response.statusCode == 404) {
        return 'Folder not found (404). Please create the backup folder on your NAS first.';
      } else if (response.statusCode == 401) {
        return 'Authentication failed (401). Check your username and password.';
      } else {
        return 'Server responded with status ${response.statusCode}.';
      }
    } on SocketException catch (e) {
      return 'Could not connect: ${e.message}';
    } on HandshakeException catch (e) {
      return 'SSL/TLS error: ${e.message}. Try enabling "Allow self-signed certificate".';
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  /// Uploads a backup zip file to the NAS.
  /// Returns true on success.
  Future<bool> uploadBackup(File zipFile, {int retentionCount = 7}) async {
    try {
      final now = DateTime.now();
      final timestamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final fileName = 'meal_of_record_$timestamp.zip';
      debugPrint('NasBackupService: Uploading $fileName...');

      final client = await _createHttpClient();
      final uri = await _buildUri(fileName);

      final request = await client.openUrl('PUT', uri);
      request.headers.contentType = ContentType('application', 'zip');
      final bytes = await zipFile.readAsBytes();
      request.headers.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close();
      client.close();

      // 201 Created or 204 No Content are both success
      if (response.statusCode == 201 || response.statusCode == 204) {
        debugPrint('NasBackupService: Upload complete.');
        if (retentionCount > 0) {
          await _enforceRetentionPolicy(retentionCount);
        }
        return true;
      } else {
        debugPrint(
          'NasBackupService: Upload failed with status ${response.statusCode}.',
        );
        return false;
      }
    } catch (e) {
      debugPrint('NasBackupService: Upload error: $e');
      return false;
    }
  }

  /// Lists backup files on the NAS, sorted newest first.
  Future<List<NasBackupFile>> listBackups() async {
    try {
      final client = await _createHttpClient();
      final uri = await _buildUri('');

      final request = await client.openUrl('PROPFIND', uri);
      request.headers.set('Depth', '1');
      request.headers.contentType = ContentType('application', 'xml');
      request.write(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:">'
        '<d:prop>'
        '<d:getcontentlength/>'
        '<d:getlastmodified/>'
        '<d:displayname/>'
        '</d:prop>'
        '</d:propfind>',
      );

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 207) {
        debugPrint(
          'NasBackupService: PROPFIND failed with status ${response.statusCode}.',
        );
        return [];
      }

      return _parsePropfindResponse(body);
    } catch (e) {
      debugPrint('NasBackupService: Error listing backups: $e');
      return [];
    }
  }

  /// Downloads a backup file from the NAS by its href path.
  Future<File?> downloadBackup(String href) async {
    try {
      final client = await _createHttpClient();
      final uri = await _buildAbsoluteUri(href);

      final request = await client.openUrl('GET', uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        debugPrint(
          'NasBackupService: Download failed with status ${response.statusCode}.',
        );
        client.close();
        return null;
      }

      final tempDir = await Directory.systemTemp.createTemp();
      final file = File('${tempDir.path}/temp_restore.zip');

      final List<int> data = [];
      await for (final chunk in response) {
        data.addAll(chunk);
      }
      await file.writeAsBytes(data);
      client.close();

      return file;
    } catch (e) {
      debugPrint('NasBackupService: Download error: $e');
      return null;
    }
  }

  /// Parses a WebDAV PROPFIND XML response into a list of NasBackupFile.
  @visibleForTesting
  List<NasBackupFile> parsePropfindResponse(String xmlBody) {
    return _parsePropfindResponse(xmlBody);
  }

  List<NasBackupFile> _parsePropfindResponse(String xmlBody) {
    final document = XmlDocument.parse(xmlBody);
    final responses = document.findAllElements('response', namespace: 'DAV:');

    final backups = <NasBackupFile>[];
    final pattern = RegExp(r'meal_of_record_.*\.zip$');

    for (final resp in responses) {
      final hrefElement = resp.findAllElements('href', namespace: 'DAV:');
      if (hrefElement.isEmpty) continue;

      final href = hrefElement.first.innerText.trim();
      final name = Uri.decodeFull(
        href.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '',
      );

      if (!pattern.hasMatch(name)) continue;

      int? size;
      DateTime? modified;

      final sizeElements = resp.findAllElements(
        'getcontentlength',
        namespace: 'DAV:',
      );
      if (sizeElements.isNotEmpty) {
        size = int.tryParse(sizeElements.first.innerText.trim());
      }

      final modElements = resp.findAllElements(
        'getlastmodified',
        namespace: 'DAV:',
      );
      if (modElements.isNotEmpty) {
        modified = HttpDate.parse(modElements.first.innerText.trim());
      }

      backups.add(
        NasBackupFile(name: name, href: href, size: size, modified: modified),
      );
    }

    // Sort newest first
    backups.sort((a, b) {
      if (a.modified == null && b.modified == null) return 0;
      if (a.modified == null) return 1;
      if (b.modified == null) return -1;
      return b.modified!.compareTo(a.modified!);
    });

    return backups;
  }

  Future<void> _enforceRetentionPolicy(int maxBackups) async {
    try {
      final backups = await listBackups();
      if (backups.length <= maxBackups) return;

      final toDelete = backups.sublist(maxBackups);
      for (final backup in toDelete) {
        try {
          final client = await _createHttpClient();
          final uri = await _buildAbsoluteUri(backup.href);
          final request = await client.openUrl('DELETE', uri);
          final response = await request.close();
          client.close();

          if (response.statusCode == 204 || response.statusCode == 200) {
            debugPrint('NasBackupService: Deleted old backup: ${backup.name}');
          } else {
            debugPrint(
              'NasBackupService: Failed to delete ${backup.name}: ${response.statusCode}',
            );
          }
        } catch (e) {
          debugPrint('NasBackupService: Error deleting ${backup.name}: $e');
        }
      }
    } catch (e) {
      debugPrint('NasBackupService: Retention policy error: $e');
    }
  }

  Future<HttpClient> _createHttpClient() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    final allowSelfSigned = await _config.getNasAllowSelfSigned();
    if (allowSelfSigned) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    }

    final (username, password) = await _config.getNasCredentials();
    if (username != null && password != null) {
      client.addCredentials(
        await _buildUri(''),
        '',
        HttpClientBasicCredentials(username, password),
      );
    }

    return client;
  }

  /// Builds a URI for a file within the configured NAS backup path.
  Future<Uri> _buildUri(String fileName) async {
    final host = await _config.getNasHost() ?? '';
    final port = await _config.getNasPort();
    final basePath = await _config.getNasPath() ?? '/';
    final useHttps = await _config.getNasUseHttps();

    final scheme = useHttps ? 'https' : 'http';
    final effectivePort = port ?? (useHttps ? 443 : 80);

    // Ensure path ends with / before appending filename
    final normalizedPath = basePath.endsWith('/') ? basePath : '$basePath/';
    final fullPath = fileName.isEmpty
        ? normalizedPath
        : '$normalizedPath$fileName';

    return Uri(scheme: scheme, host: host, port: effectivePort, path: fullPath);
  }

  /// Builds a URI from an absolute href path (as returned by PROPFIND).
  Future<Uri> _buildAbsoluteUri(String href) async {
    final host = await _config.getNasHost() ?? '';
    final port = await _config.getNasPort();
    final useHttps = await _config.getNasUseHttps();

    final scheme = useHttps ? 'https' : 'http';
    final effectivePort = port ?? (useHttps ? 443 : 80);

    return Uri(scheme: scheme, host: host, port: effectivePort, path: href);
  }
}
