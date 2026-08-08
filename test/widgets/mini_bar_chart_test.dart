import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/widgets/vertical_mini_bar_chart.dart';

void main() {
  group('MiniBarChart', () {
    testWidgets('renders correctly with given consumed and target', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: VerticalMiniBarChart(
              consumed: 50,
              target: 100,
              color: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.byType(VerticalMiniBarChart), findsOneWidget);
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('painter has correct properties when showConsumed is true', (
      WidgetTester tester,
    ) async {
      const consumed = 50.0;
      const target = 100.0;
      const color = Colors.blue;

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: VerticalMiniBarChart(
              consumed: consumed,
              target: target,
              color: color,
              showConsumed: true,
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as VerticalMiniBarChartPainter;

      expect(painter.value, consumed);
      expect(painter.maxValue, target);
      expect(painter.color, color);
    });

    testWidgets('painter has inverted value when showConsumed is false', (
      WidgetTester tester,
    ) async {
      const consumed = 30.0;
      const target = 100.0;
      const color = Colors.blue;

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: VerticalMiniBarChart(
              consumed: consumed,
              target: target,
              color: color,
              showConsumed: false,
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as VerticalMiniBarChartPainter;

      // Inverted value: target - consumed = 100 - 30 = 70
      expect(painter.value, 70.0);
      expect(painter.maxValue, target);
    });

    testWidgets('bar height is clamped at 0 when display value is negative', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: VerticalMiniBarChart(
              consumed: -10,
              target: 100,
              color: Colors.blue,
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as VerticalMiniBarChartPainter;
      expect(painter.value, -10);
    });

    testWidgets('bar height uses display value when over target', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: VerticalMiniBarChart(
              consumed: 110,
              target: 100,
              color: Colors.blue,
            ),
          ),
        ),
      );
      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as VerticalMiniBarChartPainter;
      expect(painter.value, 110);
    });

    testWidgets('negative remaining when consumed > target in remaining mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: VerticalMiniBarChart(
              consumed: 150,
              target: 100,
              color: Colors.blue,
              showConsumed: false,
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as VerticalMiniBarChartPainter;
      // Remaining: 100 - 150 = -50
      expect(painter.value, -50.0);
    });

    testWidgets('zero target: no crash', (WidgetTester tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: VerticalMiniBarChart(
              consumed: 50,
              target: 0,
              color: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.byType(VerticalMiniBarChart), findsOneWidget);
      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as VerticalMiniBarChartPainter;
      expect(painter.maxValue, 0);
    });
  });
}
