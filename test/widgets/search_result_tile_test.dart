import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/models/food_portion.dart' as model_portion;
import 'package:meal_of_record/models/food_serving.dart' as model_unit;
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/widgets/search_result_tile.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:drift/native.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart';
import 'package:meal_of_record/services/reference_database.dart';

import 'search_result_tile_test.mocks.dart';

@GenerateMocks([LogProvider, GoalsProvider])
void main() {
  setUpAll(() async {
    // Initialize DatabaseService with in-memory databases for testing
    final liveDb = LiveDatabase(connection: NativeDatabase.memory());
    final refDb = ReferenceDatabase(connection: NativeDatabase.memory());
    DatabaseService.initSingletonForTesting(liveDb, refDb);
  });

  group('SearchResultTile', () {
    late MockGoalsProvider mockGoalsProvider;

    setUp(() {
      mockGoalsProvider = MockGoalsProvider();
      when(mockGoalsProvider.useNetCarbs).thenReturn(false);
    });

    testWidgets('displays food name and nutritional info with unit dropdown', (
      tester,
    ) async {
      final mockUnits = [
        model_unit.FoodServing(
          id: 1,
          foodId: 1,
          unit: 'g',
          grams: 1.0,
          quantity: 1.0,
        ),
        model_unit.FoodServing(
          id: 2,
          foodId: 1,
          unit: '1 medium',
          grams: 182.0,
          quantity: 1.0,
        ),
        model_unit.FoodServing(
          id: 3,
          foodId: 1,
          unit: '1 cup sliced',
          grams: 109.0,
          quantity: 1.0,
        ),
      ];
      final food = model.Food(
        id: 1,
        name: 'Apple',
        emoji: '🍎',
        calories: 0.52, // per gram
        protein: 0.003, // per gram
        fat: 0.002, // per gram
        carbs: 0.14, // per gram
        fiber: 0.024, // per gram
        source: 'test',
        servings: mockUnits,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<GoalsProvider>.value(
          value: mockGoalsProvider,
          child: MaterialApp(
            home: Scaffold(
              body: SearchResultTile(food: food, onTap: (_) {}),
            ),
          ),
        ),
      );

      // Verify food name is displayed
      expect(find.text('Apple'), findsOneWidget);
      // Verify emoji is displayed separately
      expect(find.text('🍎'), findsOneWidget);

      // Default is now the first non-'g' serving ('1 medium', 182g)
      // Calories: 0.52 * 182 = 94.64
      // Protein: 0.003 * 182 = 0.546
      // Fat: 0.002 * 182 = 0.364
      // Carbs: 0.14 * 182 = 25.48
      // Fiber: 0.024 * 182 = 4.368
      expect(find.text('95🔥 • 1P • 0F • 25C • 4Fb'), findsOneWidget);

      // Select '1 cup sliced' unit - dropdown items include grams in parentheses
      await tester.tap(find.byType(DropdownButton<model_unit.FoodServing>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('1 cup sliced').last);
      await tester.pumpAndSettle();

      // Verify nutritional info updates for '1 cup sliced' (109g)
      // Calories: 0.52 * 109 = 56.68
      // Protein: 0.003 * 109 = 0.327
      // Fat: 0.002 * 109 = 0.218
      // Carbs: 0.14 * 109 = 15.26
      // Fiber: 0.024 * 109 = 2.616
      expect(find.text('57🔥 • 0P • 0F • 15C • 3Fb'), findsOneWidget);

      // Select 'g' unit to verify 1g calculation
      await tester.tap(find.byType(DropdownButton<model_unit.FoodServing>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(' g').last);
      await tester.pumpAndSettle();

      // Verify nutritional info for 1g
      // Calories: 0.52 * 1 = 0.52
      expect(find.text('1🔥 • 0P • 0F • 0C • 0Fb'), findsOneWidget);
    });

    testWidgets(
      'should have an add button that adds the food to the log queue',
      (tester) async {
        final mockLogProvider = MockLogProvider();
        final mockUnits = [
          model_unit.FoodServing(
            id: 1,
            foodId: 1,
            unit: 'g',
            grams: 100.0, // Use non-1.0 value to verify fix
            quantity: 100.0,
          ),
        ];
        final food = model.Food(
          id: 1,
          name: 'Apple',
          emoji: '🍎',
          calories: 0.52,
          protein: 0.003,
          fat: 0.002,
          carbs: 0.14,
          fiber: 0.024,
          source: 'test',
          servings: mockUnits,
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
              ChangeNotifierProvider<GoalsProvider>.value(
                value: mockGoalsProvider,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SearchResultTile(food: food, onTap: (_) {}),
              ),
            ),
          ),
        );

        // Verify the add button exists
        expect(find.byIcon(Icons.add), findsOneWidget);

        // Tap the add button
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        // Verify that addFoodToQueue was called with the correct FoodServing
        verify(
          mockLogProvider.addFoodToQueue(
            argThat(
              isA<model_portion.FoodPortion>().having(
                (p) => p.grams,
                'grams',
                100.0,
              ),
            ),
          ),
        ).called(1);
      },
    );
    testWidgets('renders correctly when food has no servings', (tester) async {
      final food = model.Food(
        id: 1,
        name: 'Apple',
        emoji: '🍎',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.024,
        source: 'test',
        servings: [
          model_unit.FoodServing(
            foodId: 1,
            unit: 'g',
            grams: 1.0,
            quantity: 1.0,
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<GoalsProvider>.value(
          value: mockGoalsProvider,
          child: MaterialApp(
            home: Scaffold(
              body: SearchResultTile(food: food, onTap: (_) {}),
            ),
          ),
        ),
      );

      // Verify food name is displayed
      expect(find.text('Apple'), findsOneWidget);
      // Verify emoji is displayed separately (via leading widget)
      expect(find.text('🍎'), findsOneWidget);

      // Verify nutritional info (should be for 1g by default)
      expect(find.text('1🔥 • 0P • 0F • 0C • 0Fb'), findsOneWidget);

      // Verify dropdown IS displayed (it should auto-add 'g')
      expect(
        find.byType(DropdownButton<model_unit.FoodServing>),
        findsOneWidget,
      );

      // Verify 'g' is the selected unit
      expect(find.text('1.0 g'), findsOneWidget);
    });

    testWidgets('resets serving state when reused for a different OFF result', (
      tester,
    ) async {
      final firstFood = model.Food(
        id: 0,
        name: 'First OFF food',
        calories: 1,
        protein: 0,
        fat: 0,
        carbs: 0,
        fiber: 0,
        source: 'off',
        sourceBarcode: '111',
        servings: [
          model_unit.FoodServing(foodId: 0, unit: 'g', grams: 1, quantity: 1),
          model_unit.FoodServing(
            foodId: 0,
            unit: 'bottle',
            grams: 500,
            quantity: 1,
          ),
        ],
      );
      final secondFood = model.Food(
        id: 0,
        name: 'Second OFF food',
        calories: 2,
        protein: 0,
        fat: 0,
        carbs: 0,
        fiber: 0,
        source: 'off',
        sourceBarcode: '222',
        servings: [
          model_unit.FoodServing(foodId: 0, unit: 'g', grams: 1, quantity: 1),
          model_unit.FoodServing(
            foodId: 0,
            unit: 'bar',
            grams: 42,
            quantity: 1,
          ),
        ],
      );
      model_unit.FoodServing? tappedServing;

      Widget buildTile(model.Food food) {
        return ChangeNotifierProvider<GoalsProvider>.value(
          value: mockGoalsProvider,
          child: MaterialApp(
            home: Scaffold(
              body: SearchResultTile(
                key: const ValueKey('reused-list-position'),
                food: food,
                onTap: (serving) => tappedServing = serving,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTile(firstFood));
      expect(find.textContaining('bottle'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<model_unit.FoodServing>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(' g').last);
      await tester.pumpAndSettle();

      await tester.pumpWidget(buildTile(secondFood));
      await tester.pump();

      expect(find.text('Second OFF food'), findsOneWidget);
      expect(find.textContaining('bar'), findsOneWidget);
      expect(find.textContaining('bottle'), findsNothing);

      await tester.tap(find.byType(ListTile));
      expect(tappedServing?.unit, 'bar');
      expect(tappedServing?.grams, 42);
    });

    testWidgets('displays note and isUpdate icon correctly', (tester) async {
      final food = model.Food(
        id: 1,
        name: 'Apple',
        calories: 0.52,
        protein: 0.003,
        fat: 0.002,
        carbs: 0.14,
        fiber: 0.024,
        source: 'test',
        servings: [
          model_unit.FoodServing(
            foodId: 1,
            unit: 'g',
            grams: 1.0,
            quantity: 1.0,
          ),
        ],
      );

      // Test with isUpdate = true and a note
      await tester.pumpWidget(
        ChangeNotifierProvider<GoalsProvider>.value(
          value: mockGoalsProvider,
          child: MaterialApp(
            home: Scaffold(
              body: SearchResultTile(
                food: food,
                onTap: (_) {},
                isUpdate: true,
                note: 'Logged',
              ),
            ),
          ),
        ),
      );

      // Verify note is displayed
      expect(find.text('Logged'), findsOneWidget);

      // Verify edit icon is shown instead of add icon
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);

      // Test with isUpdate = false and another note
      await tester.pumpWidget(
        ChangeNotifierProvider<GoalsProvider>.value(
          value: mockGoalsProvider,
          child: MaterialApp(
            home: Scaffold(
              body: SearchResultTile(
                food: food,
                onTap: (_) {},
                isUpdate: false,
                note: 'Only Dumpable',
              ),
            ),
          ),
        ),
      );

      // Verify note is displayed
      expect(find.text('Only Dumpable'), findsOneWidget);

      // Verify add icon is shown
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
    });
  });
}
