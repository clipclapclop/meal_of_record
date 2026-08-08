import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/widgets/log_queue_top_ribbon.dart';
import 'package:meal_of_record/widgets/horizontal_mini_bar_chart.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'log_queue_top_ribbon_test.mocks.dart';

@GenerateMocks([LogProvider, GoalsProvider, NavigationProvider])
void main() {
  late MockLogProvider mockLogProvider;
  late MockGoalsProvider mockGoalsProvider;
  late MockNavigationProvider mockNavigationProvider;

  void setupMocks({
    double loggedCal = 500.0,
    double loggedProt = 50.0,
    double loggedFat = 20.0,
    double loggedCarbs = 100.0,
    double loggedFiber = 10.0,
    double queuedCal = 200.0,
    double queuedProt = 20.0,
    double queuedFat = 10.0,
    double queuedCarbs = 50.0,
    double queuedFiber = 5.0,
    double goalCal = 2000.0,
    double goalProt = 150.0,
    double goalFat = 70.0,
    double goalCarbs = 300.0,
    double goalFiber = 30.0,
    bool showConsumed = true,
  }) {
    when(mockLogProvider.logQueue).thenReturn([]);
    when(mockLogProvider.loggedCalories).thenReturn(loggedCal);
    when(mockLogProvider.loggedProtein).thenReturn(loggedProt);
    when(mockLogProvider.loggedFat).thenReturn(loggedFat);
    when(mockLogProvider.loggedCarbs).thenReturn(loggedCarbs);
    when(mockLogProvider.loggedFiber).thenReturn(loggedFiber);

    when(mockLogProvider.totalCalories).thenReturn(loggedCal + queuedCal);
    when(mockLogProvider.totalProtein).thenReturn(loggedProt + queuedProt);
    when(mockLogProvider.totalFat).thenReturn(loggedFat + queuedFat);
    when(mockLogProvider.totalCarbs).thenReturn(loggedCarbs + queuedCarbs);
    when(mockLogProvider.totalFiber).thenReturn(loggedFiber + queuedFiber);

    when(mockLogProvider.queuedCalories).thenReturn(queuedCal);
    when(mockLogProvider.queuedProtein).thenReturn(queuedProt);
    when(mockLogProvider.queuedFat).thenReturn(queuedFat);
    when(mockLogProvider.queuedCarbs).thenReturn(queuedCarbs);
    when(mockLogProvider.queuedFiber).thenReturn(queuedFiber);

    when(mockGoalsProvider.currentGoals).thenReturn(
      MacroGoals(
        calories: goalCal,
        protein: goalProt,
        fat: goalFat,
        carbs: goalCarbs,
        fiber: goalFiber,
      ),
    );
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);

    when(mockNavigationProvider.showConsumed).thenReturn(showConsumed);
  }

  setUp(() {
    mockLogProvider = MockLogProvider();
    mockGoalsProvider = MockGoalsProvider();
    mockNavigationProvider = MockNavigationProvider();
  });

  Widget createTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
        ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ChangeNotifierProvider<NavigationProvider>.value(
          value: mockNavigationProvider,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: LogQueueTopRibbon(
              arrowDirection: Icons.arrow_drop_up,
              onArrowPressed: () {},
              logProvider: mockLogProvider,
            ),
          ),
        ),
      ),
    );
  }

  group('Consumed mode', () {
    testWidgets('Day\'s Macros shows total consumed with goal targets', (
      tester,
    ) async {
      setupMocks(showConsumed: true);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final charts = tester
          .widgetList<HorizontalMiniBarChart>(
            find.byType(HorizontalMiniBarChart),
          )
          .toList();

      // Day's Macros (indices 0-4): consumed = total, target = goals
      expect(charts[0].consumed, 700.0); // totalCalories
      expect(charts[0].target, 2000.0); // goal calories
      expect(charts[1].consumed, 70.0); // totalProtein
      expect(charts[1].target, 150.0); // goal protein
      expect(charts[2].consumed, 30.0); // totalFat
      expect(charts[2].target, 70.0); // goal fat
      expect(charts[3].consumed, 150.0); // totalCarbs
      expect(charts[3].target, 300.0); // goal carbs
      expect(charts[4].consumed, 15.0); // totalFiber
      expect(charts[4].target, 30.0); // goal fiber
    });

    testWidgets(
      'Queue\'s Macros shows queued consumed with (goals - logged) targets',
      (tester) async {
        setupMocks(showConsumed: true);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        final charts = tester
            .widgetList<HorizontalMiniBarChart>(
              find.byType(HorizontalMiniBarChart),
            )
            .toList();

        // Queue's Macros (indices 5-9): consumed = queued, target = goals - logged
        expect(charts[5].consumed, 200.0); // queuedCalories
        expect(charts[5].target, 1500.0); // 2000 - 500
        expect(charts[6].consumed, 20.0); // queuedProtein
        expect(charts[6].target, 100.0); // 150 - 50
        expect(charts[7].consumed, 10.0); // queuedFat
        expect(charts[7].target, 50.0); // 70 - 20
        expect(charts[8].consumed, 50.0); // queuedCarbs
        expect(charts[8].target, 200.0); // 300 - 100
        expect(charts[9].consumed, 5.0); // queuedFiber
        expect(charts[9].target, 20.0); // 30 - 10
      },
    );

    testWidgets('All 10 charts have showConsumed=true', (tester) async {
      setupMocks(showConsumed: true);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final charts = tester
          .widgetList<HorizontalMiniBarChart>(
            find.byType(HorizontalMiniBarChart),
          )
          .toList();

      for (int i = 0; i < 10; i++) {
        expect(
          charts[i].showConsumed,
          true,
          reason: "Chart $i should have showConsumed=true",
        );
      }
    });
  });

  group('Remaining mode', () {
    testWidgets('Day\'s Macros shows remaining values', (tester) async {
      setupMocks(showConsumed: false);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final charts = tester
          .widgetList<HorizontalMiniBarChart>(
            find.byType(HorizontalMiniBarChart),
          )
          .toList();

      // Day's Macros: consumed=700, target=2000, showConsumed=false → displayValue=1300
      expect(charts[0].consumed, 700.0);
      expect(charts[0].target, 2000.0);
      expect(charts[0].showConsumed, false);
    });

    testWidgets('Queue\'s Macros shows remaining values', (tester) async {
      setupMocks(showConsumed: false);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final charts = tester
          .widgetList<HorizontalMiniBarChart>(
            find.byType(HorizontalMiniBarChart),
          )
          .toList();

      // Queue's Macros: consumed=200, target=1500, showConsumed=false → displayValue=1300
      expect(charts[5].consumed, 200.0);
      expect(charts[5].target, 1500.0);
      expect(charts[5].showConsumed, false);
    });

    testWidgets('All 10 charts have showConsumed=false', (tester) async {
      setupMocks(showConsumed: false);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final charts = tester
          .widgetList<HorizontalMiniBarChart>(
            find.byType(HorizontalMiniBarChart),
          )
          .toList();

      for (int i = 0; i < 10; i++) {
        expect(
          charts[i].showConsumed,
          false,
          reason: "Chart $i should have showConsumed=false",
        );
      }
    });
  });

  group('Empty queue', () {
    testWidgets(
      'Consumed mode: Day\'s shows logged/goals, Queue\'s shows 0/(goals-logged)',
      (tester) async {
        setupMocks(
          showConsumed: true,
          queuedCal: 0,
          queuedProt: 0,
          queuedFat: 0,
          queuedCarbs: 0,
          queuedFiber: 0,
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        final charts = tester
            .widgetList<HorizontalMiniBarChart>(
              find.byType(HorizontalMiniBarChart),
            )
            .toList();

        // Day's = logged (since queued is 0)
        expect(charts[0].consumed, 500.0); // totalCalories = logged + 0
        expect(charts[0].target, 2000.0);

        // Queue's = 0/(goals-logged)
        expect(charts[5].consumed, 0.0);
        expect(charts[5].target, 1500.0); // 2000 - 500
      },
    );

    testWidgets(
      'Remaining mode: Day\'s shows remaining/goals, Queue\'s shows remaining/remaining',
      (tester) async {
        setupMocks(
          showConsumed: false,
          queuedCal: 0,
          queuedProt: 0,
          queuedFat: 0,
          queuedCarbs: 0,
          queuedFiber: 0,
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        final charts = tester
            .widgetList<HorizontalMiniBarChart>(
              find.byType(HorizontalMiniBarChart),
            )
            .toList();

        // Day's: consumed=500, target=2000, showConsumed=false → displayValue=1500
        expect(charts[0].consumed, 500.0);
        expect(charts[0].target, 2000.0);

        // Queue's: consumed=0, target=1500, showConsumed=false → displayValue=1500
        expect(charts[5].consumed, 0.0);
        expect(charts[5].target, 1500.0);
      },
    );
  });

  group('Over-budget (logged > goals)', () {
    testWidgets('Queue target is negative when logged exceeds goals', (
      tester,
    ) async {
      setupMocks(
        showConsumed: true,
        loggedCal: 2500,
        loggedProt: 200,
        loggedFat: 90,
        loggedCarbs: 400,
        loggedFiber: 40,
        queuedCal: 100,
        queuedProt: 10,
        queuedFat: 5,
        queuedCarbs: 20,
        queuedFiber: 2,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final charts = tester
          .widgetList<HorizontalMiniBarChart>(
            find.byType(HorizontalMiniBarChart),
          )
          .toList();

      // Queue target = goals - logged = 2000 - 2500 = -500
      expect(charts[5].target, -500.0);
      expect(charts[5].consumed, 100.0);
    });

    testWidgets('Remaining mode: Day\'s shows negative remaining', (
      tester,
    ) async {
      setupMocks(
        showConsumed: false,
        loggedCal: 2500,
        loggedProt: 200,
        loggedFat: 90,
        loggedCarbs: 400,
        loggedFiber: 40,
        queuedCal: 100,
        queuedProt: 10,
        queuedFat: 5,
        queuedCarbs: 20,
        queuedFiber: 2,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final charts = tester
          .widgetList<HorizontalMiniBarChart>(
            find.byType(HorizontalMiniBarChart),
          )
          .toList();

      // Day's: consumed=2600, target=2000, showConsumed=false → displayValue = 2000-2600 = -600
      expect(charts[0].consumed, 2600.0);
      expect(charts[0].target, 2000.0);
      expect(charts[0].showConsumed, false);
    });
  });

  group('Text rendering spot-check', () {
    testWidgets('Consumed mode renders correct text for Day\'s calories', (
      tester,
    ) async {
      setupMocks(showConsumed: true);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Day's Macros calories: consumed=700, target=2000
      expect(find.text('🔥 700 / 2000'), findsOneWidget);
    });

    testWidgets('Consumed mode renders correct text for Queue\'s calories', (
      tester,
    ) async {
      setupMocks(showConsumed: true);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Queue's Macros calories: consumed=200, target=1500
      expect(find.text('🔥 200 / 1500'), findsOneWidget);
    });
  });
}
