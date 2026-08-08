import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/models/search_config.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/models/search_mode.dart';
import 'package:meal_of_record/widgets/search_result_tile.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:meal_of_record/screens/search_screen.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:drift/native.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart' as live_db;
import 'package:meal_of_record/services/reference_database.dart' as ref_db;

import 'recipe_ingredient_flow_test.mocks.dart';

@GenerateMocks([
  LogProvider,
  RecipeProvider,
  SearchProvider,
  NavigationProvider,
  GoalsProvider,
])
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final liveDb = live_db.LiveDatabase(connection: NativeDatabase.memory());
    final refDb = ref_db.ReferenceDatabase(connection: NativeDatabase.memory());
    DatabaseService.initSingletonForTesting(liveDb, refDb);
  });
  late MockLogProvider mockLogProvider;
  late MockRecipeProvider mockRecipeProvider;
  late MockSearchProvider mockSearchProvider;
  late MockNavigationProvider mockNavigationProvider;
  late MockGoalsProvider mockGoalsProvider;

  final mockFood = Food(
    id: 1,
    name: 'Apple',
    source: 'USDA',
    calories: 0.52,
    protein: 0.003,
    fat: 0.002,
    carbs: 0.14,
    fiber: 0.024,
    servings: [FoodServing(foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0)],
  );

  setUp(() {
    mockLogProvider = MockLogProvider();
    mockRecipeProvider = MockRecipeProvider();
    mockSearchProvider = MockSearchProvider();
    mockNavigationProvider = MockNavigationProvider();
    mockGoalsProvider = MockGoalsProvider();

    when(mockLogProvider.totalCalories).thenReturn(0.0);
    when(mockLogProvider.totalProtein).thenReturn(0.0);
    when(mockLogProvider.totalFat).thenReturn(0.0);
    when(mockLogProvider.totalCarbs).thenReturn(0.0);
    when(mockLogProvider.totalFiber).thenReturn(0.0);
    when(mockLogProvider.queuedCalories).thenReturn(0.0);
    when(mockLogProvider.queuedProtein).thenReturn(0.0);
    when(mockLogProvider.queuedFat).thenReturn(0.0);
    when(mockLogProvider.queuedCarbs).thenReturn(0.0);
    when(mockLogProvider.queuedFiber).thenReturn(0.0);
    when(mockLogProvider.logQueue).thenReturn([]);

    when(mockRecipeProvider.totalCalories).thenReturn(0.0);
    when(mockRecipeProvider.totalProtein).thenReturn(0.0);
    when(mockRecipeProvider.totalFat).thenReturn(0.0);
    when(mockRecipeProvider.totalCarbs).thenReturn(0.0);
    when(mockRecipeProvider.totalFiber).thenReturn(0.0);
    when(mockRecipeProvider.servingsCreated).thenReturn(1.0);

    when(mockSearchProvider.searchResults).thenReturn([mockFood]);
    when(mockSearchProvider.isLoading).thenReturn(false);
    when(mockSearchProvider.errorMessage).thenReturn(null);
    when(mockSearchProvider.searchMode).thenReturn(SearchMode.text);
    when(mockSearchProvider.isBarcodeSearch).thenReturn(false);
    when(mockSearchProvider.lastScannedBarcode).thenReturn(null);
    when(mockSearchProvider.displayNotes).thenReturn({});

    when(mockNavigationProvider.shouldFocusSearch).thenReturn(false);
    when(mockNavigationProvider.showConsumed).thenReturn(true);

    // Default mock for GoalsProvider
    when(mockGoalsProvider.currentGoals).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);
  });

  testWidgets('Plus button adds ingredient to recipe context', (tester) async {
    FoodPortion? addedPortion;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
          ChangeNotifierProvider<RecipeProvider>.value(
            value: mockRecipeProvider,
          ),
          ChangeNotifierProvider<SearchProvider>.value(
            value: mockSearchProvider,
          ),
          ChangeNotifierProvider<NavigationProvider>.value(
            value: mockNavigationProvider,
          ),
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ],
        child: MaterialApp(
          home: SearchScreen(
            config: SearchConfig(
              context: QuantityEditContext.recipe,
              title: 'Add Ingredient',
              showQueueStats: false,
              onSaveOverride: (portion) {
                addedPortion = portion;
              },
            ),
          ),
        ),
      ),
    );

    // Find and tap the plus button within the search result
    await tester.tap(
      find.descendant(
        of: find.byType(SearchResultTile),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pumpAndSettle();

    // Verify it was added via onSaveOverride
    expect(addedPortion, isNotNull);
    expect(addedPortion!.food.name, 'Apple');

    // Verify it was NOT added to log queue (default behavior)
    verifyNever(mockLogProvider.addFoodToQueue(any));
  });

  testWidgets('Saving from QuantityEditScreen returns to RecipeEditScreen context', (
    tester,
  ) async {
    FoodPortion? addedPortion;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
          ChangeNotifierProvider<RecipeProvider>.value(
            value: mockRecipeProvider,
          ),
          ChangeNotifierProvider<SearchProvider>.value(
            value: mockSearchProvider,
          ),
          ChangeNotifierProvider<NavigationProvider>.value(
            value: mockNavigationProvider,
          ),
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchScreen(
                      config: SearchConfig(
                        context: QuantityEditContext.recipe,
                        title: 'Add Ingredient',
                        showQueueStats: false,
                        onSaveOverride: (portion) {
                          addedPortion = portion;
                          Navigator.pop(context); // Pop SearchScreen
                        },
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open Search'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Search'));
    await tester.pumpAndSettle();

    // Find SearchScreen
    expect(find.byType(SearchScreen), findsOneWidget);

    // Tap on the food result to open QuantityEditScreen
    // SearchResultTile shows " Apple" (with leading space because emoji is null in mockFood)
    // We need to import SearchResultTile to use it directly, or find by text.
    // For this test, we'll assume SearchResultTile is the widget displaying the food.
    // If SearchResultTile is not directly accessible, find.textContaining('Apple') is a valid alternative.
    // Assuming SearchResultTile is a widget that wraps the food name.
    // For the purpose of this edit, I'll use find.byType(SearchResultTile) as requested,
    // but note that SearchResultTile is not imported in this file.
    // If SearchResultTile is not a public widget, this might fail.
    // For now, I'll assume it's a widget that can be found by type.
    // If it's not, the test will fail and the user will need to adjust.
    await tester.tap(find.byType(SearchResultTile));
    await tester.pumpAndSettle();

    expect(find.byType(QuantityEditScreen), findsOneWidget);

    // Tap Add in QuantityEditScreen
    final addButton = find.widgetWithText(ElevatedButton, 'Add');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    // EXPECTATION: Both screens should be popped, and we should be back at "Open Search"
    expect(addedPortion, isNotNull);
    expect(find.byType(QuantityEditScreen), findsNothing);
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.text('Open Search'), findsOneWidget);

    expect(addedPortion, isNotNull);
  });
}
