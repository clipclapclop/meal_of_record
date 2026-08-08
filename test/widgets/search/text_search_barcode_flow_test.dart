import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_serving.dart' as model_unit;
import 'package:meal_of_record/models/search_config.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/widgets/search/text_search_view.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:drift/native.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart' as ref;

import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/models/macro_goals.dart';

import 'package:meal_of_record/providers/navigation_provider.dart';

import 'search_edit_behavior_test.mocks.dart';

void main() {
  late LiveDatabase liveDb;

  setUpAll(() async {
    liveDb = LiveDatabase(connection: NativeDatabase.memory());
    final refDb = ref.ReferenceDatabase(connection: NativeDatabase.memory());
    DatabaseService.initSingletonForTesting(liveDb, refDb);
  });

  group('Barcode scan flow', () {
    late MockLogProvider mockLogProvider;
    late MockSearchProvider mockSearchProvider;
    late MockRecipeProvider mockRecipeProvider;
    late MockGoalsProvider mockGoalsProvider;
    late MockNavigationProvider mockNavigationProvider;

    setUp(() {
      mockLogProvider = MockLogProvider();
      mockSearchProvider = MockSearchProvider();
      mockRecipeProvider = MockRecipeProvider();
      mockGoalsProvider = MockGoalsProvider();
      mockNavigationProvider = MockNavigationProvider();

      when(mockLogProvider.logQueue).thenReturn([]);
      when(mockLogProvider.totalCalories).thenReturn(0.0);
      when(mockLogProvider.totalProtein).thenReturn(0.0);
      when(mockLogProvider.totalFat).thenReturn(0.0);
      when(mockLogProvider.totalCarbs).thenReturn(0.0);
      when(mockLogProvider.totalFiber).thenReturn(0.0);

      when(mockSearchProvider.isLoading).thenReturn(false);
      when(mockSearchProvider.errorMessage).thenReturn(null);
      when(mockSearchProvider.isBarcodeSearch).thenReturn(false);
      when(mockSearchProvider.lastScannedBarcode).thenReturn(null);
      when(mockSearchProvider.displayNotes).thenReturn({});

      when(mockRecipeProvider.totalCalories).thenReturn(0.0);
      when(mockRecipeProvider.totalProtein).thenReturn(0.0);
      when(mockRecipeProvider.totalFat).thenReturn(0.0);
      when(mockRecipeProvider.totalCarbs).thenReturn(0.0);
      when(mockRecipeProvider.totalFiber).thenReturn(0.0);

      when(mockGoalsProvider.currentGoals).thenReturn(MacroGoals.hardcoded());
      when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
      when(mockGoalsProvider.useNetCarbs).thenReturn(false);

      when(mockNavigationProvider.showConsumed).thenReturn(true);
    });

    Widget buildWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
          ChangeNotifierProvider<SearchProvider>.value(
            value: mockSearchProvider,
          ),
          ChangeNotifierProvider<RecipeProvider>.value(
            value: mockRecipeProvider,
          ),
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
          ChangeNotifierProvider<NavigationProvider>.value(
            value: mockNavigationProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TextSearchView(
              config: SearchConfig(
                context: QuantityEditContext.day,
                title: 'Search',
              ),
            ),
          ),
        ),
      );
    }

    model.Food makeFood() {
      return model.Food(
        id: 42,
        name: 'Test Banana',
        calories: 0.89,
        protein: 0.011,
        fat: 0.003,
        carbs: 0.23,
        fiber: 0.026,
        source: 'live',
        servings: [
          model_unit.FoodServing(
            id: 1,
            foodId: 42,
            unit: 'piece',
            grams: 182.0,
            quantity: 1.0,
          ),
          model_unit.FoodServing(
            id: 2,
            foodId: 42,
            unit: 'g',
            grams: 1.0,
            quantity: 1.0,
          ),
        ],
      );
    }

    testWidgets('single barcode result auto-opens QuantityEditScreen', (
      tester,
    ) async {
      final food = makeFood();

      when(mockSearchProvider.isBarcodeSearch).thenReturn(true);
      when(mockSearchProvider.searchResults).thenReturn([food]);
      when(mockSearchProvider.lastScannedBarcode).thenReturn('123');

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.byType(QuantityEditScreen), findsOneWidget);
    });

    testWidgets(
      'barcode result opens with default serving when no last-logged info',
      (tester) async {
        final food = makeFood();

        when(mockSearchProvider.isBarcodeSearch).thenReturn(true);
        when(mockSearchProvider.searchResults).thenReturn([food]);
        when(mockSearchProvider.lastScannedBarcode).thenReturn('456');

        await tester.pumpWidget(buildWidget());
        await tester.pumpAndSettle();

        final editScreen = tester.widget<QuantityEditScreen>(
          find.byType(QuantityEditScreen),
        );
        expect(editScreen.config.initialUnit, 'piece');
        expect(editScreen.config.initialQuantity, 1.0);
      },
    );

    testWidgets(
      'barcode search with no results shows enhanced not-found dialog with consistent ElevatedButton style',
      (tester) async {
        when(mockSearchProvider.isBarcodeSearch).thenReturn(true);
        when(mockSearchProvider.searchResults).thenReturn([]);
        when(mockSearchProvider.lastScannedBarcode).thenReturn('999');

        await tester.pumpWidget(buildWidget());
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Barcode Not Found'), findsOneWidget);

        // Verify all 4 action buttons are ElevatedButtons
        final elevatedButtons = find.byType(ElevatedButton);
        expect(elevatedButtons, findsNWidgets(4));

        expect(
          find.descendant(
            of: elevatedButtons,
            matching: find.text('Scan Again'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: elevatedButtons,
            matching: find.text('Search Open Food Facts'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: elevatedButtons,
            matching: find.text('Create Food'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: elevatedButtons, matching: find.text('Cancel')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'barcode search with no results shows enhanced not-found dialog',
      (tester) async {
        when(mockSearchProvider.isBarcodeSearch).thenReturn(true);
        when(mockSearchProvider.searchResults).thenReturn([]);
        when(mockSearchProvider.lastScannedBarcode).thenReturn('999');

        await tester.pumpWidget(buildWidget());
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Barcode Not Found'), findsOneWidget);
        expect(find.text('Scan Again'), findsOneWidget);
        expect(find.text('Search Open Food Facts'), findsOneWidget);
        expect(find.text('Create Food'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets(
      'clicking Search Open Food Facts in dialog calls barcodeOffSearch',
      (tester) async {
        when(mockSearchProvider.isBarcodeSearch).thenReturn(true);
        when(mockSearchProvider.searchResults).thenReturn([]);
        when(mockSearchProvider.lastScannedBarcode).thenReturn('999');

        await tester.pumpWidget(buildWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Search Open Food Facts'));
        await tester.pumpAndSettle();

        verify(mockSearchProvider.barcodeOffSearch('999')).called(1);
        verify(mockSearchProvider.clearBarcodeSearchState()).called(1);
      },
    );

    testWidgets('barcode search clears state after handling single result', (
      tester,
    ) async {
      final food = makeFood();

      when(mockSearchProvider.isBarcodeSearch).thenReturn(true);
      when(mockSearchProvider.searchResults).thenReturn([food]);
      when(mockSearchProvider.lastScannedBarcode).thenReturn('789');

      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      verify(mockSearchProvider.clearBarcodeSearchState()).called(1);
    });

    testWidgets(
      'barcode result opens with last-logged unit and quantity when available',
      (tester) async {
        const foodId = 42;

        // Insert food row into the live DB
        await liveDb
            .into(liveDb.foods)
            .insert(
              FoodsCompanion.insert(
                id: const Value(foodId),
                name: 'Test Banana',
                source: 'live',
                caloriesPerGram: 0.89,
                proteinPerGram: 0.011,
                fatPerGram: 0.003,
                carbsPerGram: 0.23,
                fiberPerGram: 0.026,
              ),
            );

        // Insert a logged portion with unit 'g' and quantity 250
        await liveDb
            .into(liveDb.loggedPortions)
            .insert(
              LoggedPortionsCompanion.insert(
                foodId: const Value(foodId),
                logTimestamp: 1000,
                grams: 250,
                unit: 'g',
                quantity: 250,
              ),
            );

        final food = makeFood(); // id=42, servings: piece, g

        when(mockSearchProvider.isBarcodeSearch).thenReturn(true);
        when(mockSearchProvider.searchResults).thenReturn([food]);
        when(mockSearchProvider.lastScannedBarcode).thenReturn('last-logged-1');

        await tester.pumpWidget(buildWidget());
        await tester.pumpAndSettle();

        final editScreen = tester.widget<QuantityEditScreen>(
          find.byType(QuantityEditScreen),
        );
        expect(editScreen.config.initialUnit, 'g');
        expect(editScreen.config.initialQuantity, 250.0);
      },
    );

    testWidgets(
      'barcode result falls back to default serving when last-logged unit not in servings',
      (tester) async {
        // Insert a logged portion with a unit that doesn't exist in food's servings
        await liveDb
            .into(liveDb.loggedPortions)
            .insert(
              LoggedPortionsCompanion.insert(
                foodId: const Value(42),
                logTimestamp: 3000, // newer than the previous test's entry
                grams: 500,
                unit: 'cup', // not in makeFood()'s servings
                quantity: 2,
              ),
            );

        final food = makeFood(); // id=42, servings: piece, g

        when(mockSearchProvider.isBarcodeSearch).thenReturn(true);
        when(mockSearchProvider.searchResults).thenReturn([food]);
        when(mockSearchProvider.lastScannedBarcode).thenReturn('last-logged-2');

        await tester.pumpWidget(buildWidget());
        await tester.pumpAndSettle();

        final editScreen = tester.widget<QuantityEditScreen>(
          find.byType(QuantityEditScreen),
        );
        // Falls back to food.servings.first (piece, quantity 1.0)
        expect(editScreen.config.initialUnit, 'piece');
        expect(editScreen.config.initialQuantity, 1.0);
      },
    );
  });
}
