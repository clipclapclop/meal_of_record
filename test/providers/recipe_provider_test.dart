import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/recipe.dart' as model;
import 'package:meal_of_record/models/recipe_item.dart' as model;
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_portion.dart' as model;
import 'package:meal_of_record/models/food_serving.dart' as model;
import 'package:meal_of_record/models/category.dart' as model;
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:drift/native.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart' as ref;

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late RecipeProvider provider;
  late DatabaseService databaseService;
  late LiveDatabase liveDb;
  late ref.ReferenceDatabase refDb;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    liveDb = LiveDatabase(connection: NativeDatabase.memory());
    refDb = ref.ReferenceDatabase(connection: NativeDatabase.memory());
    databaseService = DatabaseService.forTesting(liveDb, refDb);
    DatabaseService.initSingletonForTesting(liveDb, refDb);
    provider = RecipeProvider();
  });

  tearDown(() async {
    await liveDb.close();
    await refDb.close();
  });

  Future<model.Food> createTestFood({
    int id = 0,
    String name = 'Test Food',
  }) async {
    return model.Food(
      id: id,
      name: name,
      source: 'foundation',
      calories: 1.0,
      protein: 0.1,
      fat: 0.1,
      carbs: 0.1,
      fiber: 0.0,
      database: model.FoodDatabase.reference,
      servings: [
        model.FoodServing(foodId: id, unit: 'g', grams: 1.0, quantity: 1.0),
      ],
    );
  }

  Future<model.Recipe> createTestRecipe({
    int id = 0,
    String name = 'Test Recipe',
    List<model.RecipeItem>? items,
  }) async {
    final food = await databaseService.ensureFoodExists(
      await createTestFood(name: 'Ingredient'),
    );

    return model.Recipe(
      id: id,
      name: name,
      servingsCreated: 1.0,
      createdTimestamp: DateTime.now().millisecondsSinceEpoch,
      items:
          items ?? [model.RecipeItem(id: 0, food: food, grams: 100, unit: 'g')],
      categories: [],
    );
  }

  group('RecipeProvider Change Tracking', () {
    test('ingredientsChanged should be false initially', () {
      expect(provider.ingredientsChanged, isFalse);
    });

    test('ingredientsChanged should be false after loadFromRecipe', () async {
      final recipe = await createTestRecipe();
      provider.loadFromRecipe(recipe);
      expect(provider.ingredientsChanged, isFalse);
    });

    test('ingredientsChanged should be false after prepareVersion', () async {
      final recipe = await createTestRecipe();
      provider.prepareVersion(recipe);
      expect(provider.ingredientsChanged, isFalse);
    });

    test('ingredientsChanged should be false after prepareCopy', () async {
      final recipe = await createTestRecipe();
      provider.prepareCopy(recipe);
      expect(provider.ingredientsChanged, isFalse);
    });

    test('addItem should set ingredientsChanged to true', () async {
      final recipe = await createTestRecipe();
      provider.loadFromRecipe(recipe);
      expect(provider.ingredientsChanged, isFalse);

      final food = await createTestFood(name: 'New Ingredient');
      final newItem = model.RecipeItem(id: 0, food: food, grams: 50, unit: 'g');
      provider.addItem(newItem);

      expect(provider.ingredientsChanged, isTrue);
    });

    test('removeItem should set ingredientsChanged to true', () async {
      final recipe = await createTestRecipe();
      provider.loadFromRecipe(recipe);
      expect(provider.ingredientsChanged, isFalse);

      provider.removeItem(0);

      expect(provider.ingredientsChanged, isTrue);
    });

    test('updateItem should set ingredientsChanged to true', () async {
      final recipe = await createTestRecipe();
      provider.loadFromRecipe(recipe);
      expect(provider.ingredientsChanged, isFalse);

      final food = await createTestFood(name: 'Updated Ingredient');
      final updatedItem = model.RecipeItem(
        id: 0,
        food: food,
        grams: 150,
        unit: 'g',
      );
      provider.updateItem(0, updatedItem);

      expect(provider.ingredientsChanged, isTrue);
    });

    test('reorderItem uses onReorderItem post-removal indices', () async {
      final first = await createTestFood(name: 'First');
      final second = await createTestFood(name: 'Second');
      final third = await createTestFood(name: 'Third');
      final recipe = await createTestRecipe(
        items: [
          model.RecipeItem(id: 1, food: first, grams: 10, unit: 'g'),
          model.RecipeItem(id: 2, food: second, grams: 20, unit: 'g'),
          model.RecipeItem(id: 3, food: third, grams: 30, unit: 'g'),
        ],
      );
      provider.loadFromRecipe(recipe);

      provider.reorderItem(0, 2);
      expect(provider.items.map((item) => item.food!.name), [
        'Second',
        'Third',
        'First',
      ]);

      provider.reorderItem(2, 0);
      expect(provider.items.map((item) => item.food!.name), [
        'First',
        'Second',
        'Third',
      ]);
      expect(provider.ingredientsChanged, isTrue);
    });

    test('metadata changes should not set ingredientsChanged', () async {
      final recipe = await createTestRecipe();
      provider.loadFromRecipe(recipe);
      expect(provider.ingredientsChanged, isFalse);

      provider.setName('New Name');
      expect(provider.ingredientsChanged, isFalse);

      provider.setPortionName('Serving');
      expect(provider.ingredientsChanged, isFalse);

      provider.setServingsCreated(2.0);
      expect(provider.ingredientsChanged, isFalse);

      provider.setFinalWeightGrams(200.0);
      expect(provider.ingredientsChanged, isFalse);

      provider.setNotes('Some notes');
      expect(provider.ingredientsChanged, isFalse);

      provider.setIsTemplate(true);
      expect(provider.ingredientsChanged, isFalse);

      final category = model.Category(id: 1, name: 'Test Category');
      provider.toggleCategory(category);
      expect(provider.ingredientsChanged, isFalse);
    });

    test('reset should reset ingredientsChanged to false', () async {
      final recipe = await createTestRecipe();
      provider.loadFromRecipe(recipe);
      provider.addItem(
        model.RecipeItem(
          id: 0,
          food: await createTestFood(name: 'New'),
          grams: 50,
          unit: 'g',
        ),
      );
      expect(provider.ingredientsChanged, isTrue);

      provider.reset();
      expect(provider.ingredientsChanged, isFalse);
    });
  });

  group('RecipeProvider Save Behavior', () {
    test('saveRecipe should create new recipe when id is 0', () async {
      final recipe = await createTestRecipe();
      provider.loadFromRecipe(recipe);

      final success = await provider.saveRecipe();
      expect(success, isTrue);
      expect(provider.id, 0); // Reset after save
    });

    test(
      'saveRecipe should update in place when not logged and ingredients changed',
      () async {
        final recipeId = await databaseService.saveRecipe(
          await createTestRecipe(),
        );
        final recipe = await databaseService.getRecipeById(recipeId);
        provider.loadFromRecipe(recipe, isLogged: false);

        // Add an ingredient
        final food = await createTestFood(name: 'New Ingredient');
        provider.addItem(
          model.RecipeItem(id: 0, food: food, grams: 50, unit: 'g'),
        );

        final success = await provider.saveRecipe();
        expect(success, isTrue);

        // Should have updated in place (only one recipe)
        final allRecipes = await databaseService.getRecipes(
          includeHidden: true,
        );
        expect(allRecipes.length, 1);
        expect(allRecipes.first.id, recipeId);
      },
    );

    test(
      'saveRecipe should update in place when logged but only metadata changed',
      () async {
        final recipeId = await databaseService.saveRecipe(
          await createTestRecipe(),
        );
        final recipe = await databaseService.getRecipeById(recipeId);

        // Log the recipe
        await databaseService.logPortions([
          model.FoodPortion(food: recipe.toFood(), grams: 100, unit: 'g'),
        ], DateTime.now());

        provider.loadFromRecipe(recipe, isLogged: true);

        // Only change metadata
        provider.setName('Updated Name');
        provider.setPortionName('Serving');
        provider.setNotes('New Notes');

        final success = await provider.saveRecipe();
        expect(success, isTrue);

        // Should have updated in place (only one recipe)
        final allRecipes = await databaseService.getRecipes(
          includeHidden: true,
        );
        expect(allRecipes.length, 1);
        expect(allRecipes.first.id, recipeId);
        expect(allRecipes.first.name, 'Updated Name');
        expect(allRecipes.first.notes, 'New Notes');
      },
    );

    test(
      'saveRecipe should copy when logged and servingsCreated changed',
      () async {
        final recipeId = await databaseService.saveRecipe(
          await createTestRecipe(),
        );
        final recipe = await databaseService.getRecipeById(recipeId);

        // Log the recipe
        await databaseService.logPortions([
          model.FoodPortion(food: recipe.toFood(), grams: 100, unit: 'g'),
        ], DateTime.now());

        provider.loadFromRecipe(recipe, isLogged: true);

        // Change servingsCreated (Nutritional change)
        provider.setServingsCreated(2.0);

        final success = await provider.saveRecipe();
        expect(success, isTrue);

        // Should have created a new recipe
        final allRecipes = await databaseService.getRecipes(
          includeHidden: true,
        );
        expect(allRecipes.length, 2);
        expect(allRecipes.any((r) => r.parentId == recipeId), isTrue);
      },
    );

    test(
      'saveRecipe should copy when logged and ingredients changed',
      () async {
        final recipeId = await databaseService.saveRecipe(
          await createTestRecipe(),
        );
        final recipe = await databaseService.getRecipeById(recipeId);

        // Log the recipe
        await databaseService.logPortions([
          model.FoodPortion(food: recipe.toFood(), grams: 100, unit: 'g'),
        ], DateTime.now());

        provider.loadFromRecipe(recipe, isLogged: true);

        // Add an ingredient
        final food = await createTestFood(name: 'New Ingredient');
        provider.addItem(
          model.RecipeItem(id: 0, food: food, grams: 50, unit: 'g'),
        );

        final success = await provider.saveRecipe();
        expect(success, isTrue);

        // Should have created a new recipe (two total)
        final allRecipes = await databaseService.getRecipes(
          includeHidden: true,
        );
        expect(allRecipes.length, 2);

        // Original should be hidden
        final original = allRecipes.firstWhere((r) => r.id == recipeId);
        expect(original.hidden, isTrue);

        // New recipe should be visible
        final newRecipe = allRecipes.firstWhere((r) => r.id != recipeId);
        expect(newRecipe.hidden, isFalse);
        expect(newRecipe.parentId, recipeId);
      },
    );

    test('saveRecipe should copy when logged and ingredient removed', () async {
      final recipeId = await databaseService.saveRecipe(
        await createTestRecipe(),
      );
      final recipe = await databaseService.getRecipeById(recipeId);

      // Log the recipe
      await databaseService.logPortions([
        model.FoodPortion(food: recipe.toFood(), grams: 100, unit: 'g'),
      ], DateTime.now());

      provider.loadFromRecipe(recipe, isLogged: true);

      // Remove the ingredient
      provider.removeItem(0);

      // This should fail validation (no ingredients)
      final success = await provider.saveRecipe();
      expect(success, isFalse);
      expect(provider.errorMessage, contains('ingredient'));
    });

    test(
      'saveRecipe should copy when logged and ingredient modified',
      () async {
        final recipeId = await databaseService.saveRecipe(
          await createTestRecipe(),
        );
        final recipe = await databaseService.getRecipeById(recipeId);

        // Log the recipe
        await databaseService.logPortions([
          model.FoodPortion(food: recipe.toFood(), grams: 100, unit: 'g'),
        ], DateTime.now());

        provider.loadFromRecipe(recipe, isLogged: true);

        // Modify the ingredient
        final food = await createTestFood(name: 'Modified Ingredient');
        provider.updateItem(
          0,
          model.RecipeItem(id: 0, food: food, grams: 150, unit: 'g'),
        );

        final success = await provider.saveRecipe();
        expect(success, isTrue);

        // Should have created a new recipe (two total)
        final allRecipes = await databaseService.getRecipes(
          includeHidden: true,
        );
        expect(allRecipes.length, 2);

        // Original should be hidden
        final original = allRecipes.firstWhere((r) => r.id == recipeId);
        expect(original.hidden, isTrue);

        // New recipe should be visible
        final newRecipe = allRecipes.firstWhere((r) => r.id != recipeId);
        expect(newRecipe.hidden, isFalse);
        expect(newRecipe.parentId, recipeId);
      },
    );
  });

  group('RecipeProvider Copy Behavior', () {
    test('prepareCopy should set name with - Copy suffix', () async {
      final recipe = await createTestRecipe(name: 'Original Recipe');
      provider.prepareCopy(recipe);

      expect(provider.name, 'Original Recipe - Copy');
      expect(provider.id, 0);
      expect(provider.parentId, isNull);
      expect(provider.ingredientsChanged, isFalse);
    });
  });

  group('RecipeProvider Import/Export', () {
    test('exportRecipe should return valid JSON', () async {
      final recipe = await createTestRecipe();
      final jsonStr = await provider.exportRecipe(recipe);
      expect(jsonStr, isNotEmpty);
      expect(jsonStr, contains('"name":"Test Recipe"'));
    });

    test('importRecipe should return ID on success', () async {
      final recipe = await createTestRecipe();
      final jsonStr = await provider.exportRecipe(recipe);

      final newId = await provider.importRecipe(jsonStr);
      expect(newId, isNotNull);
      expect(newId, isPositive);
      expect(newId, isNot(recipe.id)); // Should be a new ID
    });

    test('importRecipe should return null on invalid JSON', () async {
      final result = await provider.importRecipe('invalid json');
      expect(result, isNull);
      expect(provider.errorMessage, contains('Import failed'));
    });
  });
}
