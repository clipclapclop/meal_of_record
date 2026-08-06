import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late File databaseFile;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'meal_of_record_migration_test_',
    );
    databaseFile = File('${tempDirectory.path}/live.db');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'migrates v12 provenance fixups without corrupting parent links',
    () async {
      await _createDatabaseFromFixture(
        databaseFile,
        File('test/fixtures/live_schema_v13.sql'),
      );
      final fixture = sqlite.sqlite3.open(databaseFile.path);
      try {
        fixture.execute('PRAGMA foreign_keys = OFF');
        fixture.execute('''
        INSERT INTO foods (
          id, name, source, caloriesPerGram, proteinPerGram, fatPerGram,
          carbsPerGram, fiberPerGram, sourceFdcId, sourceBarcode, hidden,
          parentId
        ) VALUES
          (100, 'Barcode food', 'live', 1, 0, 0, 0, 0, NULL, '12345', 0, NULL),
          (101, 'USDA food', 'live', 1, 0, 0, 0, 0, 9001, NULL, 0, NULL),
          (102, 'Custom food', 'live', 1, 0, 0, 0, 0, NULL, NULL, 0, NULL),
          (103, 'Fasted', 'live', 0, 0, 0, 0, 0, NULL, NULL, 1, NULL),
          (104, 'Valid child', 'live', 1, 0, 0, 0, 0, NULL, NULL, 0, 102),
          (105, 'Orphan child', 'live', 1, 0, 0, 0, 0, NULL, NULL, 0, 999)
      ''');
        fixture.execute('PRAGMA user_version = 12');
      } finally {
        fixture.dispose();
      }

      final database = LiveDatabase(connection: NativeDatabase(databaseFile));
      addTearDown(database.close);
      await database.customSelect('SELECT 1').getSingle();

      final rows = await database.customSelect('''
      SELECT id, source, parentId FROM foods WHERE id >= 100 ORDER BY id
    ''').get();
      final byId = {for (final row in rows) row.data['id']: row.data};
      expect(byId[100]!['source'], 'off');
      expect(byId[101]!['source'], 'FOUNDATION');
      expect(byId[102]!['source'], 'user');
      expect(byId[103]!['source'], 'live');
      expect(byId[104]!['parentId'], 102);
      expect(byId[105]!['parentId'], isNull);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'migrates the production v13 fixture to v14 without data loss',
    () async {
      await _createDatabaseFromFixture(
        databaseFile,
        File('test/fixtures/live_schema_v13.sql'),
      );

      final database = LiveDatabase(connection: NativeDatabase(databaseFile));
      addTearDown(database.close);

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data['user_version'], LiveDatabase.currentSchemaVersion);

      final recipeColumns = await database
          .customSelect('PRAGMA table_info(recipes)')
          .get();
      expect(recipeColumns.map((row) => row.data['name']), contains('link'));

      expect(await _count(database, 'foods'), 2);
      expect(await _count(database, 'food_portions'), 2);
      expect(await _count(database, 'recipes'), 2);
      expect(await _count(database, 'recipe_items'), 2);
      expect(await _count(database, 'categories'), 1);
      expect(await _count(database, 'recipe_category_links'), 1);
      expect(await _count(database, 'logged_portions'), 2);
      expect(await _count(database, 'weights'), 1);
      expect(await _count(database, 'containers'), 1);
      expect(await _count(database, 'food_barcodes'), 1);

      final historicalLog = await database.customSelect('''
      SELECT lp.grams, lp.unit, lp.quantity, f.name,
             f.caloriesPerGram, f.proteinPerGram, f.parentId
      FROM logged_portions lp
      JOIN foods f ON f.id = lp.loggedFoodId
      WHERE lp.id = 40
    ''').getSingle();
      expect(historicalLog.data, containsPair('name', 'Historical oats'));
      expect(historicalLog.data, containsPair('caloriesPerGram', 3.8));
      expect(historicalLog.data, containsPair('proteinPerGram', 0.13));
      expect(historicalLog.data, containsPair('grams', 80.0));
      expect(historicalLog.data, containsPair('unit', 'bowl'));
      expect(historicalLog.data, containsPair('quantity', 1.0));
      expect(historicalLog.data['parentId'], isNull);

      final recipeRelationship = await database.customSelect('''
      SELECT ri.ingredient_recipe_id, r.name, c.name AS category
      FROM recipe_items ri
      JOIN recipes r ON r.id = ri.ingredient_recipe_id
      JOIN recipe_category_links rcl ON rcl.recipe_id = r.id
      JOIN categories c ON c.id = rcl.category_id
      WHERE ri.id = 31
    ''').getSingle();
      expect(recipeRelationship.data['ingredient_recipe_id'], 10);
      expect(recipeRelationship.data['name'], 'Oat bowl');
      expect(recipeRelationship.data['category'], 'Breakfast');

      final integrity = await database
          .customSelect('PRAGMA quick_check')
          .getSingle();
      expect(integrity.data.values.single, 'ok');
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
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
