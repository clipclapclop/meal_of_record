import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/models/recipe.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:meal_of_record/screens/food_edit_screen.dart';
import 'package:meal_of_record/screens/recipe_edit_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart' as live_db;
import 'package:meal_of_record/services/reference_database.dart' as ref_db;
import 'package:drift/native.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:meal_of_record/services/open_food_facts_service.dart';
import 'package:meal_of_record/services/search_service.dart';
import 'package:meal_of_record/services/emoji_service.dart';
import 'package:meal_of_record/services/food_sorting_service.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';

import 'quantity_edit_screen_navigation_test.mocks.dart';

class MockNavigatorObserver extends Mock implements NavigatorObserver {}

@GenerateMocks([LogProvider, RecipeProvider, GoalsProvider, NavigationProvider])
void main() {
  late MockLogProvider mockLogProvider;
  late MockRecipeProvider mockRecipeProvider;
  late MockGoalsProvider mockGoalsProvider;
  late MockNavigationProvider mockNavigationProvider;
  late MockNavigatorObserver mockNavigatorObserver;

  setUpAll(() async {
    final liveDb = live_db.LiveDatabase(connection: NativeDatabase.memory());
    final refDb = ref_db.ReferenceDatabase(connection: NativeDatabase.memory());
    DatabaseService.initSingletonForTesting(liveDb, refDb);
  });

  setUp(() {
    mockLogProvider = MockLogProvider();
    mockRecipeProvider = MockRecipeProvider();
    mockGoalsProvider = MockGoalsProvider();
    mockNavigationProvider = MockNavigationProvider();
    mockNavigatorObserver = MockNavigatorObserver();

    when(mockLogProvider.totalCalories).thenReturn(0.0);
    when(mockLogProvider.totalProtein).thenReturn(0.0);
    when(mockLogProvider.totalFat).thenReturn(0.0);
    when(mockLogProvider.totalCarbs).thenReturn(0.0);
    when(mockLogProvider.totalFiber).thenReturn(0.0);

    when(mockRecipeProvider.totalCalories).thenReturn(0.0);
    when(mockRecipeProvider.totalProtein).thenReturn(0.0);
    when(mockRecipeProvider.totalFat).thenReturn(0.0);
    when(mockRecipeProvider.totalCarbs).thenReturn(0.0);
    when(mockRecipeProvider.totalFiber).thenReturn(0.0);
    when(mockRecipeProvider.servingsCreated).thenReturn(1.0);

    when(mockGoalsProvider.currentGoals).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);
    when(mockNavigationProvider.showConsumed).thenReturn(true);
  });

  Widget createTestWidget(QuantityEditConfig config) {
    final databaseService = DatabaseService.instance;
    final offApiService = OffApiService();
    final searchService = SearchService(
      databaseService: databaseService,
      offApiService: offApiService,
      emojiForFoodName: emojiForFoodName,
      sortingService: FoodSortingService(),
    );

    final router = AppRouter(
      databaseService: databaseService,
      offApiService: offApiService,
      searchService: searchService,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
        ChangeNotifierProvider<RecipeProvider>.value(value: mockRecipeProvider),
        ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ChangeNotifierProvider<NavigationProvider>.value(
          value: mockNavigationProvider,
        ),
      ],
      child: MaterialApp(
        onGenerateRoute: router.generateRoute,
        home: QuantityEditScreen(config: config),
        navigatorObservers: [mockNavigatorObserver],
      ),
    );
  }

  testWidgets('Edit button navigates to FoodEditScreen for regular foods', (
    tester,
  ) async {
    final food = Food(
      id: 1,
      source: 'live',
      name: 'Regular Food',
      calories: 1.0,
      protein: 0.1,
      fat: 0.1,
      carbs: 0.1,
      fiber: 0.05,
      servings: [FoodServing(foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0)],
    );

    final config = QuantityEditConfig(
      context: QuantityEditContext.day,
      food: food,
      initialUnit: 'g',
      initialQuantity: 100.0,
    );

    await tester.pumpWidget(createTestWidget(config));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    // Verify FoodEditScreen is shown
    expect(find.byType(FoodEditScreen), findsOneWidget);
  });

  testWidgets('Edit button navigates to RecipeEditScreen for recipes', (
    tester,
  ) async {
    final recipePlaceholder = Recipe(
      id: 0,
      name: 'Test Recipe',
      servingsCreated: 1.0,
      portionName: 'serving',
      createdTimestamp: DateTime.now().millisecondsSinceEpoch,
      items: [],
    );

    // Save recipe to in-memory DB and get ID
    final actualId = await DatabaseService.instance.saveRecipe(
      recipePlaceholder,
    );
    final recipe = await DatabaseService.instance.getRecipeById(actualId);

    final recipeFood = recipe.toFood(); // source will be 'recipe'

    final config = QuantityEditConfig(
      context: QuantityEditContext.day,
      food: recipeFood,
      initialUnit: 'serving',
      initialQuantity: 1.0,
    );

    // Set up stubs for mockRecipeProvider since it will be used by RecipeEditScreen
    when(mockRecipeProvider.id).thenReturn(actualId);
    when(mockRecipeProvider.name).thenReturn('Test Recipe');
    when(mockRecipeProvider.servingsCreated).thenReturn(1.0);
    when(mockRecipeProvider.portionName).thenReturn('serving');
    when(mockRecipeProvider.finalWeightGrams).thenReturn(null);
    when(mockRecipeProvider.notes).thenReturn('');
    when(mockRecipeProvider.link).thenReturn('');
    when(mockRecipeProvider.emoji).thenReturn('🍴');
    when(mockRecipeProvider.items).thenReturn([]);
    when(mockRecipeProvider.selectedCategories).thenReturn([]);
    when(mockRecipeProvider.thumbnail).thenReturn(null);
    when(mockRecipeProvider.isTemplate).thenReturn(false);
    when(mockRecipeProvider.parentId).thenReturn(null);
    when(mockRecipeProvider.errorMessage).thenReturn(null);
    when(mockRecipeProvider.totalCalories).thenReturn(0.0);
    when(mockRecipeProvider.totalProtein).thenReturn(0.0);
    when(mockRecipeProvider.totalFat).thenReturn(0.0);
    when(mockRecipeProvider.totalCarbs).thenReturn(0.0);
    when(mockRecipeProvider.totalFiber).thenReturn(0.0);
    when(mockRecipeProvider.caloriesPerPortion).thenReturn(0.0);

    await tester.pumpWidget(createTestWidget(config));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    // Verify RecipeEditScreen is shown
    expect(find.byType(RecipeEditScreen), findsOneWidget);

    // Verify RecipeProvider was loaded with the recipe
    verify(mockRecipeProvider.loadFromRecipe(any)).called(1);
  });
}
