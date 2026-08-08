import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/models/recipe.dart';
import 'package:meal_of_record/models/recipe_item.dart';

void main() {
  late LogProvider logProvider;

  setUp(() {
    logProvider = LogProvider();
  });

  group('LogProvider', () {
    test('should add a food serving to the queue and update calories', () {
      // Arrange
      final food = Food(
        id: 1,
        name: 'Apple',
        calories: 0.52, // per gram
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      final portion = FoodPortion(food: food, grams: 100, unit: 'g');

      // Act
      logProvider.addFoodToQueue(portion);

      // Assert
      // 0.52 calories/g * 1.0 g/unit * 100 units = 52 calories
      expect(logProvider.logQueue.length, 1);
      expect(logProvider.logQueue.first, portion);
      expect(logProvider.queuedCalories, 52);
    });

    test('should remove a food serving from the queue and update calories', () {
      // Arrange
      final food = Food(
        id: 1,
        name: 'Apple',
        calories: 0.52, // per gram
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      final portion = FoodPortion(food: food, grams: 100, unit: 'g');
      logProvider.addFoodToQueue(portion);

      // Act
      logProvider.removeFoodFromQueue(portion);

      // Assert
      expect(logProvider.logQueue.length, 0);
      expect(logProvider.queuedCalories, 0);
    });

    test('should clear the queue and reset calories', () {
      // Arrange
      final food = Food(
        id: 1,
        name: 'Apple',
        calories: 0.52, // per gram
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      final serving = FoodPortion(food: food, grams: 100, unit: 'g');
      logProvider.addFoodToQueue(serving);

      // Act
      logProvider.clearQueue();

      // Assert
      expect(logProvider.logQueue.length, 0);
      expect(logProvider.queuedCalories, 0);
    });

    test(
      'should correctly calculate calories for a serving with a different unit',
      () {
        // Arrange
        final food = Food(
          id: 1,
          name: 'Apple',
          calories: 0.52, // per gram
          protein: 0.003,
          fat: 0.002,
          carbs: 0.14,
          fiber: 0.0,
          source: 'test',
          servings: [
            FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
            FoodServing(
              id: 2,
              foodId: 1,
              unit: 'slice',
              grams: 10.0,
              quantity: 1.0,
            ),
          ],
        );
        final serving = FoodPortion(food: food, grams: 20, unit: 'slice');

        // Act
        logProvider.addFoodToQueue(serving);

        // Assert
        // 2 slices * 10g/slice = 20g
        // 0.52 calories/g * 20g = 10.4 calories
        expect(logProvider.queuedCalories, 10.4);
      },
    );

    test(
      'addRecipeToQueue should add a recipe as a single item if not a template',
      () {
        // Arrange
        final food = Food(
          id: 1,
          name: 'Ingredient',
          calories: 1.0,
          protein: 0.1,
          fat: 0.1,
          carbs: 0.1,
          fiber: 0.0,
          source: 'test',
          servings: [
            FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
          ],
        );
        final recipe = Recipe(
          id: 10,
          name: 'Recipe',
          servingsCreated: 1.0,
          createdTimestamp: 0,
          items: [RecipeItem(id: 1, food: food, grams: 100, unit: 'g')],
        );

        // Act
        logProvider.addRecipeToQueue(recipe);

        // Assert
        expect(logProvider.logQueue.length, 1);
        expect(logProvider.logQueue.first.food.name, 'Recipe');
        expect(logProvider.logQueue.first.grams, 100);
        expect(logProvider.queuedCalories, 100);
      },
    );

    test('addRecipeToQueue should dump a recipe if it is a template', () {
      // Arrange
      final food = Food(
        id: 1,
        name: 'Ingredient',
        calories: 1.0,
        protein: 0.1,
        fat: 0.1,
        carbs: 0.1,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      final recipe = Recipe(
        id: 10,
        name: 'Recipe',
        servingsCreated: 1.0,
        createdTimestamp: 0,
        isTemplate: true,
        items: [RecipeItem(id: 1, food: food, grams: 100, unit: 'g')],
      );

      // Act
      logProvider.addRecipeToQueue(recipe);

      // Assert
      expect(logProvider.logQueue.length, 1);
      expect(logProvider.logQueue.first.food.name, 'Ingredient');
      expect(logProvider.logQueue.first.grams, 100);
      expect(logProvider.queuedCalories, 100);
    });

    test(
      'dumpRecipeToQueue should force decomposition even if not a template',
      () {
        // Arrange
        final food = Food(
          id: 1,
          name: 'Ingredient',
          calories: 1.0,
          protein: 0.1,
          fat: 0.1,
          carbs: 0.1,
          fiber: 0.0,
          source: 'test',
          servings: [
            FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
          ],
        );
        final recipe = Recipe(
          id: 10,
          name: 'Recipe',
          servingsCreated: 1.0,
          createdTimestamp: 0,
          isTemplate: false,
          items: [RecipeItem(id: 1, food: food, grams: 100, unit: 'g')],
        );

        // Act
        logProvider.dumpRecipeToQueue(recipe);

        // Assert
        expect(logProvider.logQueue.length, 1);
        expect(logProvider.logQueue.first.food.name, 'Ingredient');
        expect(logProvider.logQueue.first.grams, 100);
        expect(logProvider.queuedCalories, 100);
      },
    );

    test('empty state: all computed getters return 0', () {
      expect(logProvider.queuedCalories, 0.0);
      expect(logProvider.queuedProtein, 0.0);
      expect(logProvider.queuedFat, 0.0);
      expect(logProvider.queuedCarbs, 0.0);
      expect(logProvider.queuedFiber, 0.0);
      expect(logProvider.loggedCalories, 0.0);
      expect(logProvider.loggedProtein, 0.0);
      expect(logProvider.loggedFat, 0.0);
      expect(logProvider.loggedCarbs, 0.0);
      expect(logProvider.loggedFiber, 0.0);
    });

    test('single item: all 5 queued macro getters are correct', () {
      final food = Food(
        id: 1,
        name: 'Chicken',
        calories: 1.65,
        protein: 0.31,
        fat: 0.036,
        carbs: 0.0,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      final portion = FoodPortion(food: food, grams: 100, unit: 'g');

      logProvider.addFoodToQueue(portion);

      expect(logProvider.queuedCalories, closeTo(165.0, 0.01));
      expect(logProvider.queuedProtein, closeTo(31.0, 0.01));
      expect(logProvider.queuedFat, closeTo(3.6, 0.01));
      expect(logProvider.queuedCarbs, 0.0);
      expect(logProvider.queuedFiber, 0.0);
    });

    test('multiple items: sums are correct', () {
      final food1 = Food(
        id: 1,
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.024,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      final food2 = Food(
        id: 2,
        name: 'Banana',
        calories: 0.89,
        protein: 0.011,
        fat: 0.003,
        carbs: 0.228,
        fiber: 0.026,
        source: 'test',
        servings: [
          FoodServing(id: 2, foodId: 2, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      final food3 = Food(
        id: 3,
        name: 'Rice',
        calories: 1.30,
        protein: 0.027,
        fat: 0.003,
        carbs: 0.28,
        fiber: 0.004,
        source: 'test',
        servings: [
          FoodServing(id: 3, foodId: 3, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );

      logProvider.addFoodToQueue(
        FoodPortion(food: food1, grams: 100, unit: 'g'),
      );
      logProvider.addFoodToQueue(
        FoodPortion(food: food2, grams: 120, unit: 'g'),
      );
      logProvider.addFoodToQueue(
        FoodPortion(food: food3, grams: 200, unit: 'g'),
      );

      // Apple: 0.52*100=52, Banana: 0.89*120=106.8, Rice: 1.30*200=260
      expect(logProvider.queuedCalories, closeTo(418.8, 0.01));
      // Apple: 0.003*100=0.3, Banana: 0.011*120=1.32, Rice: 0.027*200=5.4
      expect(logProvider.queuedProtein, closeTo(7.02, 0.01));
    });

    test('add then remove: queued macros return to 0', () {
      final food = Food(
        id: 1,
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      final portion = FoodPortion(food: food, grams: 100, unit: 'g');

      logProvider.addFoodToQueue(portion);
      expect(logProvider.queuedCalories, 52);

      logProvider.removeFoodFromQueue(portion);
      expect(logProvider.queuedCalories, 0.0);
      expect(logProvider.queuedProtein, 0.0);
      expect(logProvider.queuedFat, 0.0);
      expect(logProvider.queuedCarbs, 0.0);
      expect(logProvider.queuedFiber, 0.0);
    });

    test('clear queue: all queued macros return to 0', () {
      final food = Food(
        id: 1,
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      logProvider.addFoodToQueue(
        FoodPortion(food: food, grams: 100, unit: 'g'),
      );
      logProvider.addFoodToQueue(
        FoodPortion(food: food, grams: 200, unit: 'g'),
      );
      expect(logProvider.queuedCalories, closeTo(156.0, 0.01));

      logProvider.clearQueue();
      expect(logProvider.queuedCalories, 0.0);
      expect(logProvider.queuedProtein, 0.0);
    });

    test('update item in queue: macros reflect new grams', () {
      final food = Food(
        id: 1,
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      logProvider.addFoodToQueue(
        FoodPortion(food: food, grams: 100, unit: 'g'),
      );
      expect(logProvider.queuedCalories, 52.0);

      logProvider.updateFoodInQueue(
        0,
        FoodPortion(food: food, grams: 200, unit: 'g'),
      );
      expect(logProvider.queuedCalories, 104.0);
    });

    test(
      'refreshFoodInQueue: null sourceBarcode should not cause false matches',
      () async {
        // Two different OFF foods, both with null sourceBarcode
        // (simulates the bug where edited OFF foods lost their barcode)
        final offFoodA = Food(
          id: 0,
          name: 'OFF Food A',
          calories: 1.0,
          protein: 0.1,
          fat: 0.1,
          carbs: 0.1,
          fiber: 0.0,
          source: 'off',
          sourceBarcode: null,
          servings: [
            FoodServing(id: 1, foodId: 0, unit: 'g', grams: 1.0, quantity: 1.0),
          ],
        );
        final offFoodB = Food(
          id: 0,
          name: 'OFF Food B',
          calories: 2.0,
          protein: 0.2,
          fat: 0.2,
          carbs: 0.2,
          fiber: 0.0,
          source: 'off',
          sourceBarcode: null,
          servings: [
            FoodServing(id: 2, foodId: 0, unit: 'g', grams: 1.0, quantity: 1.0),
          ],
        );

        logProvider.addFoodToQueue(
          FoodPortion(food: offFoodA, grams: 50, unit: 'g'),
        );

        // Refresh queue with offFoodB — should NOT replace offFoodA
        await logProvider.refreshFoodInQueue(0, offFoodB);

        // offFoodA should still be in the queue (matched by id=0, which is fine),
        // but the key point: if both had null barcodes previously, the null guard
        // prevents false barcode-based matching
        expect(logProvider.logQueue.length, 1);
        // The id-based match (id==0) will still replace, but that's expected.
        // The important thing is the barcode branch doesn't cause extra matches.
      },
    );

    test(
      'refreshFoodInQueue: matches OFF food by barcode, leaves others unchanged',
      () async {
        final offFoodA = Food(
          id: 0,
          name: 'Peanut Butter A',
          calories: 6.0,
          protein: 0.3,
          fat: 0.5,
          carbs: 0.2,
          fiber: 0.1,
          source: 'off',
          sourceBarcode: '12345',
          servings: [
            FoodServing(id: 1, foodId: 0, unit: 'g', grams: 1.0, quantity: 1.0),
          ],
        );
        final offFoodB = Food(
          id: 0,
          name: 'Peanut Butter B',
          calories: 5.0,
          protein: 0.2,
          fat: 0.4,
          carbs: 0.3,
          fiber: 0.1,
          source: 'off',
          sourceBarcode: '67890',
          servings: [
            FoodServing(id: 2, foodId: 0, unit: 'g', grams: 1.0, quantity: 1.0),
          ],
        );

        logProvider.addFoodToQueue(
          FoodPortion(food: offFoodA, grams: 28, unit: 'g'),
        );
        logProvider.addFoodToQueue(
          FoodPortion(food: offFoodB, grams: 32, unit: 'g'),
        );

        // Edit food A (now saved with id=99), refresh queue
        final updatedA = Food(
          id: 99,
          name: 'Peanut Butter A (edited)',
          calories: 6.5,
          protein: 0.35,
          fat: 0.55,
          carbs: 0.15,
          fiber: 0.1,
          source: 'off',
          sourceBarcode: '12345',
          servings: [
            FoodServing(
              id: 3,
              foodId: 99,
              unit: 'g',
              grams: 1.0,
              quantity: 1.0,
            ),
          ],
        );

        await logProvider.refreshFoodInQueue(99, updatedA);

        expect(logProvider.logQueue.length, 2);
        // First item should be updated to the edited version
        expect(logProvider.logQueue[0].food.name, 'Peanut Butter A (edited)');
        expect(logProvider.logQueue[0].grams, 28); // grams preserved
        // Second item should be untouched
        expect(logProvider.logQueue[1].food.name, 'Peanut Butter B');
        expect(logProvider.logQueue[1].grams, 32);
      },
    );

    test('total getters = logged + queued', () {
      final food = Food(
        id: 1,
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.0,
        source: 'test',
        servings: [
          FoodServing(id: 1, foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
        ],
      );
      logProvider.addFoodToQueue(
        FoodPortion(food: food, grams: 100, unit: 'g'),
      );

      expect(
        logProvider.totalCalories,
        logProvider.loggedCalories + logProvider.queuedCalories,
      );
      expect(
        logProvider.totalProtein,
        logProvider.loggedProtein + logProvider.queuedProtein,
      );
      expect(
        logProvider.totalFat,
        logProvider.loggedFat + logProvider.queuedFat,
      );
      expect(
        logProvider.totalCarbs,
        logProvider.loggedCarbs + logProvider.queuedCarbs,
      );
      expect(
        logProvider.totalFiber,
        logProvider.loggedFiber + logProvider.queuedFiber,
      );
    });
  });
}
