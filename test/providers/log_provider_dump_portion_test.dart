import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/models/recipe.dart';
import 'package:meal_of_record/models/recipe_item.dart';
import 'package:meal_of_record/providers/log_provider.dart';

Food _makeFood(int id, String name, {double cal = 1.0}) {
  return Food(
    id: id,
    name: name,
    calories: cal,
    protein: 0.1,
    fat: 0.05,
    carbs: 0.2,
    fiber: 0.02,
    source: 'test',
    servings: [FoodServing(foodId: id, unit: 'g', grams: 1.0, quantity: 1.0)],
  );
}

void main() {
  late LogProvider logProvider;

  setUp(() {
    logProvider = LogProvider();
  });

  group('dumpRecipePortionsAsList', () {
    test(
      'dump-only recipe with 3 ingredients at 50% returns each at 50% grams',
      () {
        final food1 = _makeFood(1, 'Chicken');
        final food2 = _makeFood(2, 'Rice');
        final food3 = _makeFood(3, 'Broccoli');
        final recipe = Recipe(
          id: 10,
          name: 'Stir Fry',
          servingsCreated: 1.0,
          isTemplate: true,
          createdTimestamp: 0,
          items: [
            RecipeItem(id: 1, food: food1, grams: 200, unit: 'g'),
            RecipeItem(id: 2, food: food2, grams: 300, unit: 'g'),
            RecipeItem(id: 3, food: food3, grams: 100, unit: 'g'),
          ],
        );

        // 50% of a 1-serving recipe → quantity = 0.5
        final portions = logProvider.dumpRecipePortionsAsList(
          recipe,
          quantity: 0.5,
        );

        expect(portions.length, 3);
        expect(portions[0].food.name, 'Chicken');
        expect(portions[0].grams, 100.0); // 200 * 0.5
        expect(portions[1].food.name, 'Rice');
        expect(portions[1].grams, 150.0); // 300 * 0.5
        expect(portions[2].food.name, 'Broccoli');
        expect(portions[2].grams, 50.0); // 100 * 0.5
      },
    );

    test('dump-only recipe with finalWeightGrams scales correctly', () {
      final food1 = _makeFood(1, 'Pasta');
      final food2 = _makeFood(2, 'Sauce');
      final recipe = Recipe(
        id: 11,
        name: 'Pasta Dish',
        servingsCreated: 1.0,
        finalWeightGrams:
            400, // cooked weight is 400g, raw ingredients sum to 500g
        isTemplate: true,
        createdTimestamp: 0,
        items: [
          RecipeItem(id: 1, food: food1, grams: 300, unit: 'g'),
          RecipeItem(id: 2, food: food2, grams: 200, unit: 'g'),
        ],
      );

      // totalGrams = finalWeightGrams = 400
      // gramsPerPortion = 400 / 1 = 400
      // Serving 200g of 400g → quantity = 200 / 400 = 0.5
      final quantity = 200 / recipe.gramsPerPortion;
      final portions = logProvider.dumpRecipePortionsAsList(
        recipe,
        quantity: quantity,
      );

      expect(portions.length, 2);
      expect(portions[0].grams, closeTo(150.0, 0.01)); // 300 * 0.5
      expect(portions[1].grams, closeTo(100.0, 0.01)); // 200 * 0.5
    });

    test('dump-only recipe at quantity 0 returns empty list', () {
      final food1 = _makeFood(1, 'Chicken');
      final recipe = Recipe(
        id: 12,
        name: 'Solo',
        servingsCreated: 1.0,
        isTemplate: true,
        createdTimestamp: 0,
        items: [RecipeItem(id: 1, food: food1, grams: 100, unit: 'g')],
      );

      final portions = logProvider.dumpRecipePortionsAsList(
        recipe,
        quantity: 0,
      );

      expect(portions.length, 1); // Still returns items, but at 0 grams
      expect(portions[0].grams, 0.0);
    });

    test('dump-only recipe with nested sub-recipe scales recursively', () {
      final food1 = _makeFood(1, 'Flour');
      final food2 = _makeFood(2, 'Butter');
      final food3 = _makeFood(3, 'Filling');

      final subRecipe = Recipe(
        id: 20,
        name: 'Dough',
        servingsCreated: 1.0,
        createdTimestamp: 0,
        items: [
          RecipeItem(id: 1, food: food1, grams: 200, unit: 'g'),
          RecipeItem(id: 2, food: food2, grams: 100, unit: 'g'),
        ],
      );

      final mainRecipe = Recipe(
        id: 21,
        name: 'Pie',
        servingsCreated: 1.0,
        isTemplate: true,
        createdTimestamp: 0,
        items: [
          // Use 1 portion (300g) of sub-recipe dough
          RecipeItem(id: 3, recipe: subRecipe, grams: 300, unit: 'portion'),
          RecipeItem(id: 4, food: food3, grams: 200, unit: 'g'),
        ],
      );

      // At 50%:
      final portions = logProvider.dumpRecipePortionsAsList(
        mainRecipe,
        quantity: 0.5,
      );

      expect(portions.length, 3); // flour, butter, filling
      expect(portions[0].food.name, 'Flour');
      expect(portions[0].grams, closeTo(100.0, 0.01)); // 200 * (300/300) * 0.5
      expect(portions[1].food.name, 'Butter');
      expect(portions[1].grams, closeTo(50.0, 0.01)); // 100 * (300/300) * 0.5
      expect(portions[2].food.name, 'Filling');
      expect(portions[2].grams, closeTo(100.0, 0.01)); // 200 * 0.5
    });

    test(
      'dumpRecipeToQueue with specific quantity adds correct proportional ingredients',
      () {
        final food1 = _makeFood(1, 'Chicken', cal: 1.65);
        final food2 = _makeFood(2, 'Rice', cal: 1.30);
        final recipe = Recipe(
          id: 13,
          name: 'Bowl',
          servingsCreated: 2.0,
          isTemplate: true,
          createdTimestamp: 0,
          items: [
            RecipeItem(id: 1, food: food1, grams: 400, unit: 'g'),
            RecipeItem(id: 2, food: food2, grams: 600, unit: 'g'),
          ],
        );

        // gramsPerPortion = 1000 / 2 = 500g
        // User wants 250g → quantity = 250 / 500 = 0.5
        logProvider.dumpRecipeToQueue(recipe, quantity: 0.5);

        expect(logProvider.logQueue.length, 2);
        expect(logProvider.logQueue[0].grams, 200.0); // 400 * 0.5
        expect(logProvider.logQueue[1].grams, 300.0); // 600 * 0.5
        // Calories: 200*1.65 + 300*1.30 = 330 + 390 = 720
        expect(logProvider.queuedCalories, closeTo(720.0, 0.01));
      },
    );
  });
}
