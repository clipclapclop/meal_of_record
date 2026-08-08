import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart' hide isNotNull;
import 'package:matcher/matcher.dart' as matcher;
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart' as ref;
import 'package:meal_of_record/services/search_service.dart';
import 'package:meal_of_record/services/open_food_facts_service.dart';
import 'package:meal_of_record/services/food_sorting_service.dart';
import 'package:drift/native.dart';
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_portion.dart' as model_portion;

class FakeOffApiService extends OffApiService {
  @override
  Future<List<model.Food>> searchFoodsByName(String query) async => [];
  @override
  Future<model.Food?> fetchFoodByBarcode(String barcode) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  late DatabaseService databaseService;
  late LiveDatabase liveDatabase;
  late ref.ReferenceDatabase referenceDatabase;

  setUp(() {
    liveDatabase = LiveDatabase(connection: NativeDatabase.memory());
    referenceDatabase = ref.ReferenceDatabase(
      connection: NativeDatabase.memory(),
    );
    databaseService = DatabaseService.forTesting(
      liveDatabase,
      referenceDatabase,
    );
  });

  tearDown(() async {
    await liveDatabase.close();
    await referenceDatabase.close();
  });

  group('copyFoodToLiveDb source preservation', () {
    test('OFF food preserves source=off', () async {
      final offFood = model.Food(
        id: 1,
        source: 'off',
        name: 'Off Brand Cereal',
        calories: 3.5,
        protein: 0.1,
        fat: 0.05,
        carbs: 0.8,
        fiber: 0.03,
        sourceBarcode: '1234567890',
        database: model.FoodDatabase.off,
      );

      final liveCopy = await databaseService.copyFoodToLiveDb(offFood);

      expect(liveCopy.source, 'off');
      expect(liveCopy.database, model.FoodDatabase.live);
    });

    test('Reference food preserves source=FOUNDATION', () async {
      final refFood = model.Food(
        id: 100,
        source: 'FOUNDATION',
        name: 'Broccoli, raw',
        calories: 0.34,
        protein: 0.028,
        fat: 0.004,
        carbs: 0.066,
        fiber: 0.026,
        database: model.FoodDatabase.reference,
      );

      final liveCopy = await databaseService.copyFoodToLiveDb(refFood);

      expect(liveCopy.source, 'FOUNDATION');
      expect(liveCopy.sourceFdcId, 100);
    });

    test('Existing match reuses food', () async {
      final offFood = model.Food(
        id: 1,
        source: 'off',
        name: 'Same Food',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.5,
        fiber: 0.05,
        sourceBarcode: '111',
        database: model.FoodDatabase.off,
      );

      final first = await databaseService.copyFoodToLiveDb(offFood);
      final second = await databaseService.copyFoodToLiveDb(offFood);

      expect(first.id, second.id);

      // Verify only one row in live DB
      final allRows = await liveDatabase.select(liveDatabase.foods).get();
      expect(allRows.length, 1);
    });
  });

