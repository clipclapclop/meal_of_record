import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/providers/weight_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/models/goal_settings.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:meal_of_record/screens/recipe_edit_screen.dart';
import 'package:meal_of_record/screens/weight_screen.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/live_database.dart' as live_db;
import 'package:meal_of_record/services/reference_database.dart' as ref_db;
import 'package:drift/native.dart';

import 'package:meal_of_record/providers/navigation_provider.dart';

import 'text_highlight_test.mocks.dart';

@GenerateMocks([
  LogProvider,
  RecipeProvider,
  GoalsProvider,
  WeightProvider,
  NavigationProvider,
])
void main() {
  late MockLogProvider mockLogProvider;
  late MockRecipeProvider mockRecipeProvider;
  late MockGoalsProvider mockGoalsProvider;
  late MockWeightProvider mockWeightProvider;
  late MockNavigationProvider mockNavigationProvider;

  setUpAll(() {
    final liveDb = live_db.LiveDatabase(connection: NativeDatabase.memory());
    final refDb = ref_db.ReferenceDatabase(connection: NativeDatabase.memory());
    DatabaseService.initSingletonForTesting(liveDb, refDb);
  });

  setUp(() {
    mockLogProvider = MockLogProvider();
    mockRecipeProvider = MockRecipeProvider();
    mockGoalsProvider = MockGoalsProvider();
    mockWeightProvider = MockWeightProvider();
    mockNavigationProvider = MockNavigationProvider();

    when(mockNavigationProvider.showConsumed).thenReturn(true);

    when(mockWeightProvider.getWeightForDate(any)).thenReturn(null);
    when(mockWeightProvider.loadWeights(any, any)).thenAnswer((_) async {});

    when(mockLogProvider.totalCalories).thenReturn(500.0);
    when(mockLogProvider.totalProtein).thenReturn(20.0);
    when(mockLogProvider.totalFat).thenReturn(10.0);
    when(mockLogProvider.totalCarbs).thenReturn(80.0);
    when(mockLogProvider.totalFiber).thenReturn(5.0);

    when(mockRecipeProvider.id).thenReturn(0);
    when(mockRecipeProvider.totalCalories).thenReturn(0.0);
    when(mockRecipeProvider.totalProtein).thenReturn(0.0);
    when(mockRecipeProvider.totalFat).thenReturn(0.0);
    when(mockRecipeProvider.totalCarbs).thenReturn(0.0);
    when(mockRecipeProvider.totalFiber).thenReturn(0.0);
    when(mockRecipeProvider.servingsCreated).thenReturn(1.0);
    when(mockRecipeProvider.name).thenReturn('');
    when(mockRecipeProvider.items).thenReturn([]);
    when(mockRecipeProvider.selectedCategories).thenReturn([]);
    when(mockRecipeProvider.portionName).thenReturn('Portion');
    when(mockRecipeProvider.finalWeightGrams).thenReturn(null);
    when(mockRecipeProvider.notes).thenReturn('');
    when(mockRecipeProvider.link).thenReturn('');
    when(mockRecipeProvider.isTemplate).thenReturn(false);
    when(mockRecipeProvider.caloriesPerPortion).thenReturn(0.0);
    when(mockRecipeProvider.emoji).thenReturn('🍴');
    when(mockRecipeProvider.thumbnail).thenReturn(null);

    when(mockGoalsProvider.currentGoals).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.settings).thenReturn(GoalSettings.defaultSettings());
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);
  });

  Widget wrapWithProviders(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
        ChangeNotifierProvider<RecipeProvider>.value(value: mockRecipeProvider),
        ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ChangeNotifierProvider<WeightProvider>.value(value: mockWeightProvider),
        ChangeNotifierProvider<NavigationProvider>.value(
          value: mockNavigationProvider,
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('QuantityEditScreen Text Highlight', () {
    testWidgets('Amount field highlights text on tap', (tester) async {
      final config = QuantityEditConfig(
        context: QuantityEditContext.day,
        food: Food(
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
          ],
        ),
        initialUnit: 'g',
        initialQuantity: 100.0,
      );

      await tester.pumpWidget(
        wrapWithProviders(QuantityEditScreen(config: config)),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField).first;

      await tester.tap(textFieldFinder);
      await tester.pumpAndSettle();

      final TextField textField = tester.widget(textFieldFinder);
      final controller = textField.controller!;
      expect(controller.selection.start, 0);
      expect(controller.selection.end, controller.text.length);
    });
  });

  group('RecipeEditScreen Text Highlight', () {
    testWidgets('Portions Count highlights text on tap', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const RecipeEditScreen()));
      await tester.pumpAndSettle();

      // Portions Count might be the 2nd TextField if name is first
      final textFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Portions Count',
      );

      await tester.ensureVisible(textFieldFinder);
      await tester.tap(textFieldFinder);
      await tester.pumpAndSettle();

      final TextField textField = tester.widget(textFieldFinder);
      final controller = textField.controller!;
      expect(controller.selection.start, 0);
      expect(controller.selection.end, controller.text.length);
    });

    testWidgets('Final Weight highlights text on tap', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const RecipeEditScreen()));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Final Weight (g)',
      );

      await tester.ensureVisible(textFieldFinder);
      await tester.pumpAndSettle();

      final TextField textFieldBefore = tester.widget(textFieldFinder);
      textFieldBefore.controller!.text = '500';

      await tester.tap(textFieldFinder);
      await tester.pumpAndSettle();

      final TextField textFieldAfter = tester.widget(textFieldFinder);
      final controller = textFieldAfter.controller!;
      expect(controller.selection.start, 0);
      expect(controller.selection.end, controller.text.length);
    });
  });

  group('WeightScreen Text Highlight', () {
    testWidgets('Weight field highlights text on tap', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const WeightScreen()));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);

      final TextField textFieldBefore = tester.widget(textFieldFinder);
      textFieldBefore.controller!.text = '70.5';

      await tester.tap(textFieldFinder);
      await tester.pumpAndSettle();

      final TextField textFieldAfter = tester.widget(textFieldFinder);
      final controller = textFieldAfter.controller!;
      expect(controller.selection.start, 0);
      expect(controller.selection.end, controller.text.length);
    });
  });
}
