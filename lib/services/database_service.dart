import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_serving.dart' as model_serving;
import 'package:meal_of_record/models/food_portion.dart' as model;
import 'package:meal_of_record/models/logged_portion.dart' as model;
import 'package:meal_of_record/models/recipe.dart' as model;
import 'package:meal_of_record/models/recipe_item.dart' as model;
import 'package:meal_of_record/services/backup_config_service.dart';
import 'package:meal_of_record/models/category.dart' as model;
import 'package:meal_of_record/models/weight.dart' as model;
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/models/daily_macro_stats.dart' as model_stats;
import 'package:meal_of_record/services/reference_database.dart'
    hide FoodPortion, FoodsCompanion, FoodPortionsCompanion;
import 'package:meal_of_record/models/food_usage_stats.dart';
import 'package:meal_of_record/models/food_container.dart';
import 'package:meal_of_record/models/merge_result.dart';
import 'package:meal_of_record/services/image_storage_service.dart';

/// Holds information about the last logged unit and quantity for a food.
class LastLoggedInfo {
  final String unit;
  final double quantity;
  final double grams;

  const LastLoggedInfo({
    required this.unit,
    required this.quantity,
    required this.grams,
  });
}

class BackupRestoreException implements Exception {
  final String message;
  final Object? cause;

  const BackupRestoreException(this.message, [this.cause]);

  @override
  String toString() => 'Backup restore failed: $message';
}

class _StagedBackup {
  final Directory directory;
  final File database;
  final Directory? images;
  final Map<String, Object?>? preferences;
  final bool replacesImages;
  final bool replacesPreferences;

  const _StagedBackup({
    required this.directory,
    required this.database,
    required this.images,
    required this.preferences,
    required this.replacesImages,
    required this.replacesPreferences,
  });
}

class DatabaseService {
  static const int backupFormatVersion = 2;
  static const int _maxBackupFiles = 10000;
  static const int _maxExpandedBackupBytes = 512 * 1024 * 1024;
  static const Set<String> _backupPreferenceKeys = {
    'goal_settings',
    'macro_targets',
    'target_snapshots',
    'has_seen_welcome',
    'share_include_images',
  };
  static const Set<String> _requiredLiveTables = {
    'foods',
    'food_portions',
    'recipes',
    'recipe_items',
    'categories',
    'recipe_category_links',
    'logged_portions',
    'weights',
    'containers',
    'food_barcodes',
  };

  late LiveDatabase _liveDb;
  late ReferenceDatabase _referenceDb;
  File? _liveDbFileOverride;
  Directory? _imagesDirectoryOverride;

  static final DatabaseService instance = DatabaseService._internal();

  DatabaseService._internal();

  factory DatabaseService.forTesting(
    LiveDatabase liveDb,
    ReferenceDatabase referenceDb, {
    File? liveDbFile,
    Directory? imagesDirectory,
  }) {
    return DatabaseService._internal()
      .._liveDb = liveDb
      .._referenceDb = referenceDb
      .._liveDbFileOverride = liveDbFile
      .._imagesDirectoryOverride = imagesDirectory;
  }

  static void initSingletonForTesting(
    LiveDatabase liveDb,
    ReferenceDatabase referenceDb,
  ) {
    instance._liveDb = liveDb;
    instance._referenceDb = referenceDb;
  }

  Future<void> init() async {
    _liveDb = LiveDatabase(connection: openLiveConnection());
    _referenceDb = ReferenceDatabase(connection: openReferenceConnection());
    await _ensureSystemQuickAddFood();
  }

  Future<void> close() async {
    await _liveDb.close();
    await _referenceDb.close();
  }

  Future<File> _liveDbFile() async {
    return _liveDbFileOverride ?? await getLiveDbFile();
  }

  Future<Directory> _imagesDirectory() async {
    return _imagesDirectoryOverride ??
        await ImageStorageService.instance.getImagesDirectory();
  }

  Future<void> restoreDatabase(File backupFile) async {
    final liveFile = await _liveDbFile();
    final imagesDirectory = await _imagesDirectory();
    await liveFile.parent.create(recursive: true);

    final staged = await _stageBackup(backupFile, liveFile.parent);
    try {
      await _installStagedBackup(staged, liveFile, imagesDirectory);
      await BackupConfigService.instance.markDirty();
    } finally {
      if (await staged.directory.exists()) {
        await staged.directory.delete(recursive: true);
      }
    }
  }

