import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart' hide isNotNull;
import 'package:matcher/matcher.dart' as matcher;
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart' as ref;
import 'package:drift/native.dart';
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_serving.dart' as model_serving;
import 'package:meal_of_record/models/food_portion.dart' as model_portion;

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

  group('searchFoodsByName', () {
    test(
      'should return combined results from both live and reference databases',
      () async {
        // Arrange
        await liveDatabase
            .into(liveDatabase.foods)
            .insert(
              FoodsCompanion.insert(
                name: 'Live Apple',
                source: 'user_created',
                caloriesPerGram: 0.52,
                proteinPerGram: 0.003,
                fatPerGram: 0.002,
                carbsPerGram: 0.14,
                fiberPerGram: 0.024,
              ),
            );
        await referenceDatabase
            .into(referenceDatabase.foods)
            .insert(
              ref.FoodsCompanion.insert(
                name: 'Reference Apple',
                source: 'foundation',
                caloriesPerGram: 0.52,
                proteinPerGram: 0.003,
                fatPerGram: 0.002,
                carbsPerGram: 0.14,
                fiberPerGram: 0.024,
              ),
            );

        // Act
        final results = await databaseService.searchFoodsByName('Apple');

        // Assert
        expect(results, isA<List<model.Food>>());
        expect(results.length, 2);
        expect(results.any((f) => f.name == 'Live Apple'), isTrue);
        expect(results.any((f) => f.name == 'Reference Apple'), isTrue);
      },
    );

    test('should return empty list if no food is found', () async {
      // Act
      final results = await databaseService.searchFoodsByName(
        'NonExistentFood',
      );

      // Assert
      expect(results.isEmpty, isTrue);
    });

    test('should handle empty databases gracefully', () async {
      // Act
      final results = await databaseService.searchFoodsByName('Apple');

      // Assert
      expect(results.isEmpty, isTrue);
    });

    test('should return Food objects with populated units list', () async {
      // Arrange
      await referenceDatabase
          .into(referenceDatabase.foods)
          .insert(
            ref.FoodsCompanion.insert(
              id: Value(1), // Assign an ID for linking units
              name: 'Reference Apple',
              source: 'foundation',
              caloriesPerGram: 0.52,
              proteinPerGram: 0.003,
              fatPerGram: 0.002,
              carbsPerGram: 0.14,
              fiberPerGram: 0.024,
            ),
          );

      await referenceDatabase
          .into(referenceDatabase.foodPortions)
          .insert(
            ref.FoodPortionsCompanion.insert(
              foodId: 1,
              unit: '1 medium',
              grams: 182.0,
              quantity: 1.0,
            ),
          );
      await referenceDatabase
          .into(referenceDatabase.foodPortions)
          .insert(
            ref.FoodPortionsCompanion.insert(
              foodId: 1,
              unit: '1 cup sliced',
              grams: 109.0,
              quantity: 1.0,
            ),
          );

      // Act
      final results = await databaseService.searchFoodsByName('Apple');

      // Assert
      expect(results, isA<List<model.Food>>());
      expect(results.length, greaterThan(0));
      final appleFood = results.firstWhere((f) => f.name == 'Reference Apple');
      expect(appleFood.servings, matcher.isNotNull);
      expect(appleFood.servings.isNotEmpty, matcher.isTrue);
      // 'g' is auto-added, plus 2 inserted = 3
      expect(appleFood.servings.length, 3);
      expect(
        appleFood.servings.any(
          (unit) => unit.unit == '1 medium' && unit.grams == 182.0,
        ),
        matcher.isTrue,
      );
      // Verify 'g' unit is automatically added
      expect(
        appleFood.servings.any((unit) => unit.unit == 'g' && unit.grams == 1.0),
        matcher.isTrue,
      );
    });
  });

  group('getLastLoggedUnit', () {
    test('should return null if no logs exist for the food', () async {
      final unit = await databaseService.getLastLoggedUnit(1);
      expect(unit, matcher.isNull);
    });

    test('should return the unit from the most recent log', () async {
      // Arrange
      // Insert a food first to satisfy foreign key constraint
      const foodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId),
              name: 'Test Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );

      // Insert logs with different timestamps linking to this food
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(foodId),
              logTimestamp: 1000,
              grams: 100,
              unit: 'old_unit',
              quantity: 100,
            ),
          );
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(foodId),
              logTimestamp: 2000,
              grams: 100,
              unit: 'new_unit',
              quantity: 100,
            ),
          );

      // Act
      final unit = await databaseService.getLastLoggedUnit(foodId);

      // Assert
      expect(unit, 'new_unit');
    });
  });

  group('getLastLoggedInfo', () {
    test('should return null if no logs exist for the food', () async {
      final info = await databaseService.getLastLoggedInfo(1);
      expect(info, matcher.isNull);
    });

    test(
      'should return unit, quantity, and grams from the most recent log',
      () async {
        // Arrange
        const foodId = 1;
        await liveDatabase
            .into(liveDatabase.foods)
            .insert(
              FoodsCompanion.insert(
                id: const Value(foodId),
                name: 'Test Food',
                source: 'user_created',
                caloriesPerGram: 1.0,
                proteinPerGram: 0.0,
                fatPerGram: 0.0,
                carbsPerGram: 0.0,
                fiberPerGram: 0.0,
              ),
            );

        // Insert logs with different timestamps
        await liveDatabase
            .into(liveDatabase.loggedPortions)
            .insert(
              LoggedPortionsCompanion.insert(
                foodId: const Value(foodId),
                logTimestamp: 1000,
                grams: 100,
                unit: 'old_unit',
                quantity: 1.0,
              ),
            );
        await liveDatabase
            .into(liveDatabase.loggedPortions)
            .insert(
              LoggedPortionsCompanion.insert(
                foodId: const Value(foodId),
                logTimestamp: 2000,
                grams: 250,
                unit: 'slice',
                quantity: 2.5,
              ),
            );

        // Act
        final info = await databaseService.getLastLoggedInfo(foodId);

        // Assert
        expect(info, matcher.isNotNull);
        expect(info!.unit, 'slice');
        expect(info.quantity, 2.5);
        expect(info.grams, 250);
      },
    );

    test('should work via sourceFdcId for reference foods', () async {
      // Arrange
      // Create a reference food in the reference database
      const refFoodId = 100;
      await referenceDatabase
          .into(referenceDatabase.foods)
          .insert(
            ref.FoodsCompanion.insert(
              id: const Value(refFoodId),
              name: 'Reference Bread',
              source: 'FOUNDATION',
              caloriesPerGram: 2.5,
              proteinPerGram: 0.08,
              fatPerGram: 0.03,
              carbsPerGram: 0.50,
              fiberPerGram: 0.02,
            ),
          );

      // Create a live copy that points to the reference via sourceFdcId
      const liveFoodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(liveFoodId),
              name: 'Reference Bread',
              source: 'live',
              sourceFdcId: const Value(refFoodId),
              caloriesPerGram: 2.5,
              proteinPerGram: 0.08,
              fatPerGram: 0.03,
              carbsPerGram: 0.50,
              fiberPerGram: 0.02,
            ),
          );

      // Log the live copy
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(liveFoodId),
              logTimestamp: 3000,
              grams: 60,
              unit: 'slice',
              quantity: 2.0,
            ),
          );

      // Act - Query using the REFERENCE food ID
      final info = await databaseService.getLastLoggedInfo(refFoodId);

      // Assert - Should find the log via sourceFdcId
      expect(info, matcher.isNotNull);
      expect(info!.unit, 'slice');
      expect(info.quantity, 2.0);
      expect(info.grams, 60);
    });

    test('should return most recent when multiple logs exist', () async {
      // Arrange
      const foodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId),
              name: 'Test Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );

      // Insert multiple logs
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(foodId),
              logTimestamp: 1000,
              grams: 100,
              unit: 'g',
              quantity: 100,
            ),
          );
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(foodId),
              logTimestamp: 3000,
              grams: 150,
              unit: 'cup',
              quantity: 1.5,
            ),
          );
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(foodId),
              logTimestamp: 2000,
              grams: 200,
              unit: 'slice',
              quantity: 2.0,
            ),
          );

      // Act
      final info = await databaseService.getLastLoggedInfo(foodId);

      // Assert - Should return the log with timestamp 3000
      expect(info, matcher.isNotNull);
      expect(info!.unit, 'cup');
      expect(info.quantity, 1.5);
      expect(info.grams, 150);
    });
  });

  group('getLoggedMacrosForDateRange', () {
    test('should return macro DTOs for logs within range', () async {
      // Arrange
      const foodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId),
              name: 'Test Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.5,
              fatPerGram: 0.2,
              carbsPerGram: 0.3,
              fiberPerGram: 0.1,
            ),
          );

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      // Log for today
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(foodId),
              logTimestamp: todayStart
                  .add(const Duration(hours: 12))
                  .millisecondsSinceEpoch,
              grams: 100,
              unit: 'g',
              quantity: 100,
            ),
          );

      // Log for yesterday
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(foodId),
              logTimestamp: todayStart
                  .subtract(const Duration(hours: 12))
                  .millisecondsSinceEpoch,
              grams: 50,
              unit: 'g',
              quantity: 50,
            ),
          );

      // Log for tomorrow (out of range if we query today only)
      await liveDatabase
          .into(liveDatabase.loggedPortions)
          .insert(
            LoggedPortionsCompanion.insert(
              foodId: const Value(foodId),
              logTimestamp: todayStart
                  .add(const Duration(days: 1, hours: 12))
                  .millisecondsSinceEpoch,
              grams: 200,
              unit: 'g',
              quantity: 200,
            ),
          );

      // Act
      // Query for Today and Yesterday
      final results = await databaseService.getLoggedMacrosForDateRange(
        todayStart.subtract(const Duration(days: 1)),
        todayStart,
      );

      // Assert
      expect(results.length, 2);

      // Verify data integrity
      final todayLog = results.firstWhere((r) => r.grams == 100);
      expect(todayLog.caloriesPerGram, 1.0);

      final yesterdayLog = results.firstWhere((r) => r.grams == 50);
      expect(yesterdayLog.caloriesPerGram, 1.0);
    });
  });

  group('Smart Versioning', () {
    test('macro-neutral changes should update in-place', () async {
      // Arrange
      const foodId = 1;
      final food = model.Food(
        id: foodId,
        source: 'live',
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.024,
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(id: savedId);

      // Act: Update name and emoji (macro-neutral)
      final updatedFood = savedFood.copyWith(name: 'Red Apple', emoji: '🍎');
      final resultId = await databaseService.saveFood(updatedFood);

      // Assert
      expect(resultId, savedId); // Should be same ID
      final saved = await databaseService.getFoodById(savedId, 'live');
      expect(saved?.name, 'Red Apple');
      expect(saved?.emoji, '🍎');
    });

    test(
      'nutritional changes should update in-place if NOT referenced',
      () async {
        // Arrange
        const foodId = 1;
        final food = model.Food(
          id: foodId,
          source: 'live',
          name: 'Apple',
          calories: 0.52,
          protein: 0.003,
          fat: 0.002,
          carbs: 0.14,
          fiber: 0.024,
        );
        final savedId = await databaseService.saveFood(food);
        final savedFood = food.copyWith(id: savedId);

        // Act: Update calories (nutritional)
        final updatedFood = savedFood.copyWith(calories: 0.60);
        final resultId = await databaseService.saveFood(updatedFood);

        // Assert
        expect(resultId, savedId); // Still same ID because not referenced
        final saved = await databaseService.getFoodById(savedId, 'live');
        expect(saved?.calories, 0.60);
      },
    );

    test(
      'nutritional changes should create new version if referenced',
      () async {
        // Arrange
        const foodId = 1;
        final food = model.Food(
          id: foodId,
          source: 'live',
          name: 'Apple',
          calories: 0.52,
          protein: 0.003,
          fat: 0.002,
          carbs: 0.14,
          fiber: 0.024,
        );
        final savedId = await databaseService.saveFood(food);
        final savedFood = food.copyWith(id: savedId);

        // Reference it in a log
        await databaseService.logPortions([
          model_portion.FoodPortion(food: savedFood, grams: 100, unit: 'g'),
        ], DateTime.now());

        // Act: Update calories (nutritional)
        final updatedFood = savedFood.copyWith(calories: 0.60);
        final resultId = await databaseService.saveFood(updatedFood);

        // Assert
        expect(resultId, matcher.isNot(savedId)); // Should be a new ID
        final oldVersion = await databaseService.getFoodById(savedId, 'live');
        final newVersion = await databaseService.getFoodById(resultId, 'live');

        expect(oldVersion?.calories, 0.52); // Old version preserved
        expect(newVersion?.calories, 0.60); // New version created
        expect(newVersion?.parentId, savedId); // Lineage maintained
      },
    );
  });

  group('Barcode Management', () {
    test('should add barcode to food', () async {
      // Arrange
      const foodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId),
              name: 'Test Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );

      // Act
      final success = await databaseService.addBarcodeToFood(
        foodId,
        '1234567890',
      );

      // Assert
      expect(success, isTrue);
      final barcodes = await databaseService.getBarcodesByFoodId(foodId);
      expect(barcodes, contains('1234567890'));
    });

    test(
      'should return false when adding duplicate barcode to same food',
      () async {
        // Arrange
        const foodId = 1;
        await liveDatabase
            .into(liveDatabase.foods)
            .insert(
              FoodsCompanion.insert(
                id: const Value(foodId),
                name: 'Test Food',
                source: 'user_created',
                caloriesPerGram: 1.0,
                proteinPerGram: 0.0,
                fatPerGram: 0.0,
                carbsPerGram: 0.0,
                fiberPerGram: 0.0,
              ),
            );
        await databaseService.addBarcodeToFood(foodId, '1234567890');

        // Act
        final success = await databaseService.addBarcodeToFood(
          foodId,
          '1234567890',
        );

        // Assert
        expect(success, isFalse);
      },
    );

    test('should get all barcodes for a food', () async {
      // Arrange
      const foodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId),
              name: 'Test Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );
      await databaseService.addBarcodeToFood(foodId, '1111111111');
      await databaseService.addBarcodeToFood(foodId, '2222222222');
      await databaseService.addBarcodeToFood(foodId, '3333333333');

      // Act
      final barcodes = await databaseService.getBarcodesByFoodId(foodId);

      // Assert
      expect(barcodes.length, 3);
      expect(barcodes, containsAll(['1111111111', '2222222222', '3333333333']));
    });

    test('should return empty list for food with no barcodes', () async {
      // Arrange
      const foodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId),
              name: 'Test Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );

      // Act
      final barcodes = await databaseService.getBarcodesByFoodId(foodId);

      // Assert
      expect(barcodes, isEmpty);
    });

    test('should remove barcode from food', () async {
      // Arrange
      const foodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId),
              name: 'Test Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );
      await databaseService.addBarcodeToFood(foodId, '1234567890');
      await databaseService.addBarcodeToFood(foodId, '0987654321');

      // Act
      await databaseService.removeBarcodeFromFood(foodId, '1234567890');

      // Assert
      final barcodes = await databaseService.getBarcodesByFoodId(foodId);
      expect(barcodes.length, 1);
      expect(barcodes, contains('0987654321'));
      expect(barcodes, isNot(contains('1234567890')));
    });

    test('should find foods by barcode', () async {
      // Arrange
      const foodId1 = 1;
      const foodId2 = 2;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId1),
              name: 'Food One',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId2),
              name: 'Food Two',
              source: 'user_created',
              caloriesPerGram: 2.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );
      await databaseService.addBarcodeToFood(foodId1, '1234567890');
      await databaseService.addBarcodeToFood(foodId2, '0987654321');

      // Act
      final foods = await databaseService.getFoodsByBarcode('1234567890');

      // Assert
      expect(foods.length, 1);
      expect(foods.first.name, 'Food One');
    });

    test(
      'should return multiple foods if same barcode exists on multiple foods',
      () async {
        // Arrange
        const foodId1 = 1;
        const foodId2 = 2;
        await liveDatabase
            .into(liveDatabase.foods)
            .insert(
              FoodsCompanion.insert(
                id: const Value(foodId1),
                name: 'Food One',
                source: 'user_created',
                caloriesPerGram: 1.0,
                proteinPerGram: 0.0,
                fatPerGram: 0.0,
                carbsPerGram: 0.0,
                fiberPerGram: 0.0,
              ),
            );
        await liveDatabase
            .into(liveDatabase.foods)
            .insert(
              FoodsCompanion.insert(
                id: const Value(foodId2),
                name: 'Food Two',
                source: 'user_created',
                caloriesPerGram: 2.0,
                proteinPerGram: 0.0,
                fatPerGram: 0.0,
                carbsPerGram: 0.0,
                fiberPerGram: 0.0,
              ),
            );
        // Same barcode on both foods
        await databaseService.addBarcodeToFood(foodId1, '1234567890');
        await databaseService.addBarcodeToFood(foodId2, '1234567890');

        // Act
        final foods = await databaseService.getFoodsByBarcode('1234567890');

        // Assert
        expect(foods.length, 2);
        expect(foods.map((f) => f.name), containsAll(['Food One', 'Food Two']));
      },
    );

    test('should return empty list for unknown barcode', () async {
      // Act
      final foods = await databaseService.getFoodsByBarcode('unknown_barcode');

      // Assert
      expect(foods, isEmpty);
    });

    test('should detect if barcode exists on other food', () async {
      // Arrange
      const foodId1 = 1;
      const foodId2 = 2;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId1),
              name: 'Food One',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId2),
              name: 'Food Two',
              source: 'user_created',
              caloriesPerGram: 2.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );
      await databaseService.addBarcodeToFood(foodId1, '1234567890');

      // Act - Check if barcode exists on a food other than foodId2
      final otherFood = await databaseService.isBarcodeOnOtherFood(
        '1234567890',
        foodId2,
      );

      // Assert
      expect(otherFood, matcher.isNotNull);
      expect(otherFood!.name, 'Food One');
    });

    test('should return null if barcode only exists on same food', () async {
      // Arrange
      const foodId = 1;
      await liveDatabase
          .into(liveDatabase.foods)
          .insert(
            FoodsCompanion.insert(
              id: const Value(foodId),
              name: 'Test Food',
              source: 'user_created',
              caloriesPerGram: 1.0,
              proteinPerGram: 0.0,
              fatPerGram: 0.0,
              carbsPerGram: 0.0,
              fiberPerGram: 0.0,
            ),
          );
      await databaseService.addBarcodeToFood(foodId, '1234567890');

      // Act - Check if barcode exists on a food other than foodId (it doesn't)
      final otherFood = await databaseService.isBarcodeOnOtherFood(
        '1234567890',
        foodId,
      );

      // Assert
      expect(otherFood, matcher.isNull);
    });

    test('should return null if barcode does not exist anywhere', () async {
      // Act
      final otherFood = await databaseService.isBarcodeOnOtherFood(
        'nonexistent',
        1,
      );

      // Assert
      expect(otherFood, matcher.isNull);
    });
  });

  group('Unit-Based Quantity Persistence', () {
    test('should persist original unit and calculated quantity', () async {
      // Arrange
      const foodId = 1;
      final food = model.Food(
        id: foodId,
        source: 'live',
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.024,
        servings: [
          const model_serving.FoodServing(
            foodId: foodId,
            unit: '1 medium',
            grams: 182,
            quantity: 1.0,
          ),
        ],
      );
      final savedId = await databaseService.saveFood(food);
      final savedFood = food.copyWith(id: savedId);

      final portion = model_portion.FoodPortion(
        food: savedFood,
        grams: 91, // Half a medium apple
        unit: '1 medium',
      );

      // Act
      final now = DateTime.now();
      await databaseService.logPortions([portion], now);

      // Assert: Verify database row directly
      final row = await (liveDatabase.select(
        liveDatabase.loggedPortions,
      )).getSingle();
      expect(row.unit, '1 medium');
      expect(row.grams, 91.0);
      expect(row.quantity, 0.5); // 91 / 182

      // Assert: Verify retrieval via LoggedPortion model
      final logs = await databaseService.getLoggedPortionsForDate(now);
      expect(logs.first.portion.quantity, 0.5);
      expect(logs.first.portion.unit, '1 medium');
    });
  });
}
