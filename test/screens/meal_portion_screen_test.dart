import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/models/logged_portion.dart';
import 'package:meal_of_record/models/meal.dart';
import 'package:meal_of_record/screens/meal_portion_screen.dart';

void main() {
  late Meal testMeal;

  final food1 = Food(
    id: 1,
    name: 'Chicken',
    calories: 1.65,
    protein: 0.31,
    fat: 0.036,
    carbs: 0.0,
    fiber: 0.0,
    source: 'test',
    servings: [FoodServing(foodId: 1, unit: 'g', grams: 1.0, quantity: 1.0)],
  );
  final food2 = Food(
    id: 2,
    name: 'Rice',
    calories: 1.30,
    protein: 0.027,
    fat: 0.003,
    carbs: 0.28,
    fiber: 0.004,
    source: 'test',
    servings: [FoodServing(foodId: 2, unit: 'g', grams: 1.0, quantity: 1.0)],
  );

  setUp(() {
    testMeal = Meal(
      timestamp: DateTime(2026, 2, 26, 12, 0),
      loggedPortion: [
        LoggedPortion(
          id: 1,
          portion: FoodPortion(food: food1, grams: 200, unit: 'g'),
          timestamp: DateTime(2026, 2, 26, 12, 0),
        ),
        LoggedPortion(
          id: 2,
          portion: FoodPortion(food: food2, grams: 300, unit: 'g'),
          timestamp: DateTime(2026, 2, 26, 12, 0),
        ),
      ],
    );
  });

  Widget buildWidget() {
    return MaterialApp(home: MealPortionScreen(meal: testMeal));
  }

  testWidgets('renders meal ingredients with correct initial grams', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());

    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.textContaining('500'), findsWidgets); // total weight and input
  });

  testWidgets('entering total grams updates ingredients proportionally', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());

    // Clear the text field and enter 250 (half of 500)
    final textField = find.byType(TextField);
    await tester.enterText(textField, '250');
    await tester.pump();

    // 200g → 100g, 300g → 150g
    expect(find.textContaining('100g'), findsOneWidget);
    expect(find.textContaining('150g'), findsOneWidget);
  });

  testWidgets('Share button is present', (tester) async {
    await tester.pumpWidget(buildWidget());

    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('does not show Add to Queue button', (tester) async {
    await tester.pumpWidget(buildWidget());

    expect(find.text('Add to Queue'), findsNothing);
  });

  testWidgets('zero input shows error on Share', (tester) async {
    await tester.pumpWidget(buildWidget());

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid amount'), findsOneWidget);
  });
}