  /// Exports a point-in-time SQLite snapshot, app-owned images, and important
  /// preferences as a versioned zip archive.
  Future<File> exportBackupAsZip() async {
    final imagesDirectory = await _imagesDirectory();
    final tempDirectory = await Directory.systemTemp.createTemp(
      'meal_of_record_backup_',
    );
    final snapshotFile = File('${tempDirectory.path}/meal_of_record.db');

    try {
      // VACUUM INTO uses SQLite's snapshot semantics and includes committed WAL
      // data without requiring the live connection to be closed.
      await _liveDb.customStatement('VACUUM INTO ?', [snapshotFile.path]);
      final databaseBytes = await snapshotFile.readAsBytes();
      final archive = Archive()
        ..addFile(
          ArchiveFile('meal_of_record.db', databaseBytes.length, databaseBytes),
        );

      if (await imagesDirectory.exists()) {
        await for (final entity in imagesDirectory.list(recursive: true)) {
          if (entity is! File) continue;
          final relativePath = p.relative(
            entity.path,
            from: imagesDirectory.path,
          );
          final archivePath = p.posix.join(
            'app_images',
            p.posix.joinAll(p.split(relativePath)),
          );
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
        }
      }

      final preferences = await _capturePreferences();
      final settingsBytes = utf8.encode(
        jsonEncode({
          'version': backupFormatVersion,
          'preferences': preferences,
        }),
      );
      archive.addFile(
        ArchiveFile('settings.json', settingsBytes.length, settingsBytes),
      );

      final manifestBytes = utf8.encode(
        jsonEncode({
          'formatVersion': backupFormatVersion,
          'databaseSchemaVersion': LiveDatabase.currentSchemaVersion,
          'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        throw const BackupRestoreException('the archive could not be encoded');
      }

      final now = DateTime.now();
      final timestamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final zipFile = File(
        '${tempDirectory.path}/meal_of_record_$timestamp.zip',
      );
      await zipFile.writeAsBytes(zipBytes, flush: true);
      await snapshotFile.delete();
      return zipFile;
    } catch (error) {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
      if (error is BackupRestoreException) rethrow;
      throw BackupRestoreException('the backup could not be created', error);
    }
  }

  Future<_StagedBackup> _stageBackup(
    File backupFile,
    Directory applicationDirectory,
  ) async {
    final stageDirectory = await applicationDirectory.createTemp(
      '.meal_of_record_restore_',
    );
    try {
      final staged = backupFile.path.toLowerCase().endsWith('.zip')
          ? await _stageZipBackup(backupFile, stageDirectory)
          : await _stageLegacyDatabase(backupFile, stageDirectory);
      return staged;
    } catch (error) {
      if (await stageDirectory.exists()) {
        await stageDirectory.delete(recursive: true);
      }
      if (error is BackupRestoreException) rethrow;
      throw BackupRestoreException(
        'the selected file is not a valid backup',
        error,
      );
    }
  }

  Future<_StagedBackup> _stageLegacyDatabase(
    File backupFile,
    Directory stageDirectory,
  ) async {
    final database = await backupFile.copy(
      '${stageDirectory.path}/meal_of_record.db',
    );
    await _validateDatabase(database);
    return _StagedBackup(
      directory: stageDirectory,
      database: database,
      images: null,
      preferences: null,
      replacesImages: false,
      replacesPreferences: false,
    );
  }

  Future<_StagedBackup> _stageZipBackup(
    File backupFile,
    Directory stageDirectory,
  ) async {
    final List<int> bytes;
    final Archive archive;
    try {
      if (await backupFile.length() > _maxExpandedBackupBytes) {
        throw const BackupRestoreException('the archive is too large');
      }
      bytes = await backupFile.readAsBytes();
      // Entry data stays compressed until after the declared expanded sizes
      // have passed the bounds below.
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      if (error is BackupRestoreException) rethrow;
      throw BackupRestoreException(
        'the zip archive is malformed or interrupted',
        error,
      );
    }

    if (archive.files.length > _maxBackupFiles) {
      throw const BackupRestoreException('the archive contains too many files');
    }

    final filesByName = <String, ArchiveFile>{};
    var expandedBytes = 0;
    for (final entry in archive.files) {
      _validateArchivePath(entry.name);
      if (entry.isSymbolicLink) {
        throw const BackupRestoreException(
          'the archive contains a symbolic link',
        );
      }
      if (!entry.isFile) continue;
      if (filesByName.containsKey(entry.name)) {
        throw BackupRestoreException(
          'the archive contains duplicate ${entry.name} entries',
        );
      }
      filesByName[entry.name] = entry;
      expandedBytes += entry.size;
      if (expandedBytes > _maxExpandedBackupBytes) {
        throw const BackupRestoreException('the expanded archive is too large');
      }
    }

    for (final entry in filesByName.values) {
      final content = entry.content as List<int>;
      if (content.length != entry.size ||
          (entry.crc32 != null && getCrc32(content) != entry.crc32)) {
        throw BackupRestoreException(
          'the archive entry ${entry.name} is corrupt',
        );
      }
    }

    final manifestEntry = filesByName['manifest.json'];
    Map<String, dynamic>? manifest;
    if (manifestEntry != null) {
      manifest = _decodeJsonObject(manifestEntry, 'manifest.json');
      final formatVersion = manifest['formatVersion'];
      if (formatVersion is! int || formatVersion != backupFormatVersion) {
        throw BackupRestoreException(
          'backup format $formatVersion is not supported by this app version',
        );
      }
    }

    final databaseEntry = filesByName['meal_of_record.db'];
    if (databaseEntry == null || databaseEntry.size == 0) {
      throw const BackupRestoreException(
        'the archive is incomplete: meal_of_record.db is missing',
      );
    }
    if (manifest != null && filesByName['settings.json'] == null) {
      throw const BackupRestoreException(
        'the archive is incomplete: settings.json is missing',
      );
    }

    if (manifest != null) {
      for (final name in filesByName.keys) {
        if (name != 'manifest.json' &&
            name != 'settings.json' &&
            name != 'meal_of_record.db' &&
            !name.startsWith('app_images/')) {
          throw BackupRestoreException(
            'the archive contains unknown file $name',
          );
        }
      }
    }

    final database = File('${stageDirectory.path}/meal_of_record.db');
    await database.writeAsBytes(
      databaseEntry.content as List<int>,
      flush: true,
    );

    final sourceSchemaVersion = await _validateDatabase(database);
    if (manifest != null) {
      final declaredSchemaVersion = manifest['databaseSchemaVersion'];
      if (declaredSchemaVersion is! int ||
          declaredSchemaVersion != sourceSchemaVersion) {
        throw const BackupRestoreException(
          'the manifest does not match the database schema',
        );
      }
    }

    final images = Directory('${stageDirectory.path}/app_images');
    await images.create();
    for (final entry in filesByName.entries) {
      if (!entry.key.startsWith('app_images/')) continue;
      final relativePath = entry.key.substring('app_images/'.length);
      if (relativePath.isEmpty) continue;
      final target = File(
        p.joinAll([images.path, ...p.posix.split(relativePath)]),
      );
      await target.parent.create(recursive: true);
      await target.writeAsBytes(entry.value.content as List<int>, flush: true);
    }

    final settingsEntry = filesByName['settings.json'];
    final preferences = settingsEntry == null
        ? null
        : _decodeBackupPreferences(settingsEntry);

    return _StagedBackup(
      directory: stageDirectory,
      database: database,
      images: images,
      preferences: preferences,
      replacesImages: true,
      replacesPreferences: settingsEntry != null,
    );
  }

  void _validateArchivePath(String name) {
    final segments = p.posix.split(name);
    if (name.isEmpty ||
        name.contains('\\') ||
        p.posix.isAbsolute(name) ||
        segments.contains('..') ||
        segments.contains('.') ||
        name.startsWith('/')) {
      throw BackupRestoreException('the archive contains unsafe path $name');
    }
  }

  Map<String, dynamic> _decodeJsonObject(ArchiveFile entry, String name) {
    try {
      final decoded = jsonDecode(utf8.decode(entry.content as List<int>));
      if (decoded is! Map) {
        throw const FormatException('expected a JSON object');
      }
      return Map<String, dynamic>.from(decoded);
    } catch (error) {
      throw BackupRestoreException('$name is malformed', error);
    }
  }

  Map<String, Object?> _decodeBackupPreferences(ArchiveFile settingsEntry) {
    final settings = _decodeJsonObject(settingsEntry, 'settings.json');
    final version = settings['version'];
    if (version is! int || version < 1 || version > backupFormatVersion) {
      throw BackupRestoreException(
        'settings version $version is not supported',
      );
    }

    final preferences = <String, Object?>{};
    if (version == 1) {
      for (final key in const [
        'goal_settings',
        'macro_targets',
        'target_snapshots',
      ]) {
        if (settings.containsKey(key)) {
          final value = settings[key];
          if (value is! Map && value is! List) {
            throw BackupRestoreException('settings value $key is malformed');
          }
          preferences[key] = jsonEncode(value);
        }
      }
      for (final key in const ['has_seen_welcome', 'share_include_images']) {
        if (settings.containsKey(key)) preferences[key] = settings[key];
      }
    } else {
      final rawPreferences = settings['preferences'];
      if (rawPreferences is! Map) {
        throw const BackupRestoreException(
          'settings.json does not contain preferences',
        );
      }
      for (final entry in rawPreferences.entries) {
        final key = entry.key;
        if (key is String && _backupPreferenceKeys.contains(key)) {
          preferences[key] = entry.value;
        }
      }
    }

    for (final entry in preferences.entries) {
      final expectsString =
          entry.key == 'goal_settings' ||
          entry.key == 'macro_targets' ||
          entry.key == 'target_snapshots';
      if ((expectsString && entry.value is! String) ||
          (!expectsString && entry.value is! bool)) {
        throw BackupRestoreException(
          'settings value ${entry.key} has the wrong type',
        );
      }
      if (expectsString) {
        try {
          jsonDecode(entry.value! as String);
        } catch (error) {
          throw BackupRestoreException(
            'settings value ${entry.key} is malformed',
            error,
          );
        }
      }
    }
    return preferences;
  }

  Future<int> _validateDatabase(File databaseFile) async {
    sqlite.Database? rawDatabase;
    late int sourceSchemaVersion;
    try {
      rawDatabase = sqlite.sqlite3.open(databaseFile.path);
      final versionRows = rawDatabase.select('PRAGMA user_version');
      sourceSchemaVersion = versionRows.single['user_version']! as int;
      if (sourceSchemaVersion < LiveDatabase.minimumSupportedSchemaVersion) {
        throw BackupRestoreException(
          'database schema $sourceSchemaVersion is older than the oldest supported schema '
          '${LiveDatabase.minimumSupportedSchemaVersion}',
        );
      }
      if (sourceSchemaVersion > LiveDatabase.currentSchemaVersion) {
        throw BackupRestoreException(
          'database schema $sourceSchemaVersion is newer than this app supports',
        );
      }
      final quickCheck = rawDatabase.select('PRAGMA quick_check');
      if (quickCheck.length != 1 || quickCheck.single.values.single != 'ok') {
        throw const BackupRestoreException(
          'the database failed its integrity check',
        );
      }
    } catch (error) {
      if (error is BackupRestoreException) rethrow;
      throw BackupRestoreException('meal_of_record.db is malformed', error);
    } finally {
      rawDatabase?.dispose();
    }

    final candidate = LiveDatabase(connection: NativeDatabase(databaseFile));
    try {
      await candidate.customSelect('SELECT 1').getSingle();
      final tables = await candidate
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames = tables.map((row) => row.data['name']).toSet();
      final missingTables = _requiredLiveTables.difference(tableNames);
      if (missingTables.isNotEmpty) {
        throw BackupRestoreException(
          'the database is incomplete; missing ${missingTables.join(', ')}',
        );
      }
      final quickCheck = await candidate
          .customSelect('PRAGMA quick_check')
          .get();
      if (quickCheck.length != 1 ||
          quickCheck.single.data.values.single != 'ok') {
        throw const BackupRestoreException(
          'the database failed its integrity check',
        );
      }
      final foreignKeyErrors = await candidate
          .customSelect('PRAGMA foreign_key_check')
          .get();
      if (foreignKeyErrors.isNotEmpty) {
        throw const BackupRestoreException(
          'the database contains broken relationships',
        );
      }
    } catch (error) {
      if (error is BackupRestoreException) rethrow;
      throw BackupRestoreException('the database could not be migrated', error);
    } finally {
      await candidate.close();
    }
    return sourceSchemaVersion;
  }

  Future<Map<String, Object?>> _capturePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return <String, Object?>{
      for (final key in _backupPreferenceKeys)
        if (prefs.containsKey(key)) key: prefs.get(key),
    };
  }

  Future<void> _replacePreferences(Map<String, Object?> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _backupPreferenceKeys) {
      await prefs.remove(key);
    }
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else {
        throw BackupRestoreException(
          'preference ${entry.key} has an unsupported type',
        );
      }
    }
  }

  Future<void> _installStagedBackup(
    _StagedBackup staged,
    File liveFile,
    Directory imagesDirectory,
  ) async {
    if (!await liveFile.exists()) {
      throw const BackupRestoreException(
        'the current live database is missing',
      );
    }

    final rollbackDatabase = File('${staged.directory.path}/previous.db');
    final rollbackImages = Directory(
      '${staged.directory.path}/previous_images',
    );
    final oldPreferences = staged.replacesPreferences
        ? await _capturePreferences()
        : null;
    final hadImages = await imagesDirectory.exists();
    var databaseMoved = false;
    var imagesMoved = false;
    var replacementDatabaseInstalled = false;
    var replacementImagesInstalled = false;
    var preferencesChanged = false;
    var replacementOpened = false;

    await _liveDb.close();
    try {
      await _deleteSqliteSidecars(liveFile);
      await liveFile.rename(rollbackDatabase.path);
      databaseMoved = true;

      if (staged.replacesImages && hadImages) {
        await imagesDirectory.rename(rollbackImages.path);
        imagesMoved = true;
      }

      await staged.database.rename(liveFile.path);
      replacementDatabaseInstalled = true;

      if (staged.replacesImages) {
        await staged.images!.rename(imagesDirectory.path);
        replacementImagesInstalled = true;
      }

      if (staged.replacesPreferences) {
        preferencesChanged = true;
        await _replacePreferences(staged.preferences!);
      }

      _liveDb = LiveDatabase(connection: NativeDatabase(liveFile));
      replacementOpened = true;
      await _liveDb.customSelect('SELECT 1').getSingle();
      await _ensureSystemQuickAddFood();
    } catch (error) {
      if (replacementOpened) {
        await _liveDb.close();
      }
      if (replacementDatabaseInstalled && await liveFile.exists()) {
        await liveFile.delete();
      }
      await _deleteSqliteSidecars(liveFile);
      if (databaseMoved && await rollbackDatabase.exists()) {
        await rollbackDatabase.rename(liveFile.path);
      }

      if (replacementImagesInstalled && await imagesDirectory.exists()) {
        await imagesDirectory.delete(recursive: true);
      }
      if (imagesMoved && await rollbackImages.exists()) {
        await rollbackImages.rename(imagesDirectory.path);
      }
      if (preferencesChanged && oldPreferences != null) {
        await _replacePreferences(oldPreferences);
      }

      _liveDb = LiveDatabase(connection: NativeDatabase(liveFile));
      await _liveDb.customSelect('SELECT 1').getSingle();
      throw BackupRestoreException(
        'the restore could not be applied; the original data was put back',
        error,
      );
    }
  }

  Future<void> _deleteSqliteSidecars(File database) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('${database.path}$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  model.Weight _mapWeightData(dynamic weightData) {
    return model.Weight(
      id: weightData.id,
      weight: weightData.weight,
      date: DateTime.fromMillisecondsSinceEpoch(weightData.date),
    );
  }

  model.Food _mapFoodData(
    dynamic foodData,
    List<model_serving.FoodServing> servings,
    model.FoodDatabase database,
  ) {
    return model.Food(
      id: foodData.id,
      source: foodData.source,
      name: foodData.name,
      emoji: foodData.emoji,
      thumbnail: foodData.thumbnail,
      calories: foodData.caloriesPerGram,
      protein: foodData.proteinPerGram,
      fat: foodData.fatPerGram,
      carbs: foodData.carbsPerGram,
      fiber: foodData.fiberPerGram,
      servings: servings,
      parentId: foodData.parentId,
      sourceFdcId: foodData.sourceFdcId,
      sourceBarcode: foodData.sourceBarcode,
      usageNote: foodData.usageNote,
      hidden: foodData.hidden ?? false,
      database: database,
    );
  }

  Future<List<model.Food>> searchFoodsByName(String query) async {
    if (query.isEmpty) return [];
    final lowerCaseQuery = '%${query.toLowerCase()}%';

    // 1. Search Live DB
    final liveFoodsData =
        await (_liveDb.select(_liveDb.foods)
              ..where((f) => f.name.lower().like(lowerCaseQuery))
              ..where((f) => f.hidden.equals(false)))
            .get();

    // 2. Search Reference DB
    final refFoodsData = await (_referenceDb.select(
      _referenceDb.foods,
    )..where((f) => f.name.lower().like(lowerCaseQuery))).get();

    // 3. Filter Logic
    // Collect all sourceFdcIds from Live results to filter out References
    final liveSourceIds = liveFoodsData
        .map((f) => f.sourceFdcId)
        .whereType<int>()
        .toSet();

    // Collect all parentIds to filter out superseded versions
    // Only consider non-hidden children to avoid hiding parents when the child is hidden
    final parentIdRows =
        await (_liveDb.selectOnly(_liveDb.foods)
              ..addColumns([_liveDb.foods.parentId])
              ..where(_liveDb.foods.parentId.isNotNull())
              ..where(_liveDb.foods.hidden.equals(false)))
            .get();
    final parentIds = parentIdRows
        .map((r) => r.read(_liveDb.foods.parentId))
        .whereType<int>()
        .toSet();

    final List<model.Food> results = [];

    // Collect IDs for batch fetching
    final liveIdsToFetch = liveFoodsData
        .where((f) => !parentIds.contains(f.id))
        .map((f) => f.id)
        .toList();

    final refIdsToFetch = refFoodsData
        .where((f) => !liveSourceIds.contains(f.id))
        .map((f) => f.id)
        .toList();

    // Batch fetch servings
    final liveServingsMap = await getServingsForFoods(liveIdsToFetch, 'live');
    final refServingsMap = await getServingsForFoods(
      refIdsToFetch,
      'reference',
    );

    // Add Live Foods
    for (final foodData in liveFoodsData) {
      if (!parentIds.contains(foodData.id)) {
        final servings = liveServingsMap[foodData.id] ?? [];
        results.add(_mapFoodData(foodData, servings, model.FoodDatabase.live));
      }
    }

    // Add Reference Foods
    for (final foodData in refFoodsData) {
      if (!liveSourceIds.contains(foodData.id)) {
        final servings = refServingsMap[foodData.id] ?? [];
        results.add(_mapFoodData(foodData, servings, model.FoodDatabase.reference));
      }
    }

    return results;
  }

  Future<List<model_serving.FoodServing>> getServingsForFood(
    int foodId,
    String foodSource,
  ) async {
    final servingsMap = await getServingsForFoods([foodId], foodSource);
    return servingsMap[foodId] ?? [];
  }

  Future<Map<int, List<model_serving.FoodServing>>> getServingsForFoods(
    List<int> foodIds,
    String foodSource,
  ) async {
    if (foodIds.isEmpty) return {};

    List<dynamic> driftServings;
    if (foodSource == 'live') {
      driftServings = await (_liveDb.select(
        _liveDb.foodPortions,
      )..where((s) => s.foodId.isIn(foodIds))).get();
    } else {
      driftServings = await (_referenceDb.select(
        _referenceDb.foodPortions,
      )..where((s) => s.foodId.isIn(foodIds))).get();
    }

    final Map<int, List<model_serving.FoodServing>> results = {};
    for (final s in driftServings) {
      final serving = model_serving.FoodServing(
        id: s.id as int,
        foodId: s.foodId as int,
        unit: s.unit as String,
        grams: s.grams as double,
        quantity: s.quantity as double,
      );
      results.putIfAbsent(s.foodId as int, () => []).add(serving);
    }

    // Ensure 'g' is always an option for each requested food
    for (final foodId in foodIds) {
      final servings = results.putIfAbsent(foodId, () => []);
      if (!servings.any((s) => s.unit == 'g')) {
        servings.add(
          model_serving.FoodServing(
            foodId: foodId,
            unit: 'g',
            grams: 1.0,
            quantity: 1.0,
          ),
        );
      }
    }

    return results;
  }

  Future<String?> getLastLoggedUnit(int originalFoodId) async {
    // Find the last log for this food OR its reference parent
    // Logic: Look for logs with foodId == originalFoodId OR (food.sourceFdcId == originalFoodId)

    // Since simpler queries with OR across joins can be tricky in Drift without custom expressions,
    // we can do two queries or one complex join.
    // Let's do a join on Foods.

    final query =
        _liveDb.select(_liveDb.loggedPortions).join([
            innerJoin(
              _liveDb.foods,
              _liveDb.foods.id.equalsExp(_liveDb.loggedPortions.foodId),
            ),
          ])
          ..where(
            _liveDb.loggedPortions.foodId.equals(originalFoodId) |
                _liveDb.foods.sourceFdcId.equals(originalFoodId),
          )
          ..orderBy([
            OrderingTerm(
              expression: _liveDb.loggedPortions.logTimestamp,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1);

    final row = await query.getSingleOrNull();
    if (row != null) {
      return row.readTable(_liveDb.loggedPortions).unit;
    }
    return null;
  }

  /// Returns the last logged unit, quantity, and grams for a food.
  /// Matches by foodId directly or via sourceFdcId for reference foods.
  Future<LastLoggedInfo?> getLastLoggedInfo(int originalFoodId) async {
    final query =
        _liveDb.select(_liveDb.loggedPortions).join([
            innerJoin(
              _liveDb.foods,
              _liveDb.foods.id.equalsExp(_liveDb.loggedPortions.foodId),
            ),
          ])
          ..where(
            _liveDb.loggedPortions.foodId.equals(originalFoodId) |
                _liveDb.foods.sourceFdcId.equals(originalFoodId),
          )
          ..orderBy([
            OrderingTerm(
              expression: _liveDb.loggedPortions.logTimestamp,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1);

    final row = await query.getSingleOrNull();
    if (row != null) {
      final loggedPortion = row.readTable(_liveDb.loggedPortions);
      return LastLoggedInfo(
        unit: loggedPortion.unit,
        quantity: loggedPortion.quantity,
        grams: loggedPortion.grams,
      );
    }
    return null;
  }

  /// Returns the last logged unit, quantity, and grams for a recipe.
  /// Returns null for dump-only recipes (isTemplate = true).
  Future<LastLoggedInfo?> getLastLoggedInfoForRecipe(int recipeId) async {
    final query =
        _liveDb.select(_liveDb.loggedPortions).join([
            innerJoin(
              _liveDb.recipes,
              _liveDb.recipes.id.equalsExp(_liveDb.loggedPortions.recipeId),
            ),
          ])
          ..where(
            _liveDb.loggedPortions.recipeId.equals(recipeId) &
                _liveDb.recipes.isTemplate.equals(false),
          )
          ..orderBy([
            OrderingTerm(
              expression: _liveDb.loggedPortions.logTimestamp,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1);

    final row = await query.getSingleOrNull();
    if (row != null) {
      final loggedPortion = row.readTable(_liveDb.loggedPortions);
      return LastLoggedInfo(
        unit: loggedPortion.unit,
        quantity: loggedPortion.quantity,
        grams: loggedPortion.grams,
      );
    }
    return null;
  }

  Future<model.Food?> getFoodByBarcode(String barcode) async {
    final food = await (_liveDb.select(
      _liveDb.foods,
    )..where((f) => f.sourceBarcode.equals(barcode))).getSingleOrNull();
    return food == null ? null : _mapFoodData(food, [], model.FoodDatabase.live);
  }

  // ========== BARCODE OPERATIONS (NEW TABLE) ==========

  /// Get all barcodes associated with a food
  Future<List<String>> getBarcodesByFoodId(int foodId) async {
    final rows = await (_liveDb.select(_liveDb.foodBarcodes)
          ..where((b) => b.foodId.equals(foodId)))
        .get();
    return rows.map((r) => r.barcode).toList();
  }

  /// Add a barcode to a food. Returns false if already exists on this food.
  Future<bool> addBarcodeToFood(int foodId, String barcode) async {
    // Check if barcode already exists on this food
    final existing = await (_liveDb.select(_liveDb.foodBarcodes)
          ..where((b) => b.foodId.equals(foodId) & b.barcode.equals(barcode)))
        .getSingleOrNull();

    if (existing != null) {
      return false; // Already exists on this food
    }

    await _liveDb.into(_liveDb.foodBarcodes).insert(
          FoodBarcodesCompanion.insert(
            foodId: foodId,
            barcode: barcode,
          ),
        );
    BackupConfigService.instance.markDirty();
    return true;
  }

  /// Remove a barcode from a food
  Future<void> removeBarcodeFromFood(int foodId, String barcode) async {
    await (_liveDb.delete(_liveDb.foodBarcodes)
          ..where((b) => b.foodId.equals(foodId) & b.barcode.equals(barcode)))
        .go();
    BackupConfigService.instance.markDirty();
  }

  /// Get all foods that have a specific barcode (searches new table)
  Future<List<model.Food>> getFoodsByBarcode(String barcode) async {
    final barcodeRows = await (_liveDb.select(_liveDb.foodBarcodes)
          ..where((b) => b.barcode.equals(barcode)))
        .get();

    if (barcodeRows.isEmpty) {
      return [];
    }

    final foodIds = barcodeRows.map((r) => r.foodId).toList().cast<int>();
    final foodsMap = await getFoodsByIds(foodIds, 'live');

    // Filter out hidden foods
    return foodsMap.values.where((f) => !f.hidden).toList();
  }

  /// Check if a barcode is assigned to another food (not the excluded one)
  /// Returns the other food if found, null otherwise
  Future<model.Food?> isBarcodeOnOtherFood(
      String barcode, int excludeFoodId) async {
    final barcodeRow = await (_liveDb.select(_liveDb.foodBarcodes)
          ..where(
              (b) => b.barcode.equals(barcode) & b.foodId.isNotValue(excludeFoodId)))
        .getSingleOrNull();

    if (barcodeRow == null) {
      return null;
    }

    return await getFoodById(barcodeRow.foodId, 'live');
  }

  Future<model.Food?> getFoodBySourceFdcId(int fdcId) async {
    final food = await (_liveDb.select(
      _liveDb.foods,
    )..where((f) => f.sourceFdcId.equals(fdcId))).getSingleOrNull();
    return food == null ? null : _mapFoodData(food, [], model.FoodDatabase.live);
  }

  Future<void> logPortions(
    List<model.FoodPortion> portions,
    DateTime logTimestamp,
  ) async {
    final timestamp = logTimestamp.millisecondsSinceEpoch;

    // First, ensure all foods are in the live database (copy if needed)
    // This must be done outside the transaction to avoid nested transaction issues
    for (final portion in portions) {
      final food = portion.food;

      if (food.database != model.FoodDatabase.live) {
        // Reference, OFF, or Foundation - check if we already have a live copy
        // For OFF items, check by barcode
        var existing;

        if (food.source == 'off') {
          if (food.sourceBarcode != null) {
            existing =
                await (_liveDb.select(_liveDb.foods)..where(
                      (f) => f.sourceBarcode.equals(food.sourceBarcode!),
                    ))
                    .getSingleOrNull();
          }
        } else {
          // Standard reference/foundation match by FDC ID
          existing = await (_liveDb.select(
            _liveDb.foods,
          )..where((f) => f.sourceFdcId.equals(food.id))).getSingleOrNull();
        }

        if (existing == null) {
          // Copy to live
          await copyFoodToLiveDb(food, isCopy: false);
        }
      }
    }

    // Now perform the actual logging within a transaction
    await _liveDb.transaction(() async {
      for (final portion in portions) {
        final food = portion.food;
        int? foodId;
        int? recipeId;
        // Calculate quantity if needed, currently placeholder to grams as per spec

        // Find the serving definition to calculate quantity
        if (portion.unit != 'g') {
          // We might need to find the serving.
          // For now, let's assume portion.grams is correct total weight.
          // If unit is 'slice', and 1 slice is 30g, and we have 60g, quantity is 2.
          // Converting back might be inexact without serving info.
          // User's previous code just put portion.grams into quantity?
          // Line 283: quantity: portion.grams, // Placeholder
          // So I will stick to that behavior for now or try to improve?
          // The comment said "// Placeholder".
          // I'll keep it as placeholder to be safe.
        }

        if (food.source == 'recipe') {
          recipeId = food.id;
        } else if (food.database == model.FoodDatabase.live) {
          foodId = food.id;
        } else if (food.source == 'off') {
          // OFF Item: Look up by barcode
          final existing =
              await (_liveDb.select(_liveDb.foods)
                    ..where((f) => f.sourceBarcode.equals(food.sourceBarcode!)))
                  .getSingleOrNull();

          if (existing != null) {
            foodId = existing.id;
          } else {
            // Should have been created in the loop above, but safe fallback
            final newFood = await copyFoodToLiveDb(food, isCopy: false);
            foodId = newFood.id;
          }
        } else {
          // Reference or Foundation
          // Food should already be copied, so just find the live copy
          final existing = await (_liveDb.select(
            _liveDb.foods,
          )..where((f) => f.sourceFdcId.equals(food.id))).getSingleOrNull();

          foodId = existing!.id;
        }

        // Create the log entry
        await _liveDb
            .into(_liveDb.loggedPortions)
            .insert(
              LoggedPortionsCompanion.insert(
                foodId: Value(foodId),
                recipeId: Value(recipeId),
                logTimestamp: timestamp,
                grams: portion.grams,
                unit: portion.unit,
                quantity: portion.quantity,
              ),
            );
      }

      BackupConfigService.instance.markDirty();
    });
  }

  Future<bool> isRecipeLogged(int recipeId) async {
    final rows = await (_liveDb.select(
      _liveDb.loggedPortions,
    )..where((t) => t.recipeId.equals(recipeId))).get();
    return rows.isNotEmpty;
  }

  Future<bool> isRecipeUsedAsIngredient(int recipeId) async {
    final rows = await (_liveDb.select(
      _liveDb.recipeItems,
    )..where((t) => t.ingredientRecipeId.equals(recipeId))).get();
    return rows.isNotEmpty;
  }

  Future<void> hideRecipe(int id) async {
    await (_liveDb.update(_liveDb.recipes)..where((t) => t.id.equals(id)))
        .write(const RecipesCompanion(hidden: Value(true)));
  }

  Future<List<model.LoggedPortion>> getLoggedPortionsForDate(
    DateTime date,
  ) async {
    final startOfDay = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    final endOfDay = DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;

    final query = _liveDb.select(_liveDb.loggedPortions)
      ..where((p) => p.logTimestamp.isBetweenValues(startOfDay, endOfDay));

    final loggedRows = await query.get();

    // Batch fetch unique foods and recipes to avoid N+1 queries
    final foodIds = loggedRows
        .map((r) => r.foodId)
        .whereType<int>()
        .toSet()
        .toList();
    final recipeIds = loggedRows
        .map((r) => r.recipeId)
        .whereType<int>()
        .toSet()
        .toList();

    final foodsMap = await getFoodsByIds(foodIds, 'live');
    final recipesMap = await getRecipesByIds(recipeIds);

    final results = <model.LoggedPortion>[];

    for (final row in loggedRows) {
      model.FoodPortion? portion;

      if (row.foodId != null) {
        final food = foodsMap[row.foodId!];
        if (food != null) {
          portion = model.FoodPortion(
            food: food,
            grams: row.grams,
            unit: row.unit,
          );
        }
      } else if (row.recipeId != null) {
        final recipe = recipesMap[row.recipeId!];
        if (recipe != null) {
          portion = model.FoodPortion(
            food: recipe.toFood(),
            grams: row.grams,
            unit: row.unit,
          );
        }
      }

      if (portion != null) {
        results.add(
          model.LoggedPortion(
            id: row.id,
            portion: portion,
            timestamp: DateTime.fromMillisecondsSinceEpoch(row.logTimestamp),
          ),
        );
      }
    }
    return await _resolveLoggedPortionRecipes(results);
  }

  Future<int> saveFood(model.Food food) async {
    // Check if food is used (logged or in recipe)
    bool isUsed = false;
    model.Food? existingLiveFood;

    if (food.id > 0 && food.database == model.FoodDatabase.live) {
      existingLiveFood = await getFoodById(food.id, 'live');
      if (existingLiveFood != null) {
        isUsed = await isFoodReferenced(food.id);
      }
    }

    if (isUsed && existingLiveFood != null) {
      // SMART VERSIONING: Only version if nutrition changed
      bool nutritionChanged = !_isFoodNutritionallyEquivalent(
        existingLiveFood,
        food,
      );

      if (nutritionChanged) {
        return await _liveDb.transaction(() async {
          // 1. Insert new food pointing to old one as parent
          final newFoodId = await _liveDb
              .into(_liveDb.foods)
              .insert(
                FoodsCompanion.insert(
                  name: food.name,
                  source: 'live',
                  caloriesPerGram: food.calories,
                  proteinPerGram: food.protein,
                  fatPerGram: food.fat,
                  carbsPerGram: food.carbs,
                  fiberPerGram: food.fiber,
                  parentId: Value(food.id), // Point to OLD ID
                  sourceFdcId: Value(food.sourceFdcId),
                  sourceBarcode: Value(food.sourceBarcode),
                  emoji: Value(food.emoji),
                  thumbnail: Value(food.thumbnail),
                  usageNote: Value(food.usageNote),
                ),
              );

          // 2. Copy portions
          for (final serving in food.servings) {
            await _liveDb
                .into(_liveDb.foodPortions)
                .insert(
                  FoodPortionsCompanion.insert(
                    foodId: newFoodId,
                    unit: serving.unit,
                    grams: serving.grams,
                    quantity: serving.quantity,
                  ),
                );
          }

          return newFoodId;
        });
      } else {
        // Macro-neutral change: update in-place even if used
        await (_liveDb.update(
          _liveDb.foods,
        )..where((t) => t.id.equals(food.id))).write(
          FoodsCompanion(
            name: Value(food.name),
            emoji: Value(food.emoji),
            thumbnail: Value(food.thumbnail),
            sourceBarcode: Value(food.sourceBarcode),
            hidden: Value(food.hidden),
            usageNote: Value(food.usageNote),
          ),
        );

        // Update portions metadata if any
        await (_liveDb.delete(
          _liveDb.foodPortions,
        )..where((t) => t.foodId.equals(food.id))).go();
        for (final serving in food.servings) {
          await _liveDb
              .into(_liveDb.foodPortions)
              .insert(
                FoodPortionsCompanion.insert(
                  foodId: food.id,
                  unit: serving.unit,
                  grams: serving.grams,
                  quantity: serving.quantity,
                ),
              );
        }

        return food.id;
      }
    } else {
      // NOT USED or NEW: UPDATE IN PLACE or INSERT
      if (existingLiveFood != null) {
        // Update
        await (_liveDb.update(
          _liveDb.foods,
        )..where((t) => t.id.equals(food.id))).write(
          FoodsCompanion(
            name: Value(food.name),
            caloriesPerGram: Value(food.calories),
            proteinPerGram: Value(food.protein),
            fatPerGram: Value(food.fat),
            carbsPerGram: Value(food.carbs),
            fiberPerGram: Value(food.fiber),
            sourceFdcId: Value(food.sourceFdcId),
            sourceBarcode: Value(food.sourceBarcode),
            emoji: Value(food.emoji),
            thumbnail: Value(food.thumbnail),
            hidden: Value(food.hidden),
            usageNote: Value(food.usageNote),
          ),
        );

        // Update portions: Delete all and re-insert
        await (_liveDb.delete(
          _liveDb.foodPortions,
        )..where((t) => t.foodId.equals(food.id))).go();
        for (final serving in food.servings) {
          await _liveDb
              .into(_liveDb.foodPortions)
              .insert(
                FoodPortionsCompanion.insert(
                  foodId: food.id,
                  unit: serving.unit,
                  grams: serving.grams,
                  quantity: serving.quantity,
                ),
              );
        }

        return food.id; // Correctly return int ID
      } else {
        // Insert New (handles copying ref to live or creating user-created with potential ID)
        final copied = await copyFoodToLiveDb(food, isCopy: false);
        return copied.id;
      }
    }
  }

  Future<List<model.LoggedPortion>> _resolveLoggedPortionRecipes(
    List<model.LoggedPortion> portions,
  ) async {
    final recipeIds = portions
        .where((p) => p.portion.food.source == 'recipe')
        .map((p) => p.portion.food.id)
        .toSet()
        .toList();

    if (recipeIds.isEmpty) {
      return portions;
    }

    final recipesMap = await getRecipesByIds(recipeIds);

    return portions.map((p) {
      if (p.portion.food.source == 'recipe') {
        final recipe = recipesMap[p.portion.food.id];
        if (recipe != null) {
          return model.LoggedPortion(
            id: p.id,
            timestamp: p.timestamp,
            portion: model.FoodPortion(
              food: recipe.toFood(),
              grams: p.portion.grams,
              unit: p.portion.unit,
            ),
          );
        }
      }
      return p;
    }).toList();
  }

  Future<void> deleteLoggedPortion(int id) async {
    await (_liveDb.delete(
      _liveDb.loggedPortions,
    )..where((t) => t.id.equals(id))).go();
    BackupConfigService.instance.markDirty();
  }

  /// Deletes multiple logged portions in a single batch operation
  ///
  /// This is more efficient than calling deleteLoggedPortion multiple times
  /// and ensures atomicity of the operation.
  Future<void> deleteLoggedPortions(List<int> ids) async {
    if (ids.isEmpty) return;

    await (_liveDb.delete(
      _liveDb.loggedPortions,
    )..where((t) => t.id.isIn(ids))).go();
    BackupConfigService.instance.markDirty();
  }

  Future<void> updateLoggedPortion(
    int loggedPortionId,
    model.FoodPortion newPortion,
  ) async {
    final food = newPortion.food;
    int? foodId;
    int? recipeId;

    if (food.source == 'recipe') {
      recipeId = food.id;
    } else if (food.database == model.FoodDatabase.live) {
      foodId = food.id;
    } else {
      // Should not typically happen during UPDATE unless we switch foods?
      // But logic is safe to replicate:
      final existing = await (_liveDb.select(
        _liveDb.foods,
      )..where((f) => f.sourceFdcId.equals(food.id))).getSingleOrNull();
      if (existing != null) {
        foodId = existing.id;
      } else {
        final newFood = await copyFoodToLiveDb(food);
        foodId = newFood.id;
      }
    }

    await (_liveDb.update(
      _liveDb.loggedPortions,
    )..where((t) => t.id.equals(loggedPortionId))).write(
      LoggedPortionsCompanion(
        foodId: Value(foodId),
        recipeId: Value(recipeId),
        grams: Value(newPortion.grams),
        unit: Value(newPortion.unit),
        quantity: Value(newPortion.quantity),
      ),
    );
    BackupConfigService.instance.markDirty();
  }

  // --- Weight Operations ---

  Future<void> saveWeight(model.Weight weight) async {
    // Weight entries for the same day should overwrite (as per spec)
    // To ensure "same day" logic, the date should be normalized to start of day
    // though the caller (Provider) should probably handle that, we'll be safe here.
    final dateObj = DateTime(
      weight.date.year,
      weight.date.month,
      weight.date.day,
    );
    final normalizedTimestamp = dateObj.millisecondsSinceEpoch;

    await _liveDb.transaction(() async {
      // Delete any existing weight for this date
      await (_liveDb.delete(
        _liveDb.weights,
      )..where((t) => t.date.equals(normalizedTimestamp))).go();

      // Insert new weight
      await _liveDb
          .into(_liveDb.weights)
          .insert(
            WeightsCompanion.insert(
              weight: weight.weight,
              date: normalizedTimestamp,
            ),
          );
    });

    BackupConfigService.instance.markDirty();
  }

  Future<List<model.Weight>> getWeightsForRange(
    DateTime start,
    DateTime end,
  ) async {
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    final query = _liveDb.select(_liveDb.weights)
      ..where((t) => t.date.isBetweenValues(startMs, endMs))
      ..orderBy([(t) => OrderingTerm(expression: t.date)]);

    final rows = await query.get();
    return rows.map((row) => _mapWeightData(row)).toList();
  }

  Future<void> deleteWeight(int id) async {
    await (_liveDb.delete(_liveDb.weights)..where((t) => t.id.equals(id))).go();
    BackupConfigService.instance.markDirty();
  }

  // --- Container Operations ---

  FoodContainer _mapContainerData(dynamic containerData) {
    return FoodContainer(
      id: containerData.id,
      name: containerData.name,
      weight: containerData.weight,
      unit: containerData.unit,
      thumbnail: containerData.thumbnail,
      hidden: containerData.hidden,
    );
  }

  Future<List<FoodContainer>> getAllContainers() async {
    final query = _liveDb.select(_liveDb.containers)
      ..where((t) => t.hidden.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);

    final rows = await query.get();
    return rows.map((row) => _mapContainerData(row)).toList();
  }

  Future<int> saveContainer(FoodContainer container) async {
    return await _liveDb.transaction(() async {
      if (container.id > 0) {
        // Update
        await (_liveDb.update(
          _liveDb.containers,
        )..where((t) => t.id.equals(container.id))).write(
          ContainersCompanion(
            name: Value(container.name),
            weight: Value(container.weight),
            unit: Value(container.unit),
            thumbnail: Value(container.thumbnail),
            hidden: Value(container.hidden),
          ),
        );
        BackupConfigService.instance.markDirty();
        return container.id;
      } else {
        // Insert
        final id = await _liveDb
            .into(_liveDb.containers)
            .insert(
              ContainersCompanion.insert(
                name: container.name,
                weight: container.weight,
                unit: Value(container.unit),
                thumbnail: Value(container.thumbnail),
                hidden: Value(container.hidden),
              ),
            );
        BackupConfigService.instance.markDirty();
        return id;
      }
    });
  }

  Future<void> deleteContainer(int id) async {
    // Soft delete by hiding, or hard delete?
    // Plan implied basic management. Let's do hard delete for now as they are not referenced by foreign keys in logged portions (logs embed weight/unit).
    // Actually, logs just store grams/unit. Usage doesn't link to container ID.
    // So hard delete is safe.
    await (_liveDb.delete(
      _liveDb.containers,
    )..where((t) => t.id.equals(id))).go();
    BackupConfigService.instance.markDirty();
  }

  // --- Fasting Operations ---

  /// Ensures that a special "Fasted" food exists in the database.
  Future<model.Food> _ensureFastedFood() async {
    final existing =
        await (_liveDb.select(_liveDb.foods)..where(
              (t) => t.source.equals('system') & t.name.equals('Fasted'),
            ))
            .getSingleOrNull();

    if (existing != null) {
      return _mapFoodData(existing, [], model.FoodDatabase.live);
    }

    final id = await _liveDb
        .into(_liveDb.foods)
        .insert(
          FoodsCompanion.insert(
            name: 'Fasted',
            source: 'system',
            emoji: const Value('🌙'),
            caloriesPerGram: 0,
            proteinPerGram: 0,
            fatPerGram: 0,
            carbsPerGram: 0,
            fiberPerGram: 0,
            hidden: const Value(true),
          ),
        );

    return model.Food(
      id: id,
      name: 'Fasted',
      source: 'system',
      calories: 0,
      protein: 0,
      fat: 0,
      carbs: 0,
      fiber: 0,
      emoji: '🌙',
      hidden: true,
      database: model.FoodDatabase.live,
    );
  }

  Future<bool> isFastedOnDate(DateTime date) async {
    final startOfDayMs = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    final endOfDayMs = DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;

    final fastedFood = await _ensureFastedFood();

    final query = _liveDb.select(_liveDb.loggedPortions)
      ..where(
        (t) =>
            t.foodId.equals(fastedFood.id) &
            t.logTimestamp.isBetweenValues(startOfDayMs, endOfDayMs),
      );

    final results = await query.get();
    return results.isNotEmpty;
  }

  Future<void> logFasted(DateTime date) async {
    final isCurrentlyFasted = await isFastedOnDate(date);
    if (isCurrentlyFasted) return;
    final fastedFood = await _ensureFastedFood();
    await logPortions([
      model.FoodPortion(food: fastedFood, grams: 0, unit: 'system'),
    ], date);
  }

  Future<void> toggleFasted(DateTime date) async {
    final isCurrentlyFasted = await isFastedOnDate(date);
    final fastedFood = await _ensureFastedFood();

    if (isCurrentlyFasted) {
      final startOfDayMs = DateTime(
        date.year,
        date.month,
        date.day,
      ).millisecondsSinceEpoch;
      final endOfDayMs = DateTime(
        date.year,
        date.month,
        date.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;

      await (_liveDb.delete(_liveDb.loggedPortions)..where(
            (t) =>
                t.foodId.equals(fastedFood.id) &
                t.logTimestamp.isBetweenValues(startOfDayMs, endOfDayMs),
          ))
          .go();
    } else {
      await logPortions([
        model.FoodPortion(food: fastedFood, grams: 0, unit: 'system'),
      ], date);
    }
    BackupConfigService.instance.markDirty();
  }

  Future<void> updateLoggedPortionsTimestamp(
    List<int> loggedPortionIds,
    DateTime newTimestamp,
  ) async {
    final timestamp = newTimestamp.millisecondsSinceEpoch;

    await (_liveDb.update(_liveDb.loggedPortions)
          ..where((t) => t.id.isIn(loggedPortionIds)))
        .write(LoggedPortionsCompanion(logTimestamp: Value(timestamp)));
    BackupConfigService.instance.markDirty();
  }

  Future<List<model_stats.LoggedMacroDTO>> getLoggedMacrosForDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final startOfDay = DateTime(
      start.year,
      start.month,
      start.day,
    ).millisecondsSinceEpoch;
    final endOfDay = DateTime(
      end.year,
      end.month,
      end.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;

    final query = _liveDb.select(_liveDb.loggedPortions)
      ..where((p) => p.logTimestamp.isBetweenValues(startOfDay, endOfDay));

    final rows = await query.get();

    // Batch fetch all referenced foods and recipes to avoid N+1 queries
    final foodIds = rows.map((r) => r.foodId).whereType<int>().toSet().toList();
    final recipeIds = rows
        .map((r) => r.recipeId)
        .whereType<int>()
        .toSet()
        .toList();

    final foodsMap = await getFoodsByIds(foodIds, 'live');
    final recipesMap = await getRecipesByIds(recipeIds);

    final results = <model_stats.LoggedMacroDTO>[];

    for (final row in rows) {
      double calories = 0, protein = 0, fat = 0, carbs = 0, fiber = 0;

      if (row.foodId != null) {
        final food = foodsMap[row.foodId!];
        if (food != null) {
          calories = food.calories;
          protein = food.protein;
          fat = food.fat;
          carbs = food.carbs;
          fiber = food.fiber;
        }
      } else if (row.recipeId != null) {
        final recipe = recipesMap[row.recipeId!];
        if (recipe != null) {
          final food = recipe.toFood();
          calories = food.calories;
          protein = food.protein;
          fat = food.fat;
          carbs = food.carbs;
          fiber = food.fiber;
        }
      }

      results.add(
        model_stats.LoggedMacroDTO(
          logTimestamp: DateTime.fromMillisecondsSinceEpoch(row.logTimestamp),
          grams: row.grams,
          caloriesPerGram: calories,
          proteinPerGram: protein,
          fatPerGram: fat,
          carbsPerGram: carbs,
          fiberPerGram: fiber,
        ),
      );
    }
    return results;
  }

  Future<model.Food?> getFoodById(int id, String source) async {
    final results = await getFoodsByIds([id], source);
    return results[id];
  }

  Future<Map<int, model.Food>> getFoodsByIds(
    List<int> ids,
    String source,
  ) async {
    if (ids.isEmpty) return {};

    List<dynamic> foodsData;
    if (source == 'live') {
      foodsData = await (_liveDb.select(
        _liveDb.foods,
      )..where((t) => t.id.isIn(ids))).get();
    } else {
      foodsData = await (_referenceDb.select(
        _referenceDb.foods,
      )..where((t) => t.id.isIn(ids))).get();
    }

    final servingsMap = await getServingsForFoods(ids, source);
    final database = source == 'live' ? model.FoodDatabase.live : model.FoodDatabase.reference;
    final Map<int, model.Food> results = {};

    for (final foodData in foodsData) {
      final servings = servingsMap[foodData.id] ?? [];
      results[foodData.id] = _mapFoodData(foodData, servings, database);
    }

    return results;
  }

  Future<Map<int, model.Recipe>> getRecipesByIds(List<int> ids) async {
    if (ids.isEmpty) return {};

    final recipesData = await (_liveDb.select(
      _liveDb.recipes,
    )..where((t) => t.id.isIn(ids))).get();

    final Map<int, model.Recipe> results = {};
    for (final row in recipesData) {
      results[row.id] = await getRecipeById(row.id);
    }
    return results;
  }

  Future<List<model.Recipe>> getRecipes({bool includeHidden = false}) async {
    final query = _liveDb.select(_liveDb.recipes);
    if (!includeHidden) {
      query.where((t) => t.hidden.equals(false));
    }
    query.orderBy([
      (t) =>
          OrderingTerm(expression: t.createdTimestamp, mode: OrderingMode.desc),
    ]);

    final rows = await query.get();
    final List<model.Recipe> results = [];
    for (final row in rows) {
      results.add(await getRecipeById(row.id));
    }
    return results;
  }

  Future<List<model.Recipe>> getRecipesBySearch(
    String query, {
    int? categoryId,
  }) async {
    final queryBuilder = _liveDb.select(_liveDb.recipes).join([]);

    if (categoryId != null) {
      queryBuilder.join([
        innerJoin(
          _liveDb.recipeCategoryLinks,
          _liveDb.recipeCategoryLinks.recipeId.equalsExp(_liveDb.recipes.id),
        ),
      ]);
      queryBuilder.where(
        _liveDb.recipeCategoryLinks.categoryId.equals(categoryId),
      );
    }

    queryBuilder.where(_liveDb.recipes.name.contains(query));
    queryBuilder.where(_liveDb.recipes.hidden.equals(false));

    final rows = await queryBuilder.get();

    // Filter out parents
    final parentIdRows =
        await (_liveDb.selectOnly(_liveDb.recipes)
              ..addColumns([_liveDb.recipes.parentId])
              ..where(_liveDb.recipes.parentId.isNotNull()))
            .get();
    final parentIds = parentIdRows
        .map((r) => r.read(_liveDb.recipes.parentId))
        .whereType<int>()
        .toSet();

    final List<model.Recipe> results = [];
    for (final row in rows) {
      final recipeData = row.readTable(_liveDb.recipes);
      if (!parentIds.contains(recipeData.id)) {
        results.add(await getRecipeById(recipeData.id));
      }
    }
    return results;
  }

  Future<model.Recipe> getRecipeById(int id) async {
    final recipeData = await (_liveDb.select(
      _liveDb.recipes,
    )..where((t) => t.id.equals(id))).getSingle();

    final itemsData = await (_liveDb.select(_liveDb.recipeItems)
          ..where((t) => t.recipeId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();

    final items = <model.RecipeItem>[];
    for (final item in itemsData) {
      model.Food? food;
      model.Recipe? subRecipe;

      if (item.ingredientFoodId != null) {
        food = await getFoodById(item.ingredientFoodId!, 'live');
      } else if (item.ingredientRecipeId != null) {
        subRecipe = await getRecipeById(item.ingredientRecipeId!);
      }

      items.add(
        model.RecipeItem(
          id: item.id,
          food: food,
          recipe: subRecipe,
          grams: item.grams,
          unit: item.unit,
          position: item.position,
        ),
      );
    }

    final categories = await getCategoriesForRecipe(id);

    return model.Recipe(
      id: recipeData.id,
      name: recipeData.name,
      emoji: recipeData.emoji,
      thumbnail: recipeData.thumbnail,
      servingsCreated: recipeData.servingsCreated,
      finalWeightGrams: recipeData.finalWeightGrams,
      portionName: recipeData.portionName,
      notes: recipeData.notes,
      link: recipeData.link,
      isTemplate: recipeData.isTemplate,
      hidden: recipeData.hidden,
      parentId: recipeData.parentId,
      createdTimestamp: recipeData.createdTimestamp,
      items: items,
      categories: categories,
    );
  }

  Future<List<model.Category>> getCategoriesForRecipe(int recipeId) async {
    final query = _liveDb.select(_liveDb.recipeCategoryLinks).join([
      innerJoin(
        _liveDb.categories,
        _liveDb.categories.id.equalsExp(_liveDb.recipeCategoryLinks.categoryId),
      ),
    ])..where(_liveDb.recipeCategoryLinks.recipeId.equals(recipeId));

    final rows = await query.get();
    return rows.map((row) {
      final cat = row.readTable(_liveDb.categories);
      return model.Category(id: cat.id, name: cat.name);
    }).toList();
  }

  Future<int> saveRecipe(
    model.Recipe recipe, {
    bool forceUpdateInPlace = false,
  }) async {
    bool isUsed = false;
    model.Recipe? existingRecipe;
    if (recipe.id > 0) {
      isUsed = await isRecipeReferenced(recipe.id);
      existingRecipe = await getRecipeById(recipe.id);
    }

    final result = await _liveDb.transaction(() async {
      int recipeId;
      bool shouldVersion =
          !forceUpdateInPlace &&
          isUsed &&
          existingRecipe != null &&
          !isRecipeNutritionallyEquivalent(existingRecipe, recipe);

      if (shouldVersion) {
        // SMART VERSIONING: Create new recipe, hide old one
        recipeId = await _liveDb
            .into(_liveDb.recipes)
            .insert(
              RecipesCompanion.insert(
                name: recipe.name,
                emoji: Value(recipe.emoji),
                thumbnail: Value(recipe.thumbnail),
                servingsCreated: Value(recipe.servingsCreated),
                finalWeightGrams: Value(recipe.finalWeightGrams),
                portionName: Value(recipe.portionName),
                notes: Value(recipe.notes),
                link: Value(recipe.link),
                isTemplate: Value(recipe.isTemplate),
                hidden: Value(recipe.hidden),
                parentId: Value(recipe.id), // Point to old ID
                createdTimestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );

        // Hide the old recipe
        await (_liveDb.update(_liveDb.recipes)
              ..where((t) => t.id.equals(recipe.id)))
            .write(const RecipesCompanion(hidden: Value(true)));
        // We don't need to delete items from old recipe, they stay for history
      } else if (recipe.id > 0) {
        recipeId = recipe.id;
        // Update basic info in-place
        await (_liveDb.update(
          _liveDb.recipes,
        )..where((t) => t.id.equals(recipeId))).write(
          RecipesCompanion(
            name: Value(recipe.name),
            emoji: Value(recipe.emoji),
            thumbnail: Value(recipe.thumbnail),
            servingsCreated: Value(recipe.servingsCreated),
            finalWeightGrams: Value(recipe.finalWeightGrams),
            portionName: Value(recipe.portionName),
            notes: Value(recipe.notes),
            link: Value(recipe.link),
            isTemplate: Value(recipe.isTemplate),
            hidden: Value(recipe.hidden),
            parentId: Value(recipe.parentId),
          ),
        );

        // Clear associated data for re-insertion
        await (_liveDb.delete(
          _liveDb.recipeItems,
        )..where((t) => t.recipeId.equals(recipeId))).go();
        await (_liveDb.delete(
          _liveDb.recipeCategoryLinks,
        )..where((t) => t.recipeId.equals(recipeId))).go();
      } else {
        recipeId = await _liveDb
            .into(_liveDb.recipes)
            .insert(
              RecipesCompanion.insert(
                name: recipe.name,
                emoji: Value(recipe.emoji),
                thumbnail: Value(recipe.thumbnail),
                servingsCreated: Value(recipe.servingsCreated),
                finalWeightGrams: Value(recipe.finalWeightGrams),
                portionName: Value(recipe.portionName),
                notes: Value(recipe.notes),
                link: Value(recipe.link),
                isTemplate: Value(recipe.isTemplate),
                hidden: Value(recipe.hidden),
                parentId: Value(recipe.parentId),
                createdTimestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      }

      for (int i = 0; i < recipe.items.length; i++) {
        final item = recipe.items[i];
        int? foodId;
        int? subRecipeId;

        if (item.food != null) {
          final persistedFood = await ensureFoodExists(item.food!);
          foodId = persistedFood.id;
        } else if (item.recipe != null) {
          subRecipeId = item.recipe!.id;
        }

        await _liveDb
            .into(_liveDb.recipeItems)
            .insert(
              RecipeItemsCompanion.insert(
                recipeId: recipeId,
                ingredientFoodId: Value(foodId),
                ingredientRecipeId: Value(subRecipeId),
                grams: item.grams,
                unit: item.unit,
                position: Value(i),
              ),
            );
      }

      for (final category in recipe.categories) {
        await _liveDb
            .into(_liveDb.recipeCategoryLinks)
            .insert(
              RecipeCategoryLinksCompanion.insert(
                recipeId: recipeId,
                categoryId: category.id,
              ),
            );
      }

      return recipeId;
    });
    BackupConfigService.instance.markDirty();
    return result;
  }

  Future<void> deleteRecipe(int id) async {
    final isLogged = await isRecipeLogged(id);
    final isUsed = await isRecipeUsedAsIngredient(id);

    if (isLogged || isUsed) {
      await hideRecipe(id);
    } else {
      await _liveDb.transaction(() async {
        await (_liveDb.delete(
          _liveDb.recipeItems,
        )..where((t) => t.recipeId.equals(id))).go();
        await (_liveDb.delete(
          _liveDb.recipeCategoryLinks,
        )..where((t) => t.recipeId.equals(id))).go();
        await (_liveDb.delete(
          _liveDb.recipes,
        )..where((t) => t.id.equals(id))).go();
      });
    }
  }

  Future<List<model.Category>> getCategories() async {
    final rows = await _liveDb.select(_liveDb.categories).get();
    return rows
        .map((row) => model.Category(id: row.id, name: row.name))
        .toList();
  }

  Future<int> addCategory(String name) async {
    final id = await _liveDb
        .into(_liveDb.categories)
        .insert(CategoriesCompanion.insert(name: name));
    BackupConfigService.instance.markDirty();
    return id;
  }

  Future<model.Food> ensureFoodExists(model.Food food) async {
    // If it's already in the live database, return it
    if (food.database == model.FoodDatabase.live) {
      return food;
    }

    // Otherwise, check if we've already copied it using sourceFdcId
    if (food.id > 0) {
      final existingByFdc = await (_liveDb.select(
        _liveDb.foods,
      )..where((t) => t.sourceFdcId.equals(food.id))).getSingleOrNull();

      if (existingByFdc != null) {
        final servings = await getServingsForFood(existingByFdc.id, 'live');
        return _mapFoodData(existingByFdc, servings, model.FoodDatabase.live);
      }
    }

    // Fallback to name/macro matching for non-fdc items (if any) or old data
    final existingQuery = _liveDb.select(_liveDb.foods)
      ..where((t) {
        Expression<bool> predicate =
            t.name.equals(food.name) &
            t.caloriesPerGram.equals(food.calories) &
            t.proteinPerGram.equals(food.protein);
        return predicate;
      });

    final existing = await existingQuery.getSingleOrNull();
    if (existing != null) {
      final servings = await getServingsForFood(existing.id, 'live');
      return _mapFoodData(existing, servings, model.FoodDatabase.live);
    }

    // If not, save it to the live database (copy logic)
    return await copyFoodToLiveDb(food, isCopy: false);
  }

  Future<Map<int, String?>> getFoodsUsageNotes(List<model.Food> foods) async {
    if (foods.isEmpty) return {};

    final foodIds = foods.map((f) => f.id).toList();
    final Map<int, String?> results = {};

    // Batch fetch logged entries
    final loggedFoodIdsRows =
        await (_liveDb.selectOnly(_liveDb.loggedPortions)
              ..addColumns([_liveDb.loggedPortions.foodId])
              ..where(_liveDb.loggedPortions.foodId.isIn(foodIds)))
            .get();
    final loggedFoodSet = loggedFoodIdsRows
        .map((r) => r.read(_liveDb.loggedPortions.foodId))
        .toSet();

    final loggedRecipeIdsRows =
        await (_liveDb.selectOnly(_liveDb.loggedPortions)
              ..addColumns([_liveDb.loggedPortions.recipeId])
              ..where(_liveDb.loggedPortions.recipeId.isIn(foodIds)))
            .get();
    final loggedRecipeSet = loggedRecipeIdsRows
        .map((r) => r.read(_liveDb.loggedPortions.recipeId))
        .toSet();

    // Batch fetch usage as ingredients
    final usedFoodIdsRows =
        await (_liveDb.selectOnly(_liveDb.recipeItems)
              ..addColumns([_liveDb.recipeItems.ingredientFoodId])
              ..where(_liveDb.recipeItems.ingredientFoodId.isIn(foodIds)))
            .get();
    final usedFoodSet = usedFoodIdsRows
        .map((r) => r.read(_liveDb.recipeItems.ingredientFoodId))
        .toSet();

    final usedRecipeIdsRows =
        await (_liveDb.selectOnly(_liveDb.recipeItems)
              ..addColumns([_liveDb.recipeItems.ingredientRecipeId])
              ..where(_liveDb.recipeItems.ingredientRecipeId.isIn(foodIds)))
            .get();
    final usedRecipeSet = usedRecipeIdsRows
        .map((r) => r.read(_liveDb.recipeItems.ingredientRecipeId))
        .toSet();

    for (final food in foods) {
      final isRecipe = food.source == 'recipe';
      final isLogged = isRecipe
          ? loggedRecipeSet.contains(food.id)
          : loggedFoodSet.contains(food.id);
      final isUsed = isRecipe
          ? usedRecipeSet.contains(food.id)
          : usedFoodSet.contains(food.id);

      if (isLogged && isUsed) {
        results[food.id] = 'Logged • In Recipe';
      } else if (isLogged) {
        results[food.id] = 'Logged';
      } else if (isUsed) {
        results[food.id] = 'In Recipe';
      } else {
        results[food.id] = null;
      }
    }
    return results;
  }

  Future<model.Food> copyFoodToLiveDb(
    model.Food sourceFood, {
    bool isCopy = false,
  }) async {
    return await _liveDb.transaction(() async {
      final foodName = isCopy ? '${sourceFood.name} - Copy' : sourceFood.name;

      // Check if a food with the same name and macros already exists
      final existingQuery = _liveDb.select(_liveDb.foods)
        ..where((t) => t.name.equals(foodName))
        ..where((t) => t.caloriesPerGram.equals(sourceFood.calories))
        ..where((t) => t.proteinPerGram.equals(sourceFood.protein))
        ..where((t) => t.fatPerGram.equals(sourceFood.fat))
        ..where((t) => t.carbsPerGram.equals(sourceFood.carbs))
        ..where((t) => t.fiberPerGram.equals(sourceFood.fiber));

      final existing = await existingQuery.getSingleOrNull();
      if (existing != null) {
        // Update metadata for existing food
        await (_liveDb.update(
          _liveDb.foods,
        )..where((t) => t.id.equals(existing.id))).write(
          FoodsCompanion(
            name: Value(foodName),
            emoji: Value(sourceFood.emoji),
            thumbnail: Value(sourceFood.thumbnail),
            usageNote: Value(sourceFood.usageNote),
          ),
        );

        // Add barcode to existing food if not already present
        if (sourceFood.sourceBarcode != null &&
            sourceFood.sourceBarcode!.isNotEmpty) {
          final existingBarcode = await (_liveDb.select(_liveDb.foodBarcodes)
                ..where((b) =>
                    b.foodId.equals(existing.id) &
                    b.barcode.equals(sourceFood.sourceBarcode!)))
              .getSingleOrNull();

          if (existingBarcode == null) {
            await _liveDb.into(_liveDb.foodBarcodes).insert(
                  FoodBarcodesCompanion.insert(
                    foodId: existing.id,
                    barcode: sourceFood.sourceBarcode!,
                  ),
                );
          }
        }

        final servings = await getServingsForFood(existing.id, 'live');
        return _mapFoodData(existing, servings, model.FoodDatabase.live);
      }

      // Insert new food into live database, preserving original source provenance
      final foodId = await _liveDb
          .into(_liveDb.foods)
          .insert(
            FoodsCompanion.insert(
              name: foodName,
              source: sourceFood.source,
              emoji: Value(sourceFood.emoji),
              thumbnail: Value(sourceFood.thumbnail),
              usageNote: Value(sourceFood.usageNote),
              caloriesPerGram: sourceFood.calories,
              proteinPerGram: sourceFood.protein,
              fatPerGram: sourceFood.fat,
              carbsPerGram: sourceFood.carbs,
              fiberPerGram: sourceFood.fiber,
              parentId: const Value(null),
              sourceFdcId: Value(
                (sourceFood.source != 'live' && sourceFood.source != 'off')
                    ? sourceFood.id
                    : null,
              ),
              sourceBarcode: Value(sourceFood.sourceBarcode),
            ),
          );

      // Save servings
      for (final serving in sourceFood.servings) {
        await _liveDb
            .into(_liveDb.foodPortions)
            .insert(
              FoodPortionsCompanion.insert(
                foodId: foodId,
                unit: serving.unit,
                grams: serving.grams,
                quantity: serving.quantity,
              ),
            );
      }

      // Add barcode to food_barcodes table if present
      if (sourceFood.sourceBarcode != null &&
          sourceFood.sourceBarcode!.isNotEmpty) {
        // Check if this barcode is already on this food (shouldn't happen, but be safe)
        final existingBarcode = await (_liveDb.select(_liveDb.foodBarcodes)
              ..where((b) =>
                  b.foodId.equals(foodId) &
                  b.barcode.equals(sourceFood.sourceBarcode!)))
            .getSingleOrNull();

        if (existingBarcode == null) {
          await _liveDb.into(_liveDb.foodBarcodes).insert(
                FoodBarcodesCompanion.insert(
                  foodId: foodId,
                  barcode: sourceFood.sourceBarcode!,
                ),
              );
        }
      }

      final servings = await getServingsForFood(foodId, 'live');
      final newFoodRow = await (_liveDb.select(
        _liveDb.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      return _mapFoodData(newFoodRow, servings, model.FoodDatabase.live);
    });
  }

  Future<void> softDeleteFood(int foodId) async {
    await (_liveDb.update(_liveDb.foods)..where((t) => t.id.equals(foodId)))
        .write(const FoodsCompanion(hidden: Value(true)));
    BackupConfigService.instance.markDirty();
  }

  Future<bool> isFoodReferenced(int foodId) async {
    // Check if referenced in logged_portions
    final loggedQuery = _liveDb.select(_liveDb.loggedPortions)
      ..where((t) => t.foodId.equals(foodId))
      ..limit(1);
    final logged = await loggedQuery.getSingleOrNull();

    // Check if used in recipes
    final usedQuery = _liveDb.select(_liveDb.recipeItems)
      ..where((t) => t.ingredientFoodId.equals(foodId))
      ..limit(1);
    final used = await usedQuery.getSingleOrNull();

    return logged != null || used != null;
  }

  Future<void> deleteFood(int foodId) async {
    final isReferenced = await isFoodReferenced(foodId);

    if (isReferenced) {
      // Soft delete if referenced
      await softDeleteFood(foodId);
    } else {
      // Hard delete if not referenced
      await _liveDb.transaction(() async {
        await (_liveDb.delete(
          _liveDb.foodPortions,
        )..where((t) => t.foodId.equals(foodId))).go();
        await (_liveDb.delete(
          _liveDb.foods,
        )..where((t) => t.id.equals(foodId))).go();
      });
    }
  }

  // ========== NEW METHODS FOR TEXT-BASED SEARCH ==========

  /// Query only live database foods by name
  Future<List<model.Food>> searchLiveFoodsByName(String query) async {
    if (query.isEmpty) return [];
    final normalized = query.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final lowerCaseQuery = '%${normalized.toLowerCase()}%';

    final liveFoodsData =
        await (_liveDb.select(_liveDb.foods)
              ..where((f) => FunctionCallExpression<String>(
                'replace',
                [f.name.lower(), const Constant(','), const Constant(' ')],
              ).like(lowerCaseQuery))
              ..where((f) => f.hidden.equals(false)))
            .get();

    // Filter out old versions: only hide a parent if a visible child with
    // source='live' points to it. Non-live sources (off, FOUNDATION, etc.)
    // can have coincidental parentId collisions that don't represent real
    // version lineage.
    final parentIds = liveFoodsData
        .where((f) => f.parentId != null && f.source == 'live')
        .map((f) => f.parentId!)
        .toSet();

    final List<model.Food> filteredLiveFoods = [];
    final List<int> idsToFetch = [];
    for (final foodData in liveFoodsData) {
      if (!parentIds.contains(foodData.id)) {
        filteredLiveFoods.add(
          _mapFoodData(foodData, [], model.FoodDatabase.live),
        );
        idsToFetch.add(foodData.id);
      }
    }

    final servingsMap = await getServingsForFoods(idsToFetch, 'live');
    final List<model.Food> liveFoods = [];
    for (var f in filteredLiveFoods) {
      liveFoods.add(f.copyWith(servings: servingsMap[f.id] ?? []));
    }

    return liveFoods;
  }

  /// Query only reference database foods by name
  Future<List<model.Food>> searchReferenceFoodsByName(String query) async {
    if (query.isEmpty) return [];
    final normalized = query.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final lowerCaseQuery = '%${normalized.toLowerCase()}%';

    final refFoodsData = await (_referenceDb.select(
      _referenceDb.foods,
    )..where((f) => FunctionCallExpression<String>(
      'replace',
      [f.name.lower(), const Constant(','), const Constant(' ')],
    ).like(lowerCaseQuery))).get();

    final idsToFetch = refFoodsData.map((f) => f.id).toList();
    final servingsMap = await getServingsForFoods(idsToFetch, 'reference');

    final List<model.Food> refFoods = [];
    for (final foodData in refFoodsData) {
      refFoods.add(_mapFoodData(foodData, servingsMap[foodData.id] ?? [], model.FoodDatabase.reference));
    }

    return refFoods;
  }

  /// Get usage statistics for a list of food IDs
  /// Queries LoggedPortions joined with LoggedFoods to count logs
  Future<Map<int, FoodUsageStats>> getFoodUsageStats(List<int> foodIds) async {
    if (foodIds.isEmpty) return {};

    final Map<int, FoodUsageStats> results = {};

    for (final foodId in foodIds) {
      // Query all logged portions for this food
      // Logic: foodId in LoggedPortions == foodId (Source: Live)
      // OR foodId is linked via sourceFdcId if we want to be smart.
      // But getFoodUsageStats is typically called with IDs from search results.
      // If search result is Live, ID is Live ID. Usage is directly on it.
      // If search result is Ref, ID is Ref ID. Usage checks if any Live food pointing to it is logged?
      // Or just check if Ref ID is logged (not possible directly)?
      // For now, assume caller passes Live IDs for usage visualization,
      // OR simple direct equality if we logged Ref items (which we copy to Live).
      // If we copied Ref (1) to Live (100), logs are on 100.
      // If I ask stats for Ref (1), I won't find logs on 1. I need to find logs on 100.
      // So I check: usage where food.sourceFdcId == id OR food.id == id.

      final query =
          _liveDb.select(_liveDb.loggedPortions).join([
              innerJoin(
                _liveDb.foods,
                _liveDb.foods.id.equalsExp(_liveDb.loggedPortions.foodId),
              ),
            ])
            ..where(
              _liveDb.loggedPortions.foodId.equals(foodId) |
                  _liveDb.foods.sourceFdcId.equals(foodId),
            )
            ..orderBy([
              OrderingTerm(
                expression: _liveDb.loggedPortions.logTimestamp,
                mode: OrderingMode.desc,
              ),
            ]);

      final rows = await query.get();

      if (rows.isEmpty) {
        results[foodId] = FoodUsageStats(
          foodId: foodId,
          logCount: 0,
          lastLoggedAt: null,
          logTimestamps: [],
        );
        continue;
      }

      final logTimestamps = rows
          .map(
            (row) => DateTime.fromMillisecondsSinceEpoch(
              row.readTable(_liveDb.loggedPortions).logTimestamp,
            ),
          )
          .toList();

      results[foodId] = FoodUsageStats(
        foodId: foodId,
        logCount: rows.length, // accurate count of logs
        lastLoggedAt: logTimestamps.first,
        logTimestamps: logTimestamps,
      );
    }

    return results;
  }

  /// Returns solo food log entries from the last [lookbackDays] days.
  /// A solo log is a logTimestamp that has exactly one portion,
  /// where that portion is a food (not a recipe) and the food is not hidden.
  Future<List<({int foodId, int logTimestamp})>> getSoloFoodLogs({
    int lookbackDays = 30,
  }) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: lookbackDays))
        .millisecondsSinceEpoch;

    final rows = await _liveDb.customSelect(
      '''
      SELECT lp.loggedFoodId AS foodId, lp.log_timestamp
      FROM logged_portions lp
      INNER JOIN foods f ON f.id = lp.loggedFoodId
      WHERE lp.log_timestamp >= ?
        AND lp.loggedFoodId IS NOT NULL
        AND lp.recipeId IS NULL
        AND f.hidden = 0
        AND lp.log_timestamp IN (
          SELECT log_timestamp FROM logged_portions
          GROUP BY log_timestamp HAVING COUNT(*) = 1
        )
      ORDER BY lp.log_timestamp DESC
      ''',
      variables: [Variable.withInt(cutoff)],
    ).get();

    return rows.map((row) {
      return (
        foodId: row.read<int>('foodId'),
        logTimestamp: row.read<int>('log_timestamp'),
      );
    }).toList();
  }

  /// Get usage statistics for a list of recipe IDs
  /// Queries LoggedPortions joined with LoggedFoods where originalFoodSource='recipe'
  Future<Map<int, FoodUsageStats>> getRecipeUsageStats(
    List<int> recipeIds,
  ) async {
    if (recipeIds.isEmpty) return {};

    final Map<int, FoodUsageStats> results = {};

    for (final recipeId in recipeIds) {
      // Query all logged portions for this recipe
      final query = _liveDb.select(_liveDb.loggedPortions)
        ..where((t) => t.recipeId.equals(recipeId))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.logTimestamp, mode: OrderingMode.desc),
        ]);

      final rows = await query.get();

      if (rows.isEmpty) {
        results[recipeId] = FoodUsageStats(
          foodId: recipeId,
          logCount: 0,
          lastLoggedAt: null,
          logTimestamps: [],
        );
        continue;
      }

      final logTimestamps = rows
          .map((row) => DateTime.fromMillisecondsSinceEpoch(row.logTimestamp))
          .toList();

      results[recipeId] = FoodUsageStats(
        foodId: recipeId,
        logCount: rows.length,
        lastLoggedAt: logTimestamps.first,
        logTimestamps: logTimestamps,
      );
    }

    return results;
  }

  Future<bool> isRecipeReferenced(int id) async {
    return await isRecipeLogged(id) || await isRecipeUsedAsIngredient(id);
  }

  bool _isFoodNutritionallyEquivalent(model.Food oldF, model.Food newF) {
    if ((oldF.calories - newF.calories).abs() > 0.001) return false;
    if ((oldF.protein - newF.protein).abs() > 0.001) return false;
    if ((oldF.fat - newF.fat).abs() > 0.001) return false;
    if ((oldF.carbs - newF.carbs).abs() > 0.001) return false;
    if ((oldF.fiber - newF.fiber).abs() > 0.001) return false;

    if (oldF.servings.length != newF.servings.length) return false;
    for (final serving in newF.servings) {
      bool found = oldF.servings.any(
        (old) =>
            old.unit == serving.unit &&
            (old.grams - serving.grams).abs() < 0.001,
      );
      if (!found) return false;
    }
    return true;
  }

  bool isRecipeNutritionallyEquivalent(model.Recipe oldR, model.Recipe newR) {
    if ((oldR.servingsCreated - newR.servingsCreated).abs() > 0.001) {
      return false;
    }
    if (oldR.finalWeightGrams != newR.finalWeightGrams) return false;
    if (oldR.items.length != newR.items.length) return false;

    for (var newItem in newR.items) {
      bool found = oldR.items.any(
        (oldItem) =>
            (oldItem.grams - newItem.grams).abs() < 0.001 &&
            oldItem.unit == newItem.unit &&
            (oldItem.food?.id == newItem.food?.id &&
                oldItem.recipe?.id == newItem.recipe?.id),
      );
      if (!found) return false;
    }
    return true;
  }

  /// Filter reference foods that have live versions
  /// Removes reference foods whose ID is in live foods' sourceFdcId
  Future<List<model.Food>> filterReferenceFoodsWithLiveVersions(
    List<model.Food> referenceFoods,
    List<model.Food> liveFoods,
  ) async {
    // Collect all sourceFdcId values from live foods
    final liveSourceIds = liveFoods
        .map((f) => f.sourceFdcId)
        .whereType<int>()
        .toSet();

    // Filter out reference foods that have a live version
    return referenceFoods
        .where((refFood) => !liveSourceIds.contains(refFood.id))
        .toList();
  }

  /// Get distinct unit names from food portions (excluding 'g')
  /// Used for populating unit dropdown in food edit screen
  Future<List<String>> getDistinctUnits() async {
    final query = _liveDb.selectOnly(_liveDb.foodPortions, distinct: true)
      ..addColumns([_liveDb.foodPortions.unit])
      ..where(_liveDb.foodPortions.unit.isNotValue('g'));

    final results = await query.get();
    return results
        .map((row) => row.read(_liveDb.foodPortions.unit))
        .whereType<String>()
        .toList()
      ..sort();
  }

  /// Get the system Quick Add food, creating it if it doesn't exist.
  /// This food has 1 calorie per gram, 0 for other macros.
  Future<model.Food> getSystemQuickAddFood() async {
    // Try to find existing system Quick Add food
    final existingData = await (_liveDb.select(_liveDb.foods)
          ..where((f) => f.name.equals('Quick Add'))
          ..where((f) => f.source.equals('system')))
        .getSingleOrNull();

    if (existingData != null) {
      final servings = await getServingsForFood(existingData.id, 'live');
      return _mapFoodData(existingData, servings, model.FoodDatabase.live);
    }

    // Create the system Quick Add food
    final foodId = await _liveDb.into(_liveDb.foods).insert(
      FoodsCompanion.insert(
        name: 'Quick Add',
        source: 'system',
        caloriesPerGram: 1.0, // 1 cal per gram
        proteinPerGram: 0.0,
        fatPerGram: 0.0,
        carbsPerGram: 0.0,
        fiberPerGram: 0.0,
        emoji: const Value('⚡'),
        hidden: const Value(true),
      ),
    );

    // Add gram serving
    await _liveDb.into(_liveDb.foodPortions).insert(
      FoodPortionsCompanion.insert(
        foodId: foodId,
        unit: 'g',
        grams: 1.0,
        quantity: 1.0,
      ),
    );

    return model.Food(
      id: foodId,
      name: 'Quick Add',
      source: 'system',
      calories: 1.0,
      protein: 0.0,
      fat: 0.0,
      carbs: 0.0,
      fiber: 0.0,
      emoji: '⚡',
      hidden: true,
      database: model.FoodDatabase.live,
      servings: [
        const model_serving.FoodServing(
          foodId: 0,
          unit: 'g',
          grams: 1.0,
          quantity: 1.0,
        ),
      ],
    );
  }

  /// Ensures the system Quick Add food exists. Called during init.
  Future<void> _ensureSystemQuickAddFood() async {
    await getSystemQuickAddFood();
  }

  // ========== DUPLICATE FOOD MERGE ==========

  Future<Set<int>> getFoodIdsWithBarcodes(List<int> foodIds) async {
    if (foodIds.isEmpty) return {};
    final rows = await (_liveDb.select(_liveDb.foodBarcodes)
          ..where((t) => t.foodId.isIn(foodIds)))
        .get();
    return rows.map((r) => r.foodId).toSet();
  }

  Future<Map<int, int>> getRecipeUsageCounts(List<int> foodIds) async {
    if (foodIds.isEmpty) return {};
    final rows = await (_liveDb.select(_liveDb.recipeItems)
          ..where((t) => t.ingredientFoodId.isIn(foodIds)))
        .get();
    final Map<int, int> counts = {for (final id in foodIds) id: 0};
    for (final row in rows) {
      final fid = row.ingredientFoodId;
      if (fid != null) counts[fid] = (counts[fid] ?? 0) + 1;
    }
    return counts;
  }

  /// Returns groups of foods connected by `parentId`. Each group is a single
  /// version-chain cluster (parent + child + grandchild + …). Only includes
  /// chains of size >= 2. Excludes `source='system'`.
  ///
  /// These chains arise from the smart-versioning path in [saveFood] (and
  /// historically from a "rev on rename" bug). Surfacing them as merge
  /// candidates lets the user consolidate the chain even when macros drifted.
  Future<List<List<model.Food>>> findVersionChainGroups() async {
    final liveRows = await (_liveDb.select(_liveDb.foods)
          ..where((f) => f.source.equals('system').not()))
        .get();
    if (liveRows.length < 2) return [];

    final idToIndex = <int, int>{
      for (int i = 0; i < liveRows.length; i++) liveRows[i].id: i,
    };

    final n = liveRows.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }
    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    bool anyEdge = false;
    for (int i = 0; i < n; i++) {
      final pid = liveRows[i].parentId;
      if (pid == null) continue;
      final j = idToIndex[pid];
      if (j == null) continue; // parent not in live set (shouldn't happen)
      union(i, j);
      anyEdge = true;
    }
    if (!anyEdge) return [];

    final Map<int, List<int>> byRoot = {};
    for (int i = 0; i < n; i++) {
      final r = find(i);
      // Only keep clusters that actually have an edge — singletons stay out.
      byRoot.putIfAbsent(r, () => []).add(i);
    }
    final groupIndices =
        byRoot.values.where((g) => g.length >= 2).toList();
    if (groupIndices.isEmpty) return [];

    final allIds =
        groupIndices.expand((g) => g.map((i) => liveRows[i].id)).toList();
    final servingsMap = await getServingsForFoods(allIds, 'live');

    return groupIndices
        .map((g) => g
            .map((i) => _mapFoodData(
                  liveRows[i],
                  servingsMap[liveRows[i].id] ?? [],
                  model.FoodDatabase.live,
                ))
            .toList())
        .toList();
  }

  Future<List<List<model.Food>>> findDuplicateFoodGroups({
    required double thresholdPct,
  }) async {
    // Every row in the live DB is user-owned. The `source` column records
    // provenance (e.g., 'off' for OpenFoodFacts imports, 'FOUNDATION' for
    // USDA imports) — these are all legitimate merge candidates. Only the
    // 'system' pseudo-foods (Quick Add, Fasted) are excluded.
    final liveRows = await (_liveDb.select(_liveDb.foods)
          ..where((f) => f.source.equals('system').not()))
        .get();

    if (liveRows.length < 2) return [];

    final threshold = thresholdPct / 100.0;
    bool macrosMatch(dynamic a, dynamic b) {
      bool within(double x, double y) {
        return (x - y).abs() <= [x.abs(), y.abs(), 0.001].reduce((m, n) => m > n ? m : n) * threshold;
      }
      return within(a.caloriesPerGram, b.caloriesPerGram) &&
          within(a.proteinPerGram, b.proteinPerGram) &&
          within(a.fatPerGram, b.fatPerGram) &&
          within(a.carbsPerGram, b.carbsPerGram) &&
          within(a.fiberPerGram, b.fiberPerGram);
    }

    final n = liveRows.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }
    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (macrosMatch(liveRows[i], liveRows[j])) union(i, j);
      }
    }

    final Map<int, List<int>> byRoot = {};
    for (int i = 0; i < n; i++) {
      byRoot.putIfAbsent(find(i), () => []).add(i);
    }

    final groupIndices = byRoot.values.where((g) => g.length >= 2).toList();
    if (groupIndices.isEmpty) return [];

    final allIds = groupIndices.expand((g) => g.map((i) => liveRows[i].id)).toList();
    final servingsMap = await getServingsForFoods(allIds, 'live');

    return groupIndices
        .map((g) => g
            .map((i) => _mapFoodData(
                  liveRows[i],
                  servingsMap[liveRows[i].id] ?? [],
                  model.FoodDatabase.live,
                ))
            .toList())
        .toList();
  }

  Future<MergePredictedCounts> getMergePredictedCounts({
    required int loserId,
  }) async {
    final logs = await (_liveDb.select(_liveDb.loggedPortions)
          ..where((t) => t.foodId.equals(loserId)))
        .get();
    final recipeItems = await (_liveDb.select(_liveDb.recipeItems)
          ..where((t) => t.ingredientFoodId.equals(loserId)))
        .get();
    final parentChains = await (_liveDb.select(_liveDb.foods)
          ..where((t) => t.parentId.equals(loserId)))
        .get();
    final portions = await (_liveDb.select(_liveDb.foodPortions)
          ..where((t) => t.foodId.equals(loserId)))
        .get();
    final barcodes = await (_liveDb.select(_liveDb.foodBarcodes)
          ..where((t) => t.foodId.equals(loserId)))
        .get();
    return MergePredictedCounts(
      loggedToRepoint: logs.length,
      recipeToRepoint: recipeItems.length,
      parentChainsToRepoint: parentChains.length,
      portionsToDrop: portions.length,
      barcodesToDrop: barcodes.length,
    );
  }

  Future<MergeResult> mergeFoods({
    required int keeperId,
    required int loserId,
  }) async {
    if (keeperId == loserId) {
      throw ArgumentError('keeperId and loserId must differ');
    }
    final keeper = await (_liveDb.select(_liveDb.foods)
          ..where((t) => t.id.equals(keeperId)))
        .getSingleOrNull();
    final loser = await (_liveDb.select(_liveDb.foods)
          ..where((t) => t.id.equals(loserId)))
        .getSingleOrNull();
    if (keeper == null || loser == null) {
      throw ArgumentError('keeper or loser not found');
    }
    if (keeper.source == 'system' || loser.source == 'system') {
      throw ArgumentError('system foods cannot be merged');
    }

    final sampleTimestampRows = await (_liveDb.select(_liveDb.loggedPortions)
          ..where((t) => t.foodId.equals(loserId))
          ..limit(5))
        .get();
    final sampleTimestamps =
        sampleTimestampRows.map((r) => r.logTimestamp).toList();

    final result = await _liveDb.transaction(() async {
      final expectedLogs = (await (_liveDb.select(_liveDb.loggedPortions)
                ..where((t) => t.foodId.equals(loserId)))
              .get())
          .length;
      final actualLogs = await (_liveDb.update(_liveDb.loggedPortions)
            ..where((t) => t.foodId.equals(loserId)))
          .write(LoggedPortionsCompanion(foodId: Value(keeperId)));
      if (actualLogs != expectedLogs) {
        throw MergeIntegrityException(
          'logged_portions: wrote $actualLogs, expected $expectedLogs',
        );
      }

      final expectedRecipe = (await (_liveDb.select(_liveDb.recipeItems)
                ..where((t) => t.ingredientFoodId.equals(loserId)))
              .get())
          .length;
      final actualRecipe = await (_liveDb.update(_liveDb.recipeItems)
            ..where((t) => t.ingredientFoodId.equals(loserId)))
          .write(RecipeItemsCompanion(ingredientFoodId: Value(keeperId)));
      if (actualRecipe != expectedRecipe) {
        throw MergeIntegrityException(
          'recipe_items: wrote $actualRecipe, expected $expectedRecipe',
        );
      }

      final expectedParent = (await (_liveDb.select(_liveDb.foods)
                ..where((t) => t.parentId.equals(loserId)))
              .get())
          .length;
      final actualParent = await (_liveDb.update(_liveDb.foods)
            ..where((t) => t.parentId.equals(loserId)))
          .write(FoodsCompanion(parentId: Value(keeperId)));
      if (actualParent != expectedParent) {
        throw MergeIntegrityException(
          'foods.parentId: wrote $actualParent, expected $expectedParent',
        );
      }

      final expectedPortions = (await (_liveDb.select(_liveDb.foodPortions)
                ..where((t) => t.foodId.equals(loserId)))
              .get())
          .length;
      final actualPortions = await (_liveDb.delete(_liveDb.foodPortions)
            ..where((t) => t.foodId.equals(loserId)))
          .go();
      if (actualPortions != expectedPortions) {
        throw MergeIntegrityException(
          'food_portions: deleted $actualPortions, expected $expectedPortions',
        );
      }

      final expectedBarcodes = (await (_liveDb.select(_liveDb.foodBarcodes)
                ..where((t) => t.foodId.equals(loserId)))
              .get())
          .length;
      final actualBarcodes = await (_liveDb.delete(_liveDb.foodBarcodes)
            ..where((t) => t.foodId.equals(loserId)))
          .go();
      if (actualBarcodes != expectedBarcodes) {
        throw MergeIntegrityException(
          'food_barcodes: deleted $actualBarcodes, expected $expectedBarcodes',
        );
      }

      final foodDeleted = await (_liveDb.delete(_liveDb.foods)
            ..where((t) => t.id.equals(loserId)))
          .go();
      if (foodDeleted != 1) {
        throw MergeIntegrityException(
          'foods: deleted $foodDeleted, expected 1',
        );
      }

      return MergeResult(
        keeperId: keeperId,
        loserId: loserId,
        loggedRepointed: actualLogs,
        recipeRepointed: actualRecipe,
        parentChainsRepointed: actualParent,
        portionsDropped: actualPortions,
        barcodesDropped: actualBarcodes,
        sampleLoggedTimestamps: sampleTimestamps,
      );
    });

    final orphanLogs = (await (_liveDb.select(_liveDb.loggedPortions)
              ..where((t) => t.foodId.equals(loserId))
              ..limit(1))
            .get())
        .length;
    final orphanRecipe = (await (_liveDb.select(_liveDb.recipeItems)
              ..where((t) => t.ingredientFoodId.equals(loserId))
              ..limit(1))
            .get())
        .length;
    final orphanParent = (await (_liveDb.select(_liveDb.foods)
              ..where((t) => t.parentId.equals(loserId))
              ..limit(1))
            .get())
        .length;
    final orphanPortions = (await (_liveDb.select(_liveDb.foodPortions)
              ..where((t) => t.foodId.equals(loserId))
              ..limit(1))
            .get())
        .length;
    final orphanBarcodes = (await (_liveDb.select(_liveDb.foodBarcodes)
              ..where((t) => t.foodId.equals(loserId))
              ..limit(1))
            .get())
        .length;
    if (orphanLogs +
            orphanRecipe +
            orphanParent +
            orphanPortions +
            orphanBarcodes >
        0) {
      throw MergeIntegrityException(
        'orphan refs to loser $loserId remain after merge',
      );
    }

    BackupConfigService.instance.markDirty();
    return result;
  }
}
