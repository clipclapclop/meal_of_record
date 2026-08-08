import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/screens/navigation_container_screen.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/providers/weight_provider.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/models/goal_settings.dart';
import 'package:meal_of_record/models/search_mode.dart';
import 'package:meal_of_record/models/daily_macro_stats.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'overview_screen_test.mocks.dart';

void main() {
  late MockGoalsProvider mockGoalsProvider;
  late MockNavigationProvider mockNavigationProvider;
  late MockLogProvider mockLogProvider;
  late MockSearchProvider mockSearchProvider;
  late MockWeightProvider mockWeightProvider;

  setUp(() {
    mockGoalsProvider = MockGoalsProvider();
    mockNavigationProvider = MockNavigationProvider();
    mockLogProvider = MockLogProvider();
    mockSearchProvider = MockSearchProvider();
    mockWeightProvider = MockWeightProvider();

    // Default stubs
    when(mockNavigationProvider.selectedIndex).thenReturn(0);
    when(mockNavigationProvider.changeTab(any)).thenReturn(null);
    when(mockNavigationProvider.showConsumed).thenReturn(true);
    when(mockNavigationProvider.weightRangeDays).thenReturn(7);
    when(mockNavigationProvider.weightRangeLabel).thenReturn('1 wk');

    when(mockGoalsProvider.showUpdateNotification).thenReturn(false);
    when(mockGoalsProvider.isGoalsSet).thenReturn(true);
    when(mockGoalsProvider.hasSeenWelcome).thenReturn(false);
    when(mockGoalsProvider.isLoading).thenReturn(false);
    when(mockGoalsProvider.currentGoals).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.settings).thenReturn(GoalSettings.defaultSettings());
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);

    // Stub WeightProvider
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

    // Stub SearchProvider
    when(mockSearchProvider.errorMessage).thenReturn(null);
    when(mockSearchProvider.isLoading).thenReturn(false);
    when(mockSearchProvider.searchResults).thenReturn([]);
    when(mockSearchProvider.searchMode).thenReturn(SearchMode.text);
  });

  Widget createWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ChangeNotifierProvider<NavigationProvider>.value(
          value: mockNavigationProvider,
        ),
        ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
        ChangeNotifierProvider<SearchProvider>.value(value: mockSearchProvider),
        ChangeNotifierProvider<WeightProvider>.value(value: mockWeightProvider),
      ],
      child: MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name == AppRouter.goalSettingsRoute) {
            return MaterialPageRoute(
              builder: (_) =>
                  const Scaffold(body: Text('Goal Settings Screen')),
            );
          }
          if (settings.name == AppRouter.dataManagementRoute) {
            return MaterialPageRoute(
              builder: (_) =>
                  const Scaffold(body: Text('Data Management Screen')),
            );
          }
          return null;
        },
        home: const NavigationContainerScreen(),
      ),
    );
  }

  testWidgets(
    'shows welcome dialog with three options when goals are not set',
    (tester) async {
      when(mockGoalsProvider.isGoalsSet).thenReturn(false);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Stay on Overview'), findsOneWidget);
      expect(find.text('Restore from Backup'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Set up Goals'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('navigates to goal settings when Set up Goals is pressed', (
    tester,
  ) async {
    when(mockGoalsProvider.isGoalsSet).thenReturn(false);

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    final setupButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Set up Goals'),
    );
    await tester.tap(setupButton);
    await tester.pumpAndSettle();

    expect(find.text('Goal Settings Screen'), findsOneWidget);
  });

  testWidgets(
    'navigates to data management when Restore from Backup is pressed',
    (tester) async {
      when(mockGoalsProvider.isGoalsSet).thenReturn(false);

      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restore from Backup'));
      await tester.pumpAndSettle();

      expect(find.text('Data Management Screen'), findsOneWidget);
    },
  );

  testWidgets('shows update dialog when showUpdateNotification is true', (
    tester,
  ) async {
    when(mockGoalsProvider.isGoalsSet).thenReturn(true);
    when(mockGoalsProvider.showUpdateNotification).thenReturn(true);
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    expect(find.text('Weekly Goal Update'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    verify(mockGoalsProvider.dismissNotification()).called(1);
    expect(find.text('Weekly Goal Update'), findsNothing);
  });
}
