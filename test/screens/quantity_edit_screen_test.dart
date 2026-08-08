import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'quantity_edit_screen_test.mocks.dart';

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
    servings: [
      FoodServing(foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0),
      FoodServing(foodId: 1, unit: 'piece', grams: 182.0, quantity: 1.0),
    ],
  );

  setUp(() {
    mockLogProvider = MockLogProvider();
    mockRecipeProvider = MockRecipeProvider();
    mockGoalsProvider = MockGoalsProvider();
    mockNavigationProvider = MockNavigationProvider();

    // Default mock behavior for LogProvider
    when(mockLogProvider.totalCalories).thenReturn(500.0);
    when(mockLogProvider.totalProtein).thenReturn(20.0);
    when(mockLogProvider.totalFat).thenReturn(10.0);
    when(mockLogProvider.totalCarbs).thenReturn(80.0);
    when(mockLogProvider.totalFiber).thenReturn(5.0);

    // Default mock behavior for RecipeProvider
    when(mockRecipeProvider.totalCalories).thenReturn(0.0);
    when(mockRecipeProvider.totalProtein).thenReturn(0.0);
    when(mockRecipeProvider.totalFat).thenReturn(0.0);
    when(mockRecipeProvider.totalCarbs).thenReturn(0.0);
    when(mockRecipeProvider.totalFiber).thenReturn(0.0);
    when(mockRecipeProvider.servingsCreated).thenReturn(1.0);

    // Default mock behavior for GoalsProvider
    when(mockGoalsProvider.currentGoals).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);

    // Default mock behavior for NavigationProvider
    when(mockNavigationProvider.showConsumed).thenReturn(true);
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

  testWidgets('Auto-focuses and selects quantity when isUpdate is true', (
    tester,
  ) async {
    final config = QuantityEditConfig(
      context: QuantityEditContext.day,
      food: mockFood,
      initialUnit: 'piece',
      initialQuantity: 1.5,
      isUpdate: true,
    );

    await tester.pumpWidget(createTestWidget(config));
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.focusNode!.hasFocus, true);
    expect(textField.controller!.selection.baseOffset, 0);
    expect(
      textField.controller!.selection.extentOffset,
      textField.controller!.text.length,
    );
  });

  testWidgets('Auto-focuses and selects quantity even when isUpdate is false', (
    tester,
  ) async {
    final config = QuantityEditConfig(
      context: QuantityEditContext.day,
      food: mockFood,
      initialUnit: 'piece',
      initialQuantity: 1.5,
      isUpdate: false,
    );

    await tester.pumpWidget(createTestWidget(config));
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.focusNode!.hasFocus, true);
    expect(textField.controller!.selection.baseOffset, 0);
    expect(
      textField.controller!.selection.extentOffset,
      textField.controller!.text.length,
    );
  });

  testWidgets('Pre-populates amount and unit from config', (tester) async {
    final config = QuantityEditConfig(
      context: QuantityEditContext.day,
      food: mockFood,
      initialUnit: 'piece',
      initialQuantity: 1.5,
    );

    await tester.pumpWidget(createTestWidget(config));

    expect(find.text('1.5'), findsOneWidget);

    final pieceChip = tester.widget<ChoiceChip>(
      find.descendant(
        of: find.byType(Wrap),
        matching: find.widgetWithText(ChoiceChip, 'piece'),
      ),
    );
    expect(pieceChip.selected, true);
  });

  testWidgets('Interactive switching: Selecting macro switches unit to g', (
    tester,
  ) async {
    final config = QuantityEditConfig(
      context: QuantityEditContext.day,
      food: mockFood,
      initialUnit: 'piece',
      initialQuantity: 1.0,
    );

    await tester.pumpWidget(createTestWidget(config));

    // Initially piece is selected
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'piece'))
          .selected,
      true,
    );

    // Click 'Calories' target (ensure it's visible first)
    await tester.ensureVisible(find.text('Calories'));
    await tester.tap(find.text('Calories'));
    await tester.pumpAndSettle();

    // Unit should switch to 'g'
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'g')).selected,
      true,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'piece'))
          .selected,
      false,
    );
  });

  testWidgets(
    'Interactive switching: Selecting unit switches target back to Unit',
    (tester) async {
      final config = QuantityEditConfig(
        context: QuantityEditContext.day,
        food: mockFood,
        initialUnit: 'g',
        initialQuantity: 100.0,
      );

      await tester.pumpWidget(createTestWidget(config));

      // Select 'Calories' target (ensure it's visible first)
      await tester.ensureVisible(find.text('Calories'));
      await tester.tap(find.text('Calories'));
      await tester.pumpAndSettle();

      // Now tap 'piece' unit button
      await tester.tap(find.text('piece'));
      await tester.pumpAndSettle();

      // Target should be back to 'Unit' (index 0)
      final toggleButtons = tester.widget<ToggleButtons>(
        find.byType(ToggleButtons),
      );
      expect(toggleButtons.isSelected[0], true);
      expect(toggleButtons.isSelected[1], false);
    },
  );

  testWidgets('Saves correct grams and unit', (tester) async {
    FoodPortion? result;

    final config = QuantityEditConfig(
      context: QuantityEditContext.day,
      food: mockFood,
      initialUnit: 'piece',
      initialQuantity: 1.0,
    );

    // Push QuantityEditScreen from a test route so we can capture the pop result
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
          ChangeNotifierProvider<RecipeProvider>.value(
            value: mockRecipeProvider,
          ),
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
          ChangeNotifierProvider<NavigationProvider>.value(
            value: mockNavigationProvider,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<FoodPortion>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuantityEditScreen(config: config),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    // Open the QuantityEditScreen
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Change quantity to 2.0
    await tester.enterText(find.byType(TextField), '2.0');
    // Ensure button is visible (it's in a scrollable view and might be off-screen)
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.grams, 364.0); // 2 * 182
    expect(result!.unit, 'piece');
  });
}
