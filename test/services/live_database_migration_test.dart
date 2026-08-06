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
