import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart' as ref;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDirectory;
  late File liveFile;
  late Directory imagesDirectory;
  late LiveDatabase liveDatabase;
  late ref.ReferenceDatabase referenceDatabase;
  late DatabaseService databaseService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'goal_settings': jsonEncode(_goalSettings),
      'macro_targets': jsonEncode(_macroTargets),
      'target_snapshots': jsonEncode(_targetSnapshots),
      'has_seen_welcome': true,
      'share_include_images': false,
      'backup_auto_enabled': true,
      'nas_host': 'nas.example.test',
    });

    tempDirectory = await Directory.systemTemp.createTemp(
      'meal_of_record_backup_test_',
    );
    liveFile = File('${tempDirectory.path}/live.db');
    imagesDirectory = Directory('${tempDirectory.path}/app_images');
    await imagesDirectory.create();
    await _createDatabaseFromFixture(
      liveFile,
      File('test/fixtures/live_schema_v13.sql'),
    );

    liveDatabase = LiveDatabase(connection: NativeDatabase(liveFile));
    await liveDatabase.customSelect('SELECT 1').getSingle();
    await liveDatabase.customStatement(
      "UPDATE recipes SET link = 'https://example.test/oat-bowl' WHERE id = 10",
    );
    referenceDatabase = ref.ReferenceDatabase(
      connection: NativeDatabase.memory(),
    );
    databaseService = DatabaseService.forTesting(
      liveDatabase,
      referenceDatabase,
      liveDbFile: liveFile,
      imagesDirectory: imagesDirectory,
    );

    for (final image in <String>[
      'food-image.jpg',
      'food-image-current.jpg',
      'recipe-image.jpg',
      'container-image.jpg',
      'unreferenced-but-owned.jpg',
    ]) {
      await File(
        '${imagesDirectory.path}/$image',
      ).writeAsString('bytes:$image');
    }
  });

  tearDown(() async {
    await databaseService.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'backup and restore round trip preserves all persisted relationships',
    () async {
      final backup = await databaseService.exportBackupAsZip();
      addTearDown(() async {
        if (await backup.parent.exists()) {
          await backup.parent.delete(recursive: true);
        }
      });

      final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
      final manifest = _jsonEntry(archive, 'manifest.json');
      expect(manifest['formatVersion'], DatabaseService.backupFormatVersion);
      expect(
        manifest['databaseSchemaVersion'],
        LiveDatabase.currentSchemaVersion,
      );

      await liveDatabase.customStatement('DELETE FROM logged_portions');
      await liveDatabase.customStatement('DELETE FROM recipe_items');
      await liveDatabase.customStatement('DELETE FROM recipe_category_links');
      await liveDatabase.customStatement('DELETE FROM food_barcodes');
      await liveDatabase.customStatement('DELETE FROM food_portions');
      await liveDatabase.customStatement('DELETE FROM weights');
      await liveDatabase.customStatement('DELETE FROM containers');
      await liveDatabase.customStatement('DELETE FROM categories');
      await liveDatabase.customStatement('DELETE FROM recipes');
      await liveDatabase.customStatement('DELETE FROM foods');
      await imagesDirectory.delete(recursive: true);
      await imagesDirectory.create();
      await File('${imagesDirectory.path}/stale.jpg').writeAsString('stale');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('goal_settings', '{"changed":true}');
      await prefs.remove('target_snapshots');
      await prefs.setBool('has_seen_welcome', false);
      await prefs.setBool('share_include_images', true);

      await databaseService.restoreDatabase(backup);

      final restored = LiveDatabase(connection: NativeDatabase(liveFile));
      addTearDown(restored.close);
      expect(await _count(restored, 'foods'), 3); // fixture + system Quick Add
      expect(await _count(restored, 'food_portions'), 3);
      expect(await _count(restored, 'recipes'), 2);
      expect(await _count(restored, 'recipe_items'), 2);
      expect(await _count(restored, 'categories'), 1);
      expect(await _count(restored, 'recipe_category_links'), 1);
      expect(await _count(restored, 'logged_portions'), 2);
      expect(await _count(restored, 'weights'), 1);
      expect(await _count(restored, 'containers'), 1);
      expect(await _count(restored, 'food_barcodes'), 1);

      final historical = await restored.customSelect('''
        SELECT f.name, f.thumbnail, f.caloriesPerGram, f.proteinPerGram, lp.grams
        FROM logged_portions lp
        JOIN foods f ON f.id = lp.loggedFoodId
        WHERE lp.id = 40
      ''').getSingle();
      expect(historical.data['name'], 'Historical oats');
      expect(historical.data['thumbnail'], 'local:food-image');
      expect(historical.data['caloriesPerGram'], 3.8);
      expect(historical.data['proteinPerGram'], 0.13);
      expect(historical.data['grams'], 80.0);

      final relationship = await restored.customSelect('''
        SELECT ri.recipe_id, ri.ingredient_recipe_id, rcl.category_id,
               r.thumbnail AS recipe_thumbnail, r.link,
               f.parentId AS food_parent,
               c.thumbnail AS container_thumbnail
        FROM recipe_items ri
        JOIN recipe_category_links rcl
          ON rcl.recipe_id = ri.ingredient_recipe_id
        JOIN recipes r ON r.id = ri.ingredient_recipe_id
        JOIN foods f ON f.id = 2
        JOIN containers c ON c.id = 60
        WHERE ri.id = 31
      ''').getSingle();
      expect(relationship.data['recipe_id'], 11);
      expect(relationship.data['ingredient_recipe_id'], 10);
      expect(relationship.data['category_id'], 20);
      expect(relationship.data['recipe_thumbnail'], 'local:recipe-image');
      expect(relationship.data['link'], 'https://example.test/oat-bowl');
      expect(relationship.data['food_parent'], 1);
      expect(relationship.data['container_thumbnail'], 'local:container-image');

      final restoredImages = await imagesDirectory
          .list()
          .where((entity) => entity is File)
          .map((entity) => entity.path.split(Platform.pathSeparator).last)
          .toList();
      expect(
        restoredImages,
        unorderedEquals(<String>[
          'food-image.jpg',
          'food-image-current.jpg',
          'recipe-image.jpg',
          'container-image.jpg',
          'unreferenced-but-owned.jpg',
        ]),
      );
      expect(await File('${imagesDirectory.path}/stale.jpg').exists(), isFalse);

      expect(jsonDecode(prefs.getString('goal_settings')!), _goalSettings);
      expect(jsonDecode(prefs.getString('macro_targets')!), _macroTargets);
      expect(
        jsonDecode(prefs.getString('target_snapshots')!),
        _targetSnapshots,
      );
      expect(prefs.getBool('has_seen_welcome'), isTrue);
      expect(prefs.getBool('share_include_images'), isFalse);

      // Backup transport configuration is device-specific and must not move.
      expect(prefs.getBool('backup_auto_enabled'), isTrue);
      expect(prefs.getString('nas_host'), 'nas.example.test');
    },
  );

  test(
    'restores the legacy v1 zip format when its schema is supported',
    () async {
      final currentBackup = await databaseService.exportBackupAsZip();
      addTearDown(() async {
        if (await currentBackup.parent.exists()) {
          await currentBackup.parent.delete(recursive: true);
        }
      });
      final currentArchive = ZipDecoder().decodeBytes(
        await currentBackup.readAsBytes(),
      );
      final databaseBytes =
          currentArchive.files
                  .singleWhere((entry) => entry.name == 'meal_of_record.db')
                  .content
              as List<int>;
      final legacy = await _writeArchive(
        File('${tempDirectory.path}/legacy-v1.zip'),
        <String, List<int>>{
          'meal_of_record.db': databaseBytes,
          'settings.json': utf8.encode(
            jsonEncode({
              'version': 1,
              'goal_settings': _goalSettings,
              'macro_targets': _macroTargets,
            }),
          ),
        },
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('goal_settings', '{"changed":true}');
      await databaseService.restoreDatabase(legacy);

      expect(jsonDecode(prefs.getString('goal_settings')!), _goalSettings);
      expect(jsonDecode(prefs.getString('macro_targets')!), _macroTargets);
      expect(prefs.containsKey('target_snapshots'), isFalse);
    },
  );

  group('safe restore failure', () {
    test('rejects an interrupted zip without changing current data', () async {
      final backup = await databaseService.exportBackupAsZip();
      addTearDown(() async {
        if (await backup.parent.exists()) {
          await backup.parent.delete(recursive: true);
        }
      });
      final bytes = await backup.readAsBytes();
      final interrupted = File('${tempDirectory.path}/interrupted.zip');
      await interrupted.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));

      await _expectSafeFailure(databaseService, interrupted, liveFile);
    });

    test('rejects malformed input without changing current data', () async {
      final malformed = File('${tempDirectory.path}/malformed.zip');
      await malformed.writeAsString('this is not a zip archive');

      await _expectSafeFailure(databaseService, malformed, liveFile);
    });

    test('rejects an incomplete backup without a database', () async {
      final incomplete = await _writeArchive(
        File('${tempDirectory.path}/incomplete.zip'),
        <String, List<int>>{
          'settings.json': utf8.encode(jsonEncode({'version': 1})),
        },
      );

      await _expectSafeFailure(databaseService, incomplete, liveFile);
    });

    test('rejects a zip backup without portable settings', () async {
      final missingSettings = await _writeArchive(
        File('${tempDirectory.path}/missing-settings.zip'),
        <String, List<int>>{'meal_of_record.db': await liveFile.readAsBytes()},
      );

      await _expectSafeFailure(databaseService, missingSettings, liveFile);
    });

    test('rejects malformed settings before replacing data', () async {
      final malformedSettings = await _writeArchive(
        File('${tempDirectory.path}/malformed-settings.zip'),
        <String, List<int>>{
          'meal_of_record.db': await liveFile.readAsBytes(),
          'settings.json': utf8.encode('{not-json'),
        },
      );

      await _expectSafeFailure(databaseService, malformedSettings, liveFile);
    });

    test(
      'rejects an archive whose declared expanded size is too large',
      () async {
        final archive = Archive()
          ..addFile(
            ArchiveFile(
              'meal_of_record.db',
              512 * 1024 * 1024 + 1,
              const <int>[],
            ),
          );
        final oversized = File('${tempDirectory.path}/oversized.zip');
        await oversized.writeAsBytes(ZipEncoder().encode(archive)!);

        await _expectSafeFailure(databaseService, oversized, liveFile);
      },
    );

    test('rejects an incompatible future backup format', () async {
      final incompatible = await _writeArchive(
        File('${tempDirectory.path}/future-format.zip'),
        <String, List<int>>{
          'manifest.json': utf8.encode(
            jsonEncode({
              'formatVersion': DatabaseService.backupFormatVersion + 1,
              'databaseSchemaVersion': LiveDatabase.currentSchemaVersion,
            }),
          ),
          'meal_of_record.db': await liveFile.readAsBytes(),
        },
      );

      await _expectSafeFailure(databaseService, incompatible, liveFile);
    });

    test('rejects an unreleased legacy schema', () async {
      final legacyDb = File('${tempDirectory.path}/legacy.db');
      final rawDatabase = sqlite.sqlite3.open(legacyDb.path);
      rawDatabase.execute(
        'PRAGMA user_version = ${LiveDatabase.minimumSupportedSchemaVersion - 1}',
      );
      rawDatabase.dispose();

      await _expectSafeFailure(databaseService, legacyDb, liveFile);
    });

    test('rejects a database from a future schema', () async {
      final futureDb = File('${tempDirectory.path}/future.db');
      final rawDatabase = sqlite.sqlite3.open(futureDb.path);
      rawDatabase.execute(
        'PRAGMA user_version = ${LiveDatabase.currentSchemaVersion + 1}',
      );
      rawDatabase.dispose();
      final incompatible = await _writeArchive(
        File('${tempDirectory.path}/future-schema.zip'),
        <String, List<int>>{
          'manifest.json': utf8.encode(
            jsonEncode({
              'formatVersion': DatabaseService.backupFormatVersion,
              'databaseSchemaVersion': LiveDatabase.currentSchemaVersion + 1,
            }),
          ),
          'meal_of_record.db': await futureDb.readAsBytes(),
          'settings.json': utf8.encode(jsonEncode({'version': 1})),
        },
      );

      await _expectSafeFailure(databaseService, incompatible, liveFile);
    });

    test('rejects archive paths that escape the image directory', () async {
      final unsafe = await _writeArchive(
        File('${tempDirectory.path}/unsafe.zip'),
        <String, List<int>>{
          'meal_of_record.db': await liveFile.readAsBytes(),
          'settings.json': utf8.encode(jsonEncode({'version': 1})),
          'app_images/../outside.jpg': utf8.encode('unsafe'),
        },
      );

      await _expectSafeFailure(databaseService, unsafe, liveFile);
      expect(await File('${tempDirectory.path}/outside.jpg').exists(), isFalse);
    });
  });
}

