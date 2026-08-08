import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/widgets/horizontal_mini_bar_chart.dart';

void main() {
  testWidgets('HorizontalMiniBarChart renders correctly', (
    WidgetTester tester,
  ) async {
    const consumed = 50.0;
    const target = 100.0;
    const macroLabel = 'P';
    const unitLabel = 'g';
    const color = Colors.blue;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizontalMiniBarChart(
            consumed: consumed,
            target: target,
            color: color,
            macroLabel: macroLabel,
            unitLabel: unitLabel,
            showConsumed: true,
          ),
        ),
      ),
    );

    expect(find.text('P 50 / 100g'), findsOneWidget);
  });

  testWidgets('HorizontalMiniBarChart renders inverted correctly', (
    WidgetTester tester,
  ) async {
    const consumed = 30.0;
    const target = 100.0;
    const macroLabel = 'P';
    const unitLabel = 'g';
    const color = Colors.blue;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizontalMiniBarChart(
            consumed: consumed,
            target: target,
            color: color,
            macroLabel: macroLabel,
            unitLabel: unitLabel,
            showConsumed: false,
          ),
        ),
      ),
    );

    // Inverted: 100 - 30 = 70
    expect(find.text('P 70 / 100g'), findsOneWidget);
  });

  testWidgets('Negative remaining when consumed > target', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizontalMiniBarChart(
            consumed: 120.0,
            target: 100.0,
            color: Colors.blue,
            macroLabel: 'P',
            unitLabel: 'g',
            showConsumed: false,
          ),
        ),
      ),
    );

    // Remaining: 100 - 120 = -20
    expect(find.text('P -20 / 100g'), findsOneWidget);
  });

  testWidgets('Zero target shows 0 / 0 and no crash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizontalMiniBarChart(
            consumed: 50.0,
            target: 0.0,
            color: Colors.blue,
            macroLabel: 'P',
            unitLabel: 'g',
            showConsumed: true,
          ),
        ),
      ),
    );

    expect(find.text('P 50 / 0g'), findsOneWidget);
  });

  testWidgets('Negative target shows correctly and no crash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizontalMiniBarChart(
            consumed: 50.0,
            target: -50.0,
            color: Colors.blue,
            macroLabel: 'P',
            unitLabel: 'g',
            showConsumed: true,
          ),
        ),
      ),
    );

    expect(find.text('P 50 / -50g'), findsOneWidget);
  });

  testWidgets('Over 100% consumed bar capped at 115%', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizontalMiniBarChart(
            consumed: 110.0,
            target: 100.0,
            color: Colors.blue,
            macroLabel: 'P',
            unitLabel: 'g',
            showConsumed: true,
          ),
        ),
      ),
    );

    expect(find.text('P 110 / 100g'), findsOneWidget);
  });

  testWidgets('Zero consumed shows 0', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizontalMiniBarChart(
            consumed: 0.0,
            target: 100.0,
            color: Colors.blue,
            macroLabel: 'P',
            unitLabel: 'g',
            showConsumed: true,
          ),
        ),
      ),
    );

    expect(find.text('P 0 / 100g'), findsOneWidget);
  });

  testWidgets('Calories label uses fire emoji and no unit label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizontalMiniBarChart(
            consumed: 500.0,
            target: 2000.0,
            color: Colors.blue,
            macroLabel: '🔥',
            unitLabel: '',
            showConsumed: true,
          ),
        ),
      ),
    );

    expect(find.text('🔥 500 / 2000'), findsOneWidget);
  });
}
