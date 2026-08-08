import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/screens/search_screen.dart';
import 'package:meal_of_record/widgets/search_ribbon.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:provider/provider.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:meal_of_record/models/search_mode.dart';
import 'package:meal_of_record/models/search_config.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'search_ribbon_test.mocks.dart';

@GenerateMocks([LogProvider, NavigationProvider, SearchProvider, GoalsProvider])
void main() {
  late MockLogProvider mockLogProvider;
  late MockNavigationProvider mockNavigationProvider;
  late MockSearchProvider mockSearchProvider;
  late MockGoalsProvider mockGoalsProvider;

  setUp(() {
    provideDummy<Future<void>>(Future.value());
    mockLogProvider = MockLogProvider();
    mockNavigationProvider = MockNavigationProvider();
    mockSearchProvider = MockSearchProvider(); // Use the mock
    mockGoalsProvider = MockGoalsProvider();
    when(mockNavigationProvider.shouldFocusSearch).thenReturn(false);
    when(mockNavigationProvider.resetSearchFocus()).thenReturn(null);
    when(mockNavigationProvider.showConsumed).thenReturn(true);
    when(mockSearchProvider.searchResults).thenReturn([]);
    when(mockSearchProvider.errorMessage).thenReturn(null); // ADDED
    when(mockSearchProvider.isLoading).thenReturn(false); // ADDED
    when(mockSearchProvider.searchMode).thenReturn(SearchMode.text);
    when(mockSearchProvider.isBarcodeSearch).thenReturn(false);
    when(mockSearchProvider.lastScannedBarcode).thenReturn(null);
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
    when(mockLogProvider.loggedCalories).thenReturn(0.0);
    when(mockLogProvider.loggedProtein).thenReturn(0.0);
    when(mockLogProvider.loggedFat).thenReturn(0.0);
    when(mockLogProvider.loggedCarbs).thenReturn(0.0);
    when(mockLogProvider.loggedFiber).thenReturn(0.0);
    when(mockLogProvider.logQueue).thenReturn([]);

    // Default mock for GoalsProvider
    when(mockGoalsProvider.currentGoals).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.useNetCarbs).thenReturn(false);
  });

  Widget createTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
        ChangeNotifierProvider<NavigationProvider>.value(
          value: mockNavigationProvider,
        ),
        ChangeNotifierProvider<SearchProvider>.value(
          value: mockSearchProvider,
        ), // Use the mock
        ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
      ],
      child: MaterialApp(
        navigatorKey: GlobalKey<NavigatorState>(),
        home: const Scaffold(body: SearchRibbon()),
        onGenerateRoute: (settings) {
          if (settings.name == AppRouter.searchRoute) {
            return MaterialPageRoute(
              builder: (_) => MultiProvider(
                // ADDED MultiProvider
                providers: [
                  ChangeNotifierProvider<LogProvider>.value(
                    value: mockLogProvider,
                  ),
                  ChangeNotifierProvider<NavigationProvider>.value(
                    value: mockNavigationProvider,
                  ),
                  ChangeNotifierProvider<SearchProvider>.value(
                    value: mockSearchProvider,
                  ),
                  ChangeNotifierProvider<GoalsProvider>.value(
                    value: mockGoalsProvider,
                  ),
                ],
                child: const SearchScreen(
                  config: SearchConfig(
                    context: QuantityEditContext.day,
                    title: 'Food Search',
                    showQueueStats: true,
                  ),
                ),
              ),
            );
          }
          return null;
        },
      ),
    );
  }

  testWidgets('tapping search bar navigates to food search screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createTestWidget());

    await tester.tap(find.byKey(const Key('food_search_text_field')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
  });

  group('OFF Button', () {
    testWidgets('tapping OFF button calls onOffSearch callback', (
      WidgetTester tester,
    ) async {
      // Arrange
      var offSearchCalled = false;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavigationProvider>.value(
              value: mockNavigationProvider,
            ),
            ChangeNotifierProvider<LogProvider>.value(
              // Added because LogProvider is now required
              value: mockLogProvider,
            ),
            ChangeNotifierProvider<GoalsProvider>.value(
              value: mockGoalsProvider,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SearchRibbon(
                onOffSearch: () {
                  offSearchCalled = true;
                },
              ),
            ),
          ),
        ),
      );

      final offButtonFinder = find.widgetWithIcon(
        ElevatedButton,
        Icons.language,
      );
      expect(offButtonFinder, findsOneWidget);

      // Act
      await tester.tap(offButtonFinder);
      await tester.pump(); // Rebuild the widget after state change

      // Assert
      expect(offSearchCalled, isTrue);
    });
  });

  testWidgets('tapping Log button saves queue and navigates home', (
    WidgetTester tester,
  ) async {
    // Arrange
    when(mockLogProvider.logQueueToDatabase()).thenAnswer((_) async {});

    await tester.pumpWidget(createTestWidget());

    final logButtonFinder = find.widgetWithText(ElevatedButton, 'Log');
    expect(logButtonFinder, findsOneWidget);

    // Act
    await tester.tap(logButtonFinder);
    await tester.pumpAndSettle();

    // Assert
    verify(mockLogProvider.logQueueToDatabase()).called(1);
    verify(mockNavigationProvider.changeTab(0)).called(1);
  });

  group('Auto-switch from food tab to text tab', () {
    Widget createActiveSearchWidget({
      required SearchMode initialMode,
      required ValueChanged<String>? onChanged,
    }) {
      when(mockSearchProvider.searchMode).thenReturn(initialMode);
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationProvider>.value(
            value: mockNavigationProvider,
          ),
          ChangeNotifierProvider<LogProvider>.value(value: mockLogProvider),
          ChangeNotifierProvider<SearchProvider>.value(
            value: mockSearchProvider,
          ),
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SearchRibbon(isSearchActive: true, onChanged: onChanged),
          ),
        ),
      );
    }

    testWidgets('switches from food tab to text tab when user starts typing', (
      WidgetTester tester,
    ) async {
      // Arrange
      String? capturedQuery;
      await tester.pumpWidget(
        createActiveSearchWidget(
          initialMode: SearchMode.food,
          onChanged: (query) {
            capturedQuery = query;
          },
        ),
      );

      // Act
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();

      // Assert
      verify(mockSearchProvider.setSearchMode(SearchMode.text)).called(1);
      expect(capturedQuery, 'apple');
    });

    testWidgets('does not switch mode when already on text tab', (
      WidgetTester tester,
    ) async {
      // Arrange
      String? capturedQuery;
      await tester.pumpWidget(
        createActiveSearchWidget(
          initialMode: SearchMode.text,
          onChanged: (query) {
            capturedQuery = query;
          },
        ),
      );

      // Act
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();

      // Assert
      verifyNever(mockSearchProvider.setSearchMode(any));
      expect(capturedQuery, 'apple');
    });

    testWidgets('does not switch mode when on recipe tab', (
      WidgetTester tester,
    ) async {
      // Arrange
      String? capturedQuery;
      await tester.pumpWidget(
        createActiveSearchWidget(
          initialMode: SearchMode.recipe,
          onChanged: (query) {
            capturedQuery = query;
          },
        ),
      );

      // Act
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();

      // Assert
      verifyNever(mockSearchProvider.setSearchMode(any));
      expect(capturedQuery, 'apple');
    });

    testWidgets('does not switch mode when clearing text on food tab', (
      WidgetTester tester,
    ) async {
      // Arrange
      String? capturedQuery;
      await tester.pumpWidget(
        createActiveSearchWidget(
          initialMode: SearchMode.food,
          onChanged: (query) {
            capturedQuery = query;
          },
        ),
      );

      // Act - enter empty string
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // Assert - should not switch mode for empty query
      verifyNever(mockSearchProvider.setSearchMode(any));
      // Note: capturedQuery might be null if onChanged isn't called for empty strings
      expect(capturedQuery, anyOf(isNull, equals('')));
    });
  });
}
