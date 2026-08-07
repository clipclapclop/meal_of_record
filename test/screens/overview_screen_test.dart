import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/screens/overview_screen.dart';
import 'package:meal_of_record/models/daily_macro_stats.dart';
import 'package:meal_of_record/widgets/nutrition_targets_overview_chart.dart';
import 'package:meal_of_record/widgets/search_ribbon.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:meal_of_record/providers/weight_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/models/goal_settings.dart';
import 'package:meal_of_record/models/search_mode.dart';
import 'overview_screen_test.mocks.dart';

@GenerateMocks([
  LogProvider,
  NavigationProvider,
  SearchProvider,
  GoalsProvider,
  WeightProvider,
])
void main() {
  late MockLogProvider mockLogProvider;
  late MockNavigationProvider mockNavigationProvider;
  late MockSearchProvider mockSearchProvider;
  late MockGoalsProvider mockGoalsProvider;
  late MockWeightProvider mockWeightProvider;

  setUp(() {
    mockLogProvider = MockLogProvider();
    mockNavigationProvider = MockNavigationProvider();
    mockSearchProvider = MockSearchProvider();
    mockGoalsProvider = MockGoalsProvider();
    mockWeightProvider = MockWeightProvider();

    when(mockWeightProvider.recentWeights).thenReturn([]);
    when(mockWeightProvider.weights).thenReturn([]);
    when(mockWeightProvider.loadWeights(any, any)).thenAnswer((_) async {});

    // Stub LogProvider
    when(mockLogProvider.totalCalories).thenReturn(0.0);
    when(mockLogProvider.totalProtein).thenReturn(0.0);
    when(mockLogProvider.totalFat).thenReturn(0.0);
    when(mockLogProvider.totalCarbs).thenReturn(0.0);
    when(mockLogProvider.totalFiber).thenReturn(0.0);
    when(mockLogProvider.queuedCalories).thenReturn(0.0);
    when(mockLogProvider.queuedProtein).thenReturn(0.0);
    when(mockLogProvider.queuedFat).thenReturn(0.0);
    when(mockLogProvider.queuedCarbs).thenReturn(0.0);
    when(mockLogProvider.queuedFiber).thenReturn(0.0);
    when(mockLogProvider.isFasted).thenReturn(false);
    when(mockLogProvider.currentDate).thenReturn(DateTime(2024, 1, 15));
    when(mockLogProvider.getDailyMacroStats(any, any)).thenAnswer(
      (_) async => List.generate(
        7,
        (index) => DailyMacroStats(
          date: DateTime.now().subtract(Duration(days: 6 - index)),
        ),
      ),
    );
    when(mockLogProvider.getTodayStats()).thenAnswer(
      (_) async => DailyMacroStats(
        date: DateTime.now(),
        calories: 0,
        protein: 0,
        fat: 0,
        carbs: 0,
        fiber: 0,
      ),
    );

    // Stub NavigationProvider
    when(mockNavigationProvider.changeTab(any)).thenAnswer((_) {});
    when(mockNavigationProvider.showConsumed).thenReturn(true);
    when(mockNavigationProvider.weightRangeDays).thenReturn(7);
    when(mockNavigationProvider.weightRangeLabel).thenReturn('1 wk');

    // Stub SearchProvider
    when(mockSearchProvider.errorMessage).thenReturn(null);
    when(mockSearchProvider.isLoading).thenReturn(false);
    when(mockSearchProvider.searchResults).thenReturn([]);
    when(mockSearchProvider.searchMode).thenReturn(SearchMode.text);

    // Stub GoalsProvider
    when(mockGoalsProvider.currentGoals).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.settings).thenReturn(GoalSettings.defaultSettings());
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.hasSeenWelcome).thenReturn(true);
    when(mockGoalsProvider.isGoalsSet).thenReturn(true);
    when(mockGoalsProvider.showUpdateNotification).thenReturn(false);
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);
  });

  Widget createTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
        ChangeNotifierProvider<NavigationProvider>.value(
          value: mockNavigationProvider,
        ),
        ChangeNotifierProvider<SearchProvider>.value(value: mockSearchProvider),
        ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ChangeNotifierProvider<WeightProvider>.value(value: mockWeightProvider),
      ],
      child: const MaterialApp(home: OverviewScreen()),
    );
  }

  group('OverviewScreen', () {
    testWidgets('renders NutritionTargetsOverviewChart and FoodActionButtons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(NutritionTargetsOverviewChart), findsOneWidget);
      expect(find.byType(SearchRibbon), findsOneWidget);
    });

    testWidgets('shows warning banner when goals are not set', (tester) async {
      when(mockGoalsProvider.isGoalsSet).thenReturn(false);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text(
          'Goals not set. Nutrient targets and trends may not be accurate.',
        ),
        findsOneWidget,
      );
      expect(find.text('Set up Goals'), findsOneWidget);
    });

    testWidgets('hides warning banner when goals are set', (tester) async {
      when(mockGoalsProvider.isGoalsSet).thenReturn(true);
      when(mockGoalsProvider.useNetCarbs).thenReturn(false);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text(
          'Goals not set. Nutrient targets and trends may not be accurate.',
        ),
        findsNothing,
      );
    });

    testWidgets('does not reload after disposal during data loading', (
      tester,
    ) async {
      final statsCompleter = Completer<List<DailyMacroStats>>();
      when(
        mockLogProvider.getDailyMacroStats(any, any),
      ).thenAnswer((_) => statsCompleter.future);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      statsCompleter.complete([]);
      await tester.pump();

      expect(tester.takeException(), isNull);
      verify(mockLogProvider.getDailyMacroStats(any, any)).called(1);
    });
  });
}
