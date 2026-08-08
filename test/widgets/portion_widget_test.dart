import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/widgets/portion_widget.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'portion_widget_test.mocks.dart';

@GenerateMocks([GoalsProvider])
void main() {
  late MockGoalsProvider mockGoalsProvider;

  setUp(() {
    mockGoalsProvider = MockGoalsProvider();
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);
  });

  testWidgets('Serving widget displays correctly', (WidgetTester tester) async {
    // Given
    final food = Food(
      id: 1,
      name: 'Apple',
      emoji: '🍎',
      calories: 0.52, // 52 kcal per 100g
      protein: 0.003, // 0.3g per 100g
      fat: 0.002, // 0.2g per 100g
      carbs: 0.14, // 14g per 100g
      fiber: 0.024, // 2.4g per 100g
      source: 'test',
      servings: [FoodServing(foodId: 1, quantity: 1.0, unit: 'g', grams: 1.0)],
    );
    final serving = FoodPortion(food: food, grams: 100, unit: 'g');

    // When
    await tester.pumpWidget(
      ChangeNotifierProvider<GoalsProvider>.value(
        value: mockGoalsProvider,
        child: MaterialApp(
          home: Scaffold(body: PortionWidget(portion: serving)),
        ),
      ),
    );

    // Then
    expect(find.text('🍎'), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('52🔥 • 0P • 0F • 14C • 2Fb'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });
}
