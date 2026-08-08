import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart' hide isNotNull;
import 'package:matcher/matcher.dart' as matcher;
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart' as ref;
import 'package:drift/native.dart';
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_portion.dart' as model_portion;
import 'package:meal_of_record/models/food_serving.dart' as model_serving;

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

  group('OpenFoodFacts Logging Issues', () {
    test('should log two different unedited OFF foods correctly', () async {
      // Arrange
      // Simulating two different foods coming from OFF
      // Note: id=0 and source='off' is standard for OFF results
      final offFoodA = model.Food(
        id: 0,
        source: 'off',
        name: 'OFF Food A',
        sourceBarcode: '111',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.1,
        fiber: 0.0,
        database: model.FoodDatabase.off,
        servings: [
          const model_serving.FoodServing(
            foodId: 0,
            unit: 'g',
            grams: 1.0,
            quantity: 1.0,
          ),
        ],
      );

      final offFoodB = model.Food(
        id: 0,
        source: 'off',
        name: 'OFF Food B',
        sourceBarcode: '222',
        calories: 2.0,
        protein: 0.2,
        fat: 0.2,
        carbs: 0.2,
        fiber: 0.0,
        database: model.FoodDatabase.off,
        servings: [
          const model_serving.FoodServing(
            foodId: 0,
            unit: 'g',
            grams: 1.0,
            quantity: 1.0,
          ),
        ],
      );

      // Act
      // Log Food A
      await databaseService.logPortions([
        model_portion.FoodPortion(food: offFoodA, grams: 100, unit: 'g'),
      ], DateTime.now());

      // Log Food B
      // This is expected to FAIL or produce INCORRECT results if the bug exists
      await databaseService.logPortions([
        model_portion.FoodPortion(food: offFoodB, grams: 100, unit: 'g'),
      ], DateTime.now());

      // Assert
      final logs = await databaseService.getLoggedPortionsForDate(
        DateTime.now(),
      );
      expect(logs.length, 2, reason: 'Should have 2 logged items');

      final logA = logs.firstWhere((l) => l.portion.food.name == 'OFF Food A');
      final logB = logs.firstWhere((l) => l.portion.food.name == 'OFF Food B');

      expect(logA, matcher.isNotNull);
      expect(logB, matcher.isNotNull);

      // Verify they point to different foods in the DB
      expect(
        logA.portion.food.id,
        isNot(equals(logB.portion.food.id)),
        reason: 'Foods should have different IDs',
      );

      // Verify barcodes are saved
      final savedFoodA = await databaseService.getFoodById(
        logA.portion.food.id,
        'live',
      );
      final savedFoodB = await databaseService.getFoodById(
        logB.portion.food.id,
        'live',
      );

      expect(savedFoodA?.sourceBarcode, '111');
      expect(savedFoodB?.sourceBarcode, '222');
    });

    test('should reuse existing live food for same OFF barcode', () async {
      // Arrange
      final offFoodA = model.Food(
        id: 0,
        source: 'off',
        name: 'OFF Food A',
        sourceBarcode: '111',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.1,
        fiber: 0.0,
        database: model.FoodDatabase.off,
        servings: [
          const model_serving.FoodServing(
            foodId: 0,
            unit: 'g',
            grams: 1.0,
            quantity: 1.0,
          ),
        ],
      );

      // Wrapper object but same barcode (simulating re-scan)
      final offFoodARescan = model.Food(
        id: 0,
        source: 'off',
        name: 'OFF Food A', // Same name
        sourceBarcode: '111', // Same barcode
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.1,
        fiber: 0.0,
        database: model.FoodDatabase.off,
        servings: [
          const model_serving.FoodServing(
            foodId: 0,
            unit: 'g',
            grams: 1.0,
            quantity: 1.0,
          ),
        ],
      );

      // Act
      await databaseService.logPortions([
        model_portion.FoodPortion(food: offFoodA, grams: 100, unit: 'g'),
      ], DateTime.now());

      await databaseService.logPortions([
        model_portion.FoodPortion(food: offFoodARescan, grams: 100, unit: 'g'),
      ], DateTime.now());

      // Assert
      final logs = await databaseService.getLoggedPortionsForDate(
        DateTime.now(),
      );
      expect(logs.length, 2);

      final id1 = logs[0].portion.food.id;
      final id2 = logs[1].portion.food.id;

      expect(id1, equals(id2), reason: 'Should point to same Food ID');

      // Check that we didn't create duplicate foods in the DB
      final allFoods = await liveDatabase.select(liveDatabase.foods).get();
      expect(allFoods.length, 1);
    });
  });
}