  group('saveFood ID collision fix', () {
    test('Reference food with id>0 does not collide with live food', () async {
      // Insert a live food that gets id=1
      final liveFood = model.Food(
        id: 0,
        source: 'user',
        name: 'My Custom Food',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.5,
        fiber: 0.05,
        database: model.FoodDatabase.live,
      );
      final liveId = await databaseService.saveFood(liveFood);
      expect(liveId, 1);

      // Now create a reference food with id=1 (same as the live food)
      final refFood = model.Food(
        id: 1,
        source: 'FOUNDATION',
        name: 'Reference Celery',
        calories: 0.14,
        protein: 0.007,
        fat: 0.002,
        carbs: 0.03,
        fiber: 0.016,
        database: model.FoodDatabase.reference,
      );
      final resultId = await databaseService.saveFood(refFood);

      // The reference food should get a NEW id, not overwrite the live food
      expect(resultId, isNot(equals(liveId)));

      // Verify the live food is still intact
      final originalLive = await databaseService.getFoodById(liveId, 'live');
      expect(originalLive, matcher.isNotNull);
      expect(originalLive!.name, 'My Custom Food');
    });

    test('Live food with id>0 updates existing', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Banana',
        calories: 0.89,
        protein: 0.011,
        fat: 0.003,
        carbs: 0.228,
        fiber: 0.026,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);

      // Update it
      final updated = food.copyWith(
        id: savedId,
        name: 'Banana (ripe)',
        database: model.FoodDatabase.live,
      );
      final updatedId = await databaseService.saveFood(updated);

      expect(updatedId, savedId);
      final fetched = await databaseService.getFoodById(savedId, 'live');
      expect(fetched!.name, 'Banana (ripe)');
    });
  });

  group('logPortions with database enum', () {
    test('Reference food gets copied to live before logging', () async {
      final refFood = model.Food(
        id: 42,
        source: 'FOUNDATION',
        name: 'Spinach, raw',
        calories: 0.23,
        protein: 0.029,
        fat: 0.004,
        carbs: 0.036,
        fiber: 0.022,
        database: model.FoodDatabase.reference,
      );

      await databaseService.logPortions([
        model_portion.FoodPortion(food: refFood, grams: 100, unit: 'g'),
      ], DateTime.now());

      // Verify a live copy exists with sourceFdcId = refFood.id
      final liveCopy = await databaseService.getFoodBySourceFdcId(42);
      expect(liveCopy, matcher.isNotNull);
      expect(liveCopy!.source, 'FOUNDATION');

      // Verify the log entry points to the live copy
      final logRow = await liveDatabase
          .select(liveDatabase.loggedPortions)
          .getSingle();
      expect(logRow.foodId, liveCopy.id);
    });

    test('Live food logs directly by ID', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Rice',
        calories: 1.3,
        protein: 0.027,
        fat: 0.003,
        carbs: 0.28,
        fiber: 0.004,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(
        id: savedId,
        database: model.FoodDatabase.live,
      );

      await databaseService.logPortions([
        model_portion.FoodPortion(food: savedFood, grams: 200, unit: 'g'),
      ], DateTime.now());

      final logRow = await liveDatabase
          .select(liveDatabase.loggedPortions)
          .getSingle();
      expect(logRow.foodId, savedId);
    });

    test('OFF food logs by barcode lookup', () async {
      final offFood = model.Food(
        id: 99,
        source: 'off',
        name: 'OFF Granola',
        calories: 4.5,
        protein: 0.08,
        fat: 0.18,
        carbs: 0.65,
        fiber: 0.06,
        sourceBarcode: '9876543210',
        database: model.FoodDatabase.off,
      );

      await databaseService.logPortions([
        model_portion.FoodPortion(food: offFood, grams: 50, unit: 'g'),
      ], DateTime.now());

      // Verify a live copy exists with the barcode
      final allFoods = await liveDatabase.select(liveDatabase.foods).get();
      final liveCopy = allFoods.firstWhere(
        (f) => f.sourceBarcode == '9876543210',
      );
      expect(liveCopy.source, 'off');

      final logRow = await liveDatabase
          .select(liveDatabase.loggedPortions)
          .getSingle();
      expect(logRow.foodId, liveCopy.id);
    });
  });

  group('searchLiveFoodsByName parentIds fix', () {
    test('Hidden child does not hide parent from search', () async {
      // Insert parent
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(1),
              name: 'Celery',
              source: 'user',
              caloriesPerGram: 0.14,
              proteinPerGram: 0.007,
              fatPerGram: 0.002,
              carbsPerGram: 0.03,
              fiberPerGram: 0.016,
            ),
          );

      // Insert hidden child pointing to parent
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(2),
              name: 'Celery',
              source: 'user',
              caloriesPerGram: 0.16,
              proteinPerGram: 0.008,
              fatPerGram: 0.002,
              carbsPerGram: 0.035,
              fiberPerGram: 0.018,
              parentId: const Value(1),
              hidden: const Value(true),
            ),
          );

      final results = await databaseService.searchLiveFoodsByName('Celery');

      // Parent should appear since child is hidden
      expect(results.any((f) => f.id == 1), isTrue);
    });

    test('Visible live child hides parent', () async {
      // Insert parent
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(1),
              name: 'Celery',
              source: 'user',
              caloriesPerGram: 0.14,
              proteinPerGram: 0.007,
              fatPerGram: 0.002,
              carbsPerGram: 0.03,
              fiberPerGram: 0.016,
            ),
          );

      // Insert visible child with source='live' (a real versioned update)
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(2),
              name: 'Celery',
              source: 'live',
              caloriesPerGram: 0.16,
              proteinPerGram: 0.008,
              fatPerGram: 0.002,
              carbsPerGram: 0.035,
              fiberPerGram: 0.018,
              parentId: const Value(1),
            ),
          );

      final results = await databaseService.searchLiveFoodsByName('Celery');

      // Only child should appear (parent hidden by live-source child)
      expect(results.length, 1);
      expect(results.first.id, 2);
    });

    test('Non-live child with parentId does not suppress parent', () async {
      // Insert "Strawberries" (id=1, source=FOUNDATION)
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(1),
              name: 'Strawberries',
              source: 'FOUNDATION',
              caloriesPerGram: 0.32,
              proteinPerGram: 0.007,
              fatPerGram: 0.003,
              carbsPerGram: 0.077,
              fiberPerGram: 0.02,
            ),
          );

      // Insert "Celery" (id=2, parentId=1, source=off) — coincidental
      // parentId collision from ID reuse across databases
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(2),
              name: 'Celery',
              source: 'off',
              caloriesPerGram: 0.14,
              proteinPerGram: 0.007,
              fatPerGram: 0.002,
              carbsPerGram: 0.03,
              fiberPerGram: 0.016,
              parentId: const Value(1),
            ),
          );

      // Strawberries should appear — Celery's parentId=1 doesn't count
      // because Celery's source is 'off', not 'live'
      final results = await databaseService.searchLiveFoodsByName(
        'Strawberries',
      );
      expect(results.length, 1);
      expect(results.first.name, 'Strawberries');
    });

    test('Live child with parentId does suppress parent', () async {
      // Insert parent "Apple" (id=1)
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(1),
              name: 'Apple',
              source: 'user',
              caloriesPerGram: 0.52,
              proteinPerGram: 0.003,
              fatPerGram: 0.002,
              carbsPerGram: 0.14,
              fiberPerGram: 0.024,
            ),
          );

      // Insert updated version "Apple" (id=2, parentId=1, source=live)
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(2),
              name: 'Apple',
              source: 'live',
              caloriesPerGram: 0.55,
              proteinPerGram: 0.003,
              fatPerGram: 0.002,
              carbsPerGram: 0.15,
              fiberPerGram: 0.024,
              parentId: const Value(1),
            ),
          );

      // Only the child should appear — it's source='live' with parentId=1
      final results = await databaseService.searchLiveFoodsByName('Apple');
      expect(results.length, 1);
      expect(results.first.id, 2);
    });
  });

  group('deleteFood / isFoodReferenced', () {
    test('Unreferenced food is hard-deleted', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Temp Food',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.5,
        fiber: 0.05,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);

      await databaseService.deleteFood(savedId);

      final fetched = await databaseService.getFoodById(savedId, 'live');
      expect(fetched, matcher.isNull);
    });

    test('Referenced food is soft-deleted', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Logged Food',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.5,
        fiber: 0.05,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(
        id: savedId,
        database: model.FoodDatabase.live,
      );

      // Log it to make it referenced
      await databaseService.logPortions([
        model_portion.FoodPortion(food: savedFood, grams: 100, unit: 'g'),
      ], DateTime.now());

      await databaseService.deleteFood(savedId);

      // Row should still exist but be hidden
      final row = await (liveDatabase.select(
        liveDatabase.foods,
      )..where((t) => t.id.equals(savedId))).getSingleOrNull();
      expect(row, matcher.isNotNull);
      expect(row!.hidden, isTrue);
    });

    test('isFoodReferenced true for logged food', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Logged Food',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.5,
        fiber: 0.05,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(
        id: savedId,
        database: model.FoodDatabase.live,
      );

      await databaseService.logPortions([
        model_portion.FoodPortion(food: savedFood, grams: 100, unit: 'g'),
      ], DateTime.now());

      final referenced = await databaseService.isFoodReferenced(savedId);
      expect(referenced, isTrue);
    });

    test('isFoodReferenced false for unlogged food', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Unlogged Food',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.5,
        fiber: 0.05,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);

      final referenced = await databaseService.isFoodReferenced(savedId);
      expect(referenced, isFalse);
    });
  });

  group('getFoodsUsageNotes', () {
    test('Logged food → Logged', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.024,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(
        id: savedId,
        database: model.FoodDatabase.live,
      );

      await databaseService.logPortions([
        model_portion.FoodPortion(food: savedFood, grams: 100, unit: 'g'),
      ], DateTime.now());

      final notes = await databaseService.getFoodsUsageNotes([savedFood]);
      expect(notes[savedId], 'Logged');
    });

    test('Food in recipe → In Recipe', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Flour',
        calories: 3.64,
        protein: 0.1,
        fat: 0.01,
        carbs: 0.76,
        fiber: 0.027,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(
        id: savedId,
        database: model.FoodDatabase.live,
      );

      // Create a recipe and add this food as ingredient
      final recipeId = await liveDatabase
          .into(liveDatabase.recipes)
          .insert(
            RecipesCompanion.insert(
              name: 'Test Recipe',
              createdTimestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      await liveDatabase
          .into(liveDatabase.recipeItems)
          .insert(
            RecipeItemsCompanion.insert(
              recipeId: recipeId,
              ingredientFoodId: Value(savedId),
              grams: 200,
              unit: 'g',
            ),
          );

      final notes = await databaseService.getFoodsUsageNotes([savedFood]);
      expect(notes[savedId], 'In Recipe');
    });

    test('Both logged and in recipe → Logged • In Recipe', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Butter',
        calories: 7.17,
        protein: 0.009,
        fat: 0.81,
        carbs: 0.001,
        fiber: 0.0,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(
        id: savedId,
        database: model.FoodDatabase.live,
      );

      // Log it
      await databaseService.logPortions([
        model_portion.FoodPortion(food: savedFood, grams: 14, unit: 'g'),
      ], DateTime.now());

      // Add to recipe
      final recipeId = await liveDatabase
          .into(liveDatabase.recipes)
          .insert(
            RecipesCompanion.insert(
              name: 'Pastry',
              createdTimestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      await liveDatabase
          .into(liveDatabase.recipeItems)
          .insert(
            RecipeItemsCompanion.insert(
              recipeId: recipeId,
              ingredientFoodId: Value(savedId),
              grams: 100,
              unit: 'g',
            ),
          );

      final notes = await databaseService.getFoodsUsageNotes([savedFood]);
      expect(notes[savedId], 'Logged • In Recipe');
    });

    test('Unused food → null', () async {
      final food = model.Food(
        id: 0,
        source: 'user',
        name: 'Unused Food',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.5,
        fiber: 0.05,
        database: model.FoodDatabase.live,
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(
        id: savedId,
        database: model.FoodDatabase.live,
      );

      final notes = await databaseService.getFoodsUsageNotes([savedFood]);
      expect(notes[savedId], matcher.isNull);
    });
  });

  group('SearchResults displayNotes preserve usageNote', () {
    test(
      'searchLocal returns displayNotes separately from food.usageNote',
      () async {
        // Create food with a user-entered usageNote
        await liveDatabase
            .into(liveDatabase.foods)
            .insert(
              FoodsCompanion.insert(
                id: const Value(1),
                name: 'Apple',
                source: 'user',
                caloriesPerGram: 0.52,
                proteinPerGram: 0.003,
                fatPerGram: 0.002,
                carbsPerGram: 0.14,
                fiberPerGram: 0.024,
                usageNote: const Value('My Note'),
              ),
            );

        // Log it so it gets a display note
        await liveDatabase
            .into(liveDatabase.loggedPortions)
            .insert(
              LoggedPortionsCompanion.insert(
                foodId: const Value(1),
                logTimestamp: DateTime.now().millisecondsSinceEpoch,
                grams: 100,
                unit: 'g',
                quantity: 100,
              ),
            );

        final searchService = SearchService(
          databaseService: databaseService,
          offApiService: FakeOffApiService(),
          emojiForFoodName: (name) => '🍎',
          sortingService: FoodSortingService(),
        );

        final results = await searchService.searchLocal('Apple');

        expect(results.foods.length, 1);
        // displayNotes should have the usage status
        expect(results.displayNotes[1], 'Logged');
        // food.usageNote should still be the user-entered value
        expect(results.foods.first.usageNote, 'My Note');
      },
    );
  });
}
