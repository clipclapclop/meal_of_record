import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:meal_of_record/widgets/horizontal_mini_bar_chart.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'quantity_edit_remaining_test.mocks.dart';

@GenerateMocks([LogProvider, RecipeProvider, GoalsProvider, NavigationProvider])
void main() {
  late MockLogProvider mockLogProvider;
  late MockRecipeProvider mockRecipeProvider;
  late MockGoalsProvider mockGoalsProvider;
  late MockNavigationProvider mockNavigationProvider;

  final mockFood = Food(
    id: 1,
    source: 'USDA',
    name: 'Apple',
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
    mockGoalsProvider = MockGoalsProvider();
    mockNavigationProvider = MockNavigationProvider();

    // Logged: 1500, Goal: 2000 => Remaining: 500
    when(mockLogProvider.loggedCalories).thenReturn(1500.0);
    when(mockLogProvider.loggedProtein).thenReturn(100.0);
    when(mockLogProvider.loggedFat).thenReturn(50.0);
    when(mockLogProvider.loggedCarbs).thenReturn(200.0);
    when(mockLogProvider.loggedFiber).thenReturn(20.0);

    // Current totals (doesn't matter much for this test, but just in case)
    when(mockLogProvider.totalCalories).thenReturn(1500.0);
    when(mockLogProvider.totalProtein).thenReturn(100.0);
    when(mockLogProvider.totalFat).thenReturn(50.0);
    when(mockLogProvider.totalCarbs).thenReturn(200.0);
    when(mockLogProvider.totalFiber).thenReturn(20.0);

    when(mockGoalsProvider.currentGoals).thenReturn(
      MacroGoals(
        calories: 2000.0,
        protein: 150.0,
        fat: 70.0,
        carbs: 300.0,
        fiber: 30.0,
      ),
    );
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);

    when(mockRecipeProvider.totalCalories).thenReturn(0.0);
    when(mockRecipeProvider.totalProtein).thenReturn(0.0);
    when(mockRecipeProvider.totalFat).thenReturn(0.0);
    when(mockRecipeProvider.totalCarbs).thenReturn(0.0);
    when(mockRecipeProvider.totalFiber).thenReturn(0.0);
    when(mockRecipeProvider.servingsCreated).thenReturn(1.0);
  });

  Widget createTestWidget(QuantityEditConfig config) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
        ChangeNotifierProvider<RecipeProvider>.value(value: mockRecipeProvider),
        ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ChangeNotifierProvider<NavigationProvider>.value(
          value: mockNavigationProvider,
        ),
      ],
      child: MaterialApp(home: QuantityEditScreen(config: config)),
    );
  }

  testWidgets('Uses daily goals as target when showConsumed is true', (
    tester,
  ) async {
    when(mockNavigationProvider.showConsumed).thenReturn(true);

    final config = QuantityEditConfig(
      context: QuantityEditContext.day,
      food: mockFood,
      initialUnit: 'g',
      initialQuantity: 100.0,
    );

    await tester.pumpWidget(createTestWidget(config));
    await tester.pumpAndSettle();

    final charts = tester.widgetList<HorizontalMiniBarChart>(
      find.byType(HorizontalMiniBarChart),
    );

    // Day's Macros Calories
    final dayChart = charts.first;
    expect(dayChart.target, 2000.0);

    // Portion's Macros Calories
    final portionChart = charts.skip(5).first;
    expect(portionChart.target, 2000.0);
  });

  testWidgets(
    'Uses remaining budget as target for portion when showConsumed is false',
    (tester) async {
      when(mockNavigationProvider.showConsumed).thenReturn(false);

      final config = QuantityEditConfig(
        context: QuantityEditContext.day,
        food: mockFood,
        initialUnit: 'g',
        initialQuantity: 100.0,
      );

      await tester.pumpWidget(createTestWidget(config));
      await tester.pumpAndSettle();

      final charts = tester.widgetList<HorizontalMiniBarChart>(
        find.byType(HorizontalMiniBarChart),
      );

      // Day's Macros Calories Chart should still use daily goal for context
      final dayChart = charts.first;
      expect(dayChart.target, 2000.0);

      // Portion's Macros Calories Chart should use remaining budget (2000 - 1500 = 500)
      final portionChart = charts.skip(5).first;
      expect(portionChart.target, 500.0);

      // Portion's Macros Protein Chart should use remaining budget (150 - 100 = 50)
      final portionProteinChart = charts.skip(6).first;
      expect(portionProteinChart.target, 50.0);
    },
  );
}
