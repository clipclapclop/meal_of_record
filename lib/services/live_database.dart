import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:meal_of_record/data/database/tables.dart';

part 'live_database.g.dart';

@DriftDatabase(
  tables: [
    Foods,
    FoodPortions,
    Recipes,
    RecipeItems,
    Categories,
    RecipeCategoryLinks,
    LoggedPortions,
    Weights,
    Containers,
    FoodBarcodes,
  ],
)
class LiveDatabase extends _$LiveDatabase {
  static const int currentSchemaVersion = 14;

  // v13 is the oldest schema shipped in a tagged production release. Earlier
  // development schemas were never released and don't have a safe, complete
  // migration path.
  static const int minimumSupportedSchemaVersion = 13;

  LiveDatabase({required QueryExecutor connection}) : super(connection);

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          // Add parentId to Foods
          // ...
          await m.addColumn(foods, foods.parentId);
          // Create new tables
          await m.createTable(recipes);
          await m.createTable(recipeItems);
          await m.createTable(categories);
          await m.createTable(recipeCategoryLinks);
        }
        // ... (existing migrations)
        if (from < 4) {
          await customStatement('DROP TABLE IF EXISTS logged_foods');
          await customStatement('DROP TABLE IF EXISTS logged_food_servings');
          await customStatement('DROP TABLE IF EXISTS logged_portions');
          await m.createTable(loggedPortions);
        }
        if (from < 5) {
          await m.addColumn(foods, foods.usageNote);
        }
        if (from < 6) {
          await m.createTable(weights);
        }
        // v7 and v8 skipped/handled
        if (from < 9) {
          await m.createTable(containers);
        }
        if (from < 10) {
          await m.addColumn(recipes, recipes.emoji);
          await m.addColumn(recipes, recipes.thumbnail);
        }
        if (from < 11) {
          await m.addColumn(recipeItems, recipeItems.position);
          // Backfill: assign position based on existing ID order per recipe
          await customStatement('''
            UPDATE recipe_items
            SET position = (
              SELECT COUNT(*)
              FROM recipe_items AS ri
              WHERE ri.recipe_id = recipe_items.recipe_id
              AND ri.id < recipe_items.id
            )
          ''');
        }
        if (from < 12) {
          await m.createTable(foodBarcodes);
        }
        if (from < 13) {
          // Fix source provenance: foods incorrectly set to 'live' should
          // reflect their original data source.
          // 1. Foods with sourceFdcId: look up reference DB source
          //    (handled via raw SQL join against reference DB - not possible
          //     cross-database, so we use heuristics)
          // 2. Foods with sourceBarcode and no sourceFdcId -> 'off'
          await customStatement('''
            UPDATE foods SET source = 'off'
            WHERE source = 'live'
              AND sourceBarcode IS NOT NULL
              AND sourceFdcId IS NULL
              AND parentId IS NULL
          ''');
          // 3. Foods with sourceFdcId: these came from USDA reference DB.
          //    We can't easily determine FOUNDATION vs SR_LEGACY without
          //    querying the reference DB, so mark as 'FOUNDATION' (the more
          //    common/better source). This is a best-effort heuristic.
          await customStatement('''
            UPDATE foods SET source = 'FOUNDATION'
            WHERE source = 'live'
              AND sourceFdcId IS NOT NULL
              AND parentId IS NULL
          ''');
          // 4. Remaining 'live' foods with no sourceFdcId, no sourceBarcode,
          //    no parentId -> 'user' (user-created)
          //    (Exclude system foods which already have source='system')
          await customStatement('''
            UPDATE foods SET source = 'user'
            WHERE source = 'live'
              AND sourceFdcId IS NULL
              AND sourceBarcode IS NULL
              AND parentId IS NULL
              AND name != 'Fasted'
              AND name != 'Quick Add'
          ''');
          // 5. Fix corrupt parentId: clear parentId on any food where
          //    the parent doesn't actually exist or is from a different
          //    source lineage (the Strawberries/Celery ID collision bug)
          await customStatement('''
            UPDATE foods SET parentId = NULL
            WHERE parentId IS NOT NULL
              AND parentId NOT IN (SELECT id FROM foods)
          ''');
        }

        if (from < 14) {
          await m.addColumn(recipes, recipes.link);
        }
      },
      beforeOpen: (details) async {
        if (details.wasCreated) {
          // Initialize categories or other data if needed
        }
        // Enable foreign_keys is usually default or handled by Drift,
        // but ensuring it is good practice if using raw SQL.
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}

Future<File> getLiveDbFile() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return File(p.join(dbFolder.path, 'live.db'));
}

QueryExecutor openLiveConnection() {
  return LazyDatabase(() async {
    return NativeDatabase(await getLiveDbFile());
  });
}
