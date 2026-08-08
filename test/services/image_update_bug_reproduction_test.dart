import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_portion.dart' as model_portion;
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart' as ref;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test(
    'Food image update should be isolated to the edited version (REPRODUCTION)',
    () async {
      // 1. Create a food
      final initialFood = model.Food(
        id: 0,
        source: 'live',
        name: 'Test Food',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.1,
        fiber: 0.05,
        thumbnail: 'initial_image.png',
      );
      final foodIdV1 = await databaseService.saveFood(initialFood);
      final foodV1 = initialFood.copyWith(id: foodIdV1);

      // 2. Log it (makes it "referenced")
      final logDate = DateTime.now();
      await databaseService.logPortions([
        model_portion.FoodPortion(food: foodV1, grams: 100, unit: 'g'),
      ], logDate);

      // 3. Update nutrition (triggers versioning)
      final foodWithNewNutrition = foodV1.copyWith(calories: 2.0);
      final foodIdV2 = await databaseService.saveFood(foodWithNewNutrition);

      expect(
        foodIdV2,
        isNot(foodIdV1),
        reason: 'A new version should have been created',
      );

      final foodV2 = foodWithNewNutrition.copyWith(id: foodIdV2);

      // 4. Update image of the latest version (v2)
      // Reproducing the UI behavior where source is preserved (previously 'user' issue)
      final foodWithNewImage = foodV2.copyWith(thumbnail: 'new_image.png');
      final resultId = await databaseService.saveFood(foodWithNewImage);

      expect(
        resultId,
        foodIdV2,
        reason: 'Image update should be in-place for the latest version',
      );

      // 5. Check the latest version
      final latestFood = await databaseService.getFoodById(foodIdV2, 'live');

      expect(
        latestFood?.thumbnail,
        'new_image.png',
        reason: 'The version being edited SHOULD be updated',
      );

      // 6. Check the old version (log entry)
      final logs = await databaseService.getLoggedPortionsForDate(logDate);
      final loggedFood = logs.first.portion.food;

      // Per user request: Old version should NOT be updated
      expect(
        loggedFood.thumbnail,
        'initial_image.png',
        reason: 'Old version should RETAIN its original image',
      );
    },
  );
}
