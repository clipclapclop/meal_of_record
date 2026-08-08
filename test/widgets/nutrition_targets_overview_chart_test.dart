import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/widgets/vertical_mini_bar_chart.dart';
import 'package:meal_of_record/widgets/nutrition_targets_overview_chart.dart';
import 'package:meal_of_record/models/nutrition_target.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:provider/provider.dart';

void main() {
  group('NutritionTargetsOverviewChart', () {
    // Wed Feb 4 through Tue Feb 10, 2026 → labels: W, T, F, S, S, M, T
    final List<DateTime> mockDates = List.generate(
      7,
      (i) => DateTime(2026, 2, 4).add(Duration(days: i)),
    );

    final List<NutritionTarget> mockNutritionData = [
      NutritionTarget(
        color: Colors.blue,
        thisAmount: 2134.0,
        targetAmount: 2143.0,
        macroLabel: '🔥',
        unitLabel: '',
        dailyAmounts: [
          1714.4,
          1928.7,
          1821.55,
          2035.85,
          1607.25,
          1714.4,
          2143.0,
        ],
        dailyTargets: [2143.0, 2143.0, 2143.0, 2143.0, 2143.0, 2143.0, 2143.0],
      ),
      NutritionTarget(
        color: Colors.red,
        thisAmount: 159.0,
        targetAmount: 141.0,
        macroLabel: 'P',
        unitLabel: 'g',
        dailyAmounts: [141.0, 126.9, 133.95, 148.05, 119.85, 126.9, 143.82],
        dailyTargets: [141.0, 141.0, 141.0, 141.0, 141.0, 141.0, 141.0],
      ),
      NutritionTarget(
        color: Colors.yellow,
        thisAmount: 70.0,
        targetAmount: 71.0,
        macroLabel: 'F',
        unitLabel: 'g',
        dailyAmounts: [63.9, 71.0, 74.55, 67.45, 56.8, 60.35, 69.58],
        dailyTargets: [71.0, 71.0, 71.0, 71.0, 71.0, 71.0, 71.0],
      ),
      NutritionTarget(
        color: Colors.green,
        thisAmount: 241.0,
        targetAmount: 233.0,
        macroLabel: 'C',
        unitLabel: 'g',
        dailyAmounts: [221.35, 198.05, 209.7, 233.0, 244.65, 186.4, 242.32],
        dailyTargets: [233.0, 233.0, 233.0, 233.0, 233.0, 233.0, 233.0],
      ),
      NutritionTarget(
        color: Colors.brown,
        thisAmount: 25.0,
        targetAmount: 30.0,
        macroLabel: 'Fb',
        unitLabel: 'g',
        dailyAmounts: [22.5, 28.0, 31.5, 25.0, 18.0, 29.0, 26.5],
        dailyTargets: [30.0, 30.0, 30.0, 30.0, 30.0, 30.0, 30.0],
      ),
    ];

    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NutritionTargetsOverviewChart(
              nutritionData: mockNutritionData,
              dates: mockDates,
            ),
          ),
        ),
      );
    }

    testWidgets('renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(NutritionTargetsOverviewChart), findsOneWidget);
    });

    testWidgets('renders 35 mini-bar widgets', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(VerticalMiniBarChart), findsNWidgets(35));
    });

    testWidgets('renders weekday labels matching passed-in dates', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      // Dates are Wed Feb 4 – Tue Feb 10 → W, T, F, S, S, M, T
      expect(find.text('W'), findsOneWidget);
      expect(find.text('T'), findsNWidgets(2)); // Thursday and Tuesday
      expect(find.text('F'), findsOneWidget);
      expect(find.text('S'), findsNWidgets(2)); // Saturday and Sunday
      expect(find.text('M'), findsOneWidget);
    });

    testWidgets(
      'renders formatted nutrient values for selected day (defaults to today/day 6)',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget());

        // Values come from dailyAmounts[6] (today), not thisAmount
        expect(find.text('2143 🔥\n of 2143'), findsOneWidget);
        expect(find.text('143 P\n of 141g'), findsOneWidget);
        expect(find.text('69 F\n of 71g'), findsOneWidget);
        expect(find.text('242 C\n of 233g'), findsOneWidget);
        expect(find.text('26 Fb\n of 30g'), findsOneWidget);
      },
    );

    testWidgets('renders "Consumed" and "Remaining" buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.widgetWithText(TextButton, 'Consumed'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Remaining'), findsOneWidget);
    });

    testWidgets('toggles between Consumed and Remaining views', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      // Initially shows Consumed (from dailyAmounts[6])
      expect(find.text('2143 🔥\n of 2143'), findsOneWidget);
      expect(find.text('143 P\n of 141g'), findsOneWidget);

      // Tap Remaining
      await tester.tap(find.text('Remaining'));
      await tester.pumpAndSettle();

      // Should show Remaining: target - dailyAmounts[6]
      // 2143 - 2143 = 0
      // 141 - 143.82 = -2
      expect(find.text('0 🔥\n of 2143'), findsOneWidget);
      expect(find.text('-2 P\n of 141g'), findsOneWidget);

      // Tap Consumed
      await tester.tap(find.text('Consumed'));
      await tester.pumpAndSettle();

      // Should show Consumed again
      expect(find.text('2143 🔥\n of 2143'), findsOneWidget);
      expect(find.text('143 P\n of 141g'), findsOneWidget);
    });

    testWidgets('tapping a day column updates selection and displayed values', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      // Initially selected is day 6 (today) with values from dailyAmounts[6]
      expect(find.text('2143 🔥\n of 2143'), findsOneWidget);

      // Find and tap the first day column (Monday, index 0)
      // The bars are in GestureDetector widgets
      final gestureDetectors = find.byType(GestureDetector);
      // Tap the first one (Monday's column)
      await tester.tap(gestureDetectors.first);
      await tester.pumpAndSettle();

      // Should now show values from dailyAmounts[0]
      // Calories: 1714.4 -> 1714
      expect(find.text('1714 🔥\n of 2143'), findsOneWidget);
    });
  });
}