Future<void> _expectSafeFailure(
  DatabaseService service,
  File backup,
  File liveFile,
) async {
  final before = await liveFile.readAsBytes();
  final prefs = await SharedPreferences.getInstance();
  final settingsBefore = prefs.getString('goal_settings');

  await expectLater(
    service.restoreDatabase(backup),
    throwsA(isA<BackupRestoreException>()),
  );

  expect(await liveFile.readAsBytes(), before);
  expect(prefs.getString('goal_settings'), settingsBefore);
  final current = LiveDatabase(connection: NativeDatabase(liveFile));
  try {
    expect(await _count(current, 'logged_portions'), 2);
  } finally {
    await current.close();
  }
}

Map<String, dynamic> _jsonEntry(Archive archive, String name) {
  final entry = archive.files.singleWhere((file) => file.name == name);
  return jsonDecode(utf8.decode(entry.content as List<int>))
      as Map<String, dynamic>;
}

Future<File> _writeArchive(File target, Map<String, List<int>> entries) {
  return _writeArchiveEntries(target, entries.entries.toList());
}

Future<File> _writeArchiveEntries(
  File target,
  List<MapEntry<String, List<int>>> entries,
) async {
  final archive = Archive();
  for (final entry in entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final bytes = ZipEncoder().encode(archive)!;
  await target.writeAsBytes(bytes);
  return target;
}

Future<int> _count(LiveDatabase database, String table) async {
  final row = await database
      .customSelect('SELECT COUNT(*) AS count FROM $table')
      .getSingle();
  return row.data['count']! as int;
}

Future<void> _createDatabaseFromFixture(File target, File fixture) async {
  final database = sqlite.sqlite3.open(target.path);
  try {
    final sql = await fixture.readAsString();
    database.execute(sql);
  } finally {
    database.dispose();
  }
}

const _goalSettings = <String, dynamic>{
  'anchorWeight': 81.25,
  'maintenanceCaloriesStart': 2400.0,
  'proteinTarget': 160.0,
  'fatTarget': 80.0,
  'carbTarget': 220.0,
  'fiberTarget': 30.0,
  'mode': 'GoalMode.maintain',
  'calculationMode': 'MacroCalculationMode.proteinCarbs',
  'proteinTargetMode': 'ProteinTargetMode.fixed',
  'proteinMultiplier': 1.0,
  'fixedDelta': 0.0,
  'lastTargetUpdate': 1735862400000,
  'isSet': true,
  'enableSmartTargets': true,
  'correctionWindowDays': 30,
  'tdeeWindowDays': 28,
  'useNetCarbs': true,
};

const _macroTargets = <String, dynamic>{
  'calories': 2400.0,
  'protein': 160.0,
  'fat': 80.0,
  'carbs': 220.0,
  'fiber': 30.0,
};

const _targetSnapshots = <Map<String, dynamic>>[
  <String, dynamic>{
    'date': '2025-01-03',
    'calories': 2300.0,
    'protein': 155.0,
    'fat': 75.0,
    'carbs': 215.0,
    'fiber': 30.0,
  },
  <String, dynamic>{
    'date': '2025-01-04',
    'calories': 2400.0,
    'protein': 160.0,
    'fat': 80.0,
    'carbs': 220.0,
    'fiber': 30.0,
  },
];
