import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/screens/goal_settings_screen.dart';
import 'package:meal_of_record/providers/goals_provider.dart' show GoalsProvider, TargetRecalcResult;
import 'package:meal_of_record/models/goal_settings.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/providers/weight_provider.dart';
import 'package:meal_of_record/models/weight.dart';

import 'package:meal_of_record/providers/navigation_provider.dart';

import 'goal_settings_screen_test.mocks.dart';

@GenerateMocks([GoalsProvider, WeightProvider, NavigationProvider])
void main() {
  late MockGoalsProvider mockGoalsProvider;
  late MockWeightProvider mockWeightProvider;
  late MockNavigationProvider mockNavigationProvider;

  setUp(() {
    mockGoalsProvider = MockGoalsProvider();
    mockWeightProvider = MockWeightProvider();
    mockNavigationProvider = MockNavigationProvider();

    // Stub the settings getter
    when(mockGoalsProvider.settings).thenReturn(GoalSettings.defaultSettings());
    when(mockGoalsProvider.targetFor(any)).thenReturn(MacroGoals.hardcoded());
    when(mockGoalsProvider.isGoalsSet).thenReturn(false);

    // Stub weight provider
    when(mockWeightProvider.getWeightForDate(any)).thenReturn(null);
    when(mockWeightProvider.saveWeight(any, any)).thenAnswer((_) async {});
    when(mockGoalsProvider.recalculateTargets(any, isInitialSetup: anyNamed('isInitialSetup'), updateTdeeEstimate: anyNamed('updateTdeeEstimate'))).thenAnswer(
      (invocation) async => TargetRecalcResult(
        settings: GoalSettings.defaultSettings(),
        goals: MacroGoals.hardcoded(),
      ),
    );
  });

  testWidgets('GoalSettingsScreen renders all fields and toggles', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
          ChangeNotifierProvider<WeightProvider>.value(
            value: mockWeightProvider,
          ),
        ],
        child: const MaterialApp(home: GoalSettingsScreen()),
      ),
    );

    expect(find.text('Goals & Targets'), findsOneWidget);
    expect(find.text('Goal Mode'), findsOneWidget);
    expect(
      find.text('Target Weight (lb)'),
      findsOneWidget,
    ); // Default is Imperial
    // Scroll to see the save button
    final saveButton = find.text('Save Settings');
    await tester.scrollUntilVisible(
      saveButton,
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Check for save button
    expect(saveButton, findsOneWidget);
  });

  testWidgets('Saving settings saves settings', (tester) async {
    when(
      mockGoalsProvider.saveSettings(
        any,
        isInitialSetup: anyNamed('isInitialSetup'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
          ChangeNotifierProvider<NavigationProvider>.value(
            value: mockNavigationProvider,
          ),
          ChangeNotifierProvider<WeightProvider>.value(
            value: mockWeightProvider,
          ),
        ],
        child: const MaterialApp(home: GoalSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Helper to fill a field by label
    Future<void> fillField(String label, String value) async {
      final finder = find.widgetWithText(TextField, label);
      await tester.scrollUntilVisible(
        finder,
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(finder, value);
      await tester.pump();
    }

    await fillField('Target Weight (lb)', '155.5');
    await fillField('Initial TDEE', '2340');
    await fillField('Protein Target (g)', '150');
    await fillField('Carbs (g)', '200');
    await fillField('Fiber (g)', '38');

    // Scroll to save
    final saveButton = find.text('Save Settings');
    await tester.scrollUntilVisible(
      saveButton,
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final savedSettings = verify(
      mockGoalsProvider.saveSettings(
        captureAny,
        isInitialSetup: anyNamed('isInitialSetup'),
      ),
    ).captured.single as GoalSettings;
    expect(savedSettings.anchorWeight, 155.5);
    verify(mockNavigationProvider.changeTab(0)).called(1);
  });

  testWidgets('Saving does not navigate after the screen is disposed', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    when(
      mockGoalsProvider.saveSettings(
        any,
        isInitialSetup: anyNamed('isInitialSetup'),
      ),
    ).thenAnswer((_) => saveCompleter.future);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
          ChangeNotifierProvider<NavigationProvider>.value(
            value: mockNavigationProvider,
          ),
          ChangeNotifierProvider<WeightProvider>.value(
            value: mockWeightProvider,
          ),
        ],
        child: const MaterialApp(home: GoalSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> fillField(String label, String value) async {
      final finder = find.widgetWithText(TextField, label);
      await tester.scrollUntilVisible(
        finder,
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(finder, value);
      await tester.pump();
    }

    await fillField('Target Weight (lb)', '155.5');
    await fillField('Initial TDEE', '2340');
    await fillField('Protein Target (g)', '150');
    await fillField('Carbs (g)', '200');
    await fillField('Fiber (g)', '38');

    final saveButton = find.text('Save Settings');
    await tester.scrollUntilVisible(
      saveButton,
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump();

    verify(
      mockGoalsProvider.saveSettings(
        any,
        isInitialSetup: anyNamed('isInitialSetup'),
      ),
    ).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
    saveCompleter.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    verifyNever(mockNavigationProvider.changeTab(any));
  });

  testWidgets(
    'Estimated protein target is NOT displayed when using Multiplier mode',
    (tester) async {
      // Select Multiplier mode
      final settings = GoalSettings.defaultSettings().copyWith(
      proteinTargetMode: ProteinTargetMode.percentageOfWeight,
      proteinMultiplier: 1.0,
      anchorWeight: 155.5,
    );
    when(mockGoalsProvider.settings).thenReturn(settings);
    when(mockWeightProvider.recentWeights).thenReturn([]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
          ChangeNotifierProvider<WeightProvider>.value(
            value: mockWeightProvider,
          ),
        ],
        child: const MaterialApp(home: GoalSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Verify "Estimated Target:" is NOT present
    expect(find.textContaining('Estimated Target:'), findsNothing);
  });

  testWidgets(
    'Switching to Maintain mode sets target weight to latest raw weight',
    (tester) async {
      // Setup some weight history
      final weights = [
        Weight(id: 1, weight: 160.0, date: DateTime(2024, 1, 1)),
        Weight(id: 2, weight: 158.0, date: DateTime(2024, 1, 2)),
        Weight(id: 3, weight: 159.0, date: DateTime(2024, 1, 3)),
      ];
      when(mockWeightProvider.weights).thenReturn(weights);

      // Load screen in Lose mode
      final settings = GoalSettings.defaultSettings().copyWith(
        mode: GoalMode.lose,
        anchorWeight: 170.0,
      );
      when(mockGoalsProvider.settings).thenReturn(settings);
      when(mockGoalsProvider.useNetCarbs).thenReturn(false);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalsProvider>.value(value: mockGoalsProvider),
            ChangeNotifierProvider<WeightProvider>.value(
              value: mockWeightProvider,
            ),
          ],
          child: const MaterialApp(home: GoalSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Starting Weight (lb)'), findsOneWidget);
      expect(find.text('170.0'), findsOneWidget);

      // Tap Maintain mode
      await tester.tap(find.text('Maintain'));
      await tester.pumpAndSettle();

      // Should now show Target Weight with latest raw weight (159.0)
      expect(find.text('Target Weight (lb)'), findsOneWidget);
      expect(find.text('159.0'), findsOneWidget);
    },
  );

  group('Unsaved Changes Dialog', () {
    testWidgets('Pops immediately if no changes', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalsProvider>.value(
              value: mockGoalsProvider,
            ),
            ChangeNotifierProvider<WeightProvider>.value(
              value: mockWeightProvider,
            ),
          ],
          child: const MaterialApp(home: GoalSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger back navigation
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // Screen should be gone (MaterialApp home is gone, or check navigator)
      expect(find.byType(GoalSettingsScreen), findsNothing);
    });

    testWidgets('Shows dialog if has changes and back is pressed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalsProvider>.value(
              value: mockGoalsProvider,
            ),
            ChangeNotifierProvider<WeightProvider>.value(
              value: mockWeightProvider,
            ),
          ],
          child: const MaterialApp(home: GoalSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Make a change
      await tester.enterText(
        find.widgetWithText(TextField, 'Target Weight (lb)'),
        '180',
      );
      await tester.pump();

      // Trigger back navigation
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // Dialog should be visible
      expect(find.text('Unsaved Changes'), findsOneWidget);
    });

    testWidgets('Dialog Cancel stays on screen', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalsProvider>.value(
              value: mockGoalsProvider,
            ),
            ChangeNotifierProvider<WeightProvider>.value(
              value: mockWeightProvider,
            ),
          ],
          child: const MaterialApp(home: GoalSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Target Weight (lb)'),
        '180',
      );
      await tester.pump();

      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog gone, screen still there
      expect(find.text('Unsaved Changes'), findsNothing);
      expect(find.byType(GoalSettingsScreen), findsOneWidget);
    });

    testWidgets('Dialog Discard pops screen', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalsProvider>.value(
              value: mockGoalsProvider,
            ),
            ChangeNotifierProvider<WeightProvider>.value(
              value: mockWeightProvider,
            ),
          ],
          child: const MaterialApp(home: GoalSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Target Weight (lb)'),
        '180',
      );
      await tester.pump();

      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // Screen gone
      expect(find.byType(GoalSettingsScreen), findsNothing);
    });

    testWidgets('Dialog Save validates and saves', (tester) async {
      when(
        mockGoalsProvider.saveSettings(
          any,
          isInitialSetup: anyNamed('isInitialSetup'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalsProvider>.value(
              value: mockGoalsProvider,
            ),
            ChangeNotifierProvider<NavigationProvider>.value(
              value: mockNavigationProvider,
            ),
            ChangeNotifierProvider<WeightProvider>.value(
              value: mockWeightProvider,
            ),
          ],
          child: const MaterialApp(home: GoalSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Make a valid change
      await tester.enterText(
        find.widgetWithText(TextField, 'Target Weight (lb)'),
        '180',
      );
      await tester.pump();

      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Should have called save and navigator popped
      verify(
        mockGoalsProvider.saveSettings(
          any,
          isInitialSetup: anyNamed('isInitialSetup'),
        ),
      ).called(1);
      expect(find.byType(GoalSettingsScreen), findsNothing);
    });
  });
}
