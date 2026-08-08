import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/models/goal_settings.dart';
import 'package:meal_of_record/models/weight.dart';
import 'package:meal_of_record/models/daily_macro_stats.dart';

import 'goals_provider_test.mocks.dart';

@GenerateMocks([DatabaseService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDatabaseService mockDatabaseService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockDatabaseService = MockDatabaseService();

    // Default stubs for calls that happen during initialization
    when(
      mockDatabaseService.getWeightsForRange(any, any),
    ).thenAnswer((_) async => []);
    when(
      mockDatabaseService.getLoggedMacrosForDateRange(any, any),
    ).thenAnswer((_) async => []);
    when(
      mockDatabaseService.getFoodsByIds(any, any),
    ).thenAnswer((_) async => {});
    when(mockDatabaseService.getRecipesByIds(any)).thenAnswer((_) async => {});
  });

  /// Helper: creates a GoalsProvider with a fixed clock and waits for init.
  Future<GoalsProvider> createProvider({
    required DateTime Function() clock,
    GoalSettings? initialSettings,
  }) async {
    if (initialSettings != null) {
      SharedPreferences.setMockInitialValues({
        'goal_settings': jsonEncode(initialSettings.toJson()),
      });
    } else {
      SharedPreferences.setMockInitialValues({});
    }

    // Stub DB calls that happen during _loadFromPrefs -> checkWeeklyUpdate
    when(
      mockDatabaseService.getWeightsForRange(any, any),
    ).thenAnswer((_) async => []);
    when(
      mockDatabaseService.getLoggedMacrosForDateRange(any, any),
    ).thenAnswer((_) async => []);

    final provider = GoalsProvider(
      databaseService: mockDatabaseService,
      clock: clock,
    );
    await Future.delayed(Duration.zero);
    return provider;
  }

  /// Helper: builds weight entries for N recent days.
  List<Weight> buildRecentWeights(
    DateTime now,
    int count, {
    double weight = 100.0,
  }) {
    return List.generate(
      count,
      (i) => Weight(
        weight: weight,
        date: now.subtract(Duration(days: i)),
      ),
    );
  }

  group('GoalsProvider basic', () {
    test('initial state should be loading then default settings', () async {
      final provider = await createProvider(clock: () => DateTime(2024, 1, 15));
      expect(provider.isLoading, false);
      expect(provider.settings.anchorWeight, 0.0);
      expect(provider.settings.isSet, false);
    });

    test('saveSettings should persist and mark as set', () async {
      final now = DateTime(2024, 1, 15); // Monday
      final provider = await createProvider(clock: () => now);

      final newSettings = GoalSettings(
        anchorWeight: 75.0,
        maintenanceCaloriesStart: 2500,
        proteinTarget: 160,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: now,
        fiberTarget: 37.0,
      );

      await provider.saveSettings(newSettings);

      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString('goal_settings');
      expect(savedJson, isNotNull);
      final decoded = GoalSettings.fromJson(jsonDecode(savedJson!));
      expect(decoded.anchorWeight, 75.0);
      expect(decoded.isSet, true);
    });
  });

  group('GoalsProvider cold boot', () {
    test('no weight data -> uses manual maintenance', () async {
      // Monday with old lastUpdate
      final now = DateTime(2024, 1, 15, 10); // Monday
      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => []);

      final settings = GoalSettings(
        anchorWeight: 150.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 1), // old

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // Cold boot fallback: manual maintenance = 2000
      expect(provider.currentGoals.calories, 2000.0);
    });

    test('insufficient weight entries -> still manual', () async {
      final now = DateTime(2024, 1, 15, 10); // Monday
      // 9 weights in last 28 days. Needs 70% of 14 (smallest tier) = 10.
      // But only 9 days of data span, so effectiveWindow returns 0.
      final weights = buildRecentWeights(now, 9);

      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => weights);

      final settings = GoalSettings(
        anchorWeight: 100.0,
        maintenanceCaloriesStart: 2200,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 1),

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // Cold boot: not enough data for any tier. Falls back to manual.
      expect(provider.currentGoals.calories, 2200.0);
    });

    test(
      '20 days of data with 60d setting -> falls back to 14d tier',
      () async {
        final now = DateTime(2024, 1, 15, 10); // Monday
        // 20 days of data: effectiveWindow(60, 20) = 14
        // 70% of 14 = 10. We have enough within 14-day window.
        final weights = buildRecentWeights(now, 15);

        when(
          mockDatabaseService.getWeightsForRange(any, any),
        ).thenAnswer((_) async => weights);
        when(
          mockDatabaseService.getLoggedMacrosForDateRange(any, any),
        ).thenAnswer((_) async => []);

        final settings = GoalSettings(
          anchorWeight: 100.0,
          maintenanceCaloriesStart: 2200,
          proteinTarget: 150,
          fatTarget: 70,
          carbTarget: 200,
          mode: GoalMode.maintain,
          calculationMode: MacroCalculationMode.proteinCarbs,
          proteinTargetMode: ProteinTargetMode.fixed,
          proteinMultiplier: 1.0,
          fixedDelta: 0,
          lastTargetUpdate: DateTime(2024, 1, 1),

          fiberTarget: 37.0,
          enableSmartTargets: true,
          tdeeWindowDays: 60,
        );

        final provider = await createProvider(
          clock: () => now,
          initialSettings: settings,
        );

        // Should use Kalman (fell back to 14d tier), not manual 2200.
        // With all-invalid intake, TDEE stays near initial 2200.
        expect(provider.currentGoals.calories, closeTo(2200.0, 100.0));
      },
    );
  });

  group('GoalsProvider warm start (Kalman)', () {
    /// Helper: sets up a provider with enough weight data for Kalman.
    Future<GoalsProvider> createWarmProvider({
      required DateTime Function() clock,
      required GoalSettings settings,
      int weightCount = 20,
      double weightValue = 100.0,
      List<LoggedMacroDTO>? dtos,
    }) async {
      final now = clock();
      final weights = buildRecentWeights(now, weightCount, weight: weightValue);

      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => weights);
      when(
        mockDatabaseService.getLoggedMacrosForDateRange(any, any),
      ).thenAnswer((_) async => dtos ?? []);

      return createProvider(clock: clock, initialSettings: settings);
    }

    GoalSettings baseSettings({
      GoalMode mode = GoalMode.maintain,
      double fixedDelta = 0,
      double maintenance = 2000,
    }) {
      return GoalSettings(
        anchorWeight: 100.0,
        maintenanceCaloriesStart: maintenance,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: mode,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: fixedDelta,
        lastTargetUpdate: DateTime(2024, 1, 1), // old, forces recalc on Monday

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );
    }

    test('10+ weight entries with stable intake -> uses Kalman TDEE', () async {
      final now = DateTime(2024, 1, 15, 10); // Monday

      // Build DTOs for stable 2000 cal intake for 90 days
      final today = DateTime(now.year, now.month, now.day);
      final analysisStart = today.subtract(const Duration(days: 90));
      final dtos = <LoggedMacroDTO>[];
      var d = analysisStart;
      while (!d.isAfter(today)) {
        dtos.add(
          LoggedMacroDTO(
            logTimestamp: d,
            grams: 100.0,
            caloriesPerGram: 20.0, // 2000 cal total
            proteinPerGram: 1.5,
            fatPerGram: 0.7,
            carbsPerGram: 2.0,
            fiberPerGram: 0.38,
          ),
        );
        d = d.add(const Duration(days: 1));
      }

      final provider = await createWarmProvider(
        clock: () => now,
        settings: baseSettings(),
        weightCount: 20,
        weightValue: 100.0,
        dtos: dtos,
      );

      // Kalman with stable weight + 2000 cal intake -> TDEE near 2000
      expect(provider.currentGoals.calories, closeTo(2000.0, 100.0));
    });

    test('maintain mode at anchor weight: target = Kalman TDEE', () async {
      final now = DateTime(2024, 1, 15, 10);
      final provider = await createWarmProvider(
        clock: () => now,
        settings: baseSettings(mode: GoalMode.maintain),
        weightValue: 100.0, // equals anchorWeight: 100.0 → drift = 0
      );

      // drift = 0, so no correction. Target = TDEE.
      expect(provider.currentGoals.calories, closeTo(2000.0, 100.0));
    });

    test(
      'maintain mode above anchor weight: target < TDEE (deficit to drift down)',
      () async {
        // NOTE: createWarmProvider/createProvider reset mocks internally, so we
        // wire up the GoalsProvider directly to ensure weight data reaches Kalman.
        final now = DateTime(2024, 1, 15, 10); // Monday
        // 2 lbs over target, 30-day correction window → deficit = 2*3500/30 ≈ 233 cal/day
        const correctionWindowDays = 30;
        const anchorWeight = 100.0;
        const currentWeight = 102.0; // 2 lbs over
        const expectedCorrection =
            (currentWeight - anchorWeight) * 3500 / correctionWindowDays;

        final settings = GoalSettings(
          anchorWeight: anchorWeight,
          maintenanceCaloriesStart: 2000,
          proteinTarget: 150,
          fatTarget: 70,
          carbTarget: 200,
          mode: GoalMode.maintain,
          calculationMode: MacroCalculationMode.proteinCarbs,
          proteinTargetMode: ProteinTargetMode.fixed,
          proteinMultiplier: 1.0,
          fixedDelta: 0,
          lastTargetUpdate: DateTime(
            2024,
            1,
            1,
          ), // old → triggers Monday recalc
          fiberTarget: 37.0,
          enableSmartTargets: true,
          correctionWindowDays: correctionWindowDays,
        );

        SharedPreferences.setMockInitialValues({
          'goal_settings': jsonEncode(settings.toJson()),
        });
        final weights = buildRecentWeights(now, 20, weight: currentWeight);
        when(
          mockDatabaseService.getWeightsForRange(any, any),
        ).thenAnswer((_) async => weights);
        when(
          mockDatabaseService.getLoggedMacrosForDateRange(any, any),
        ).thenAnswer((_) async => []);

        final provider = GoalsProvider(
          databaseService: mockDatabaseService,
          clock: () => now,
        );
        await Future.delayed(Duration.zero);

        // TDEE stays near 2000 (no valid intake). Target should be below TDEE.
        expect(provider.currentGoals.calories, lessThan(2000.0));
        expect(
          provider.currentGoals.calories,
          closeTo(2000.0 - expectedCorrection, 100.0),
        );
      },
    );

    test(
      'maintain mode below anchor weight: target > TDEE (surplus to drift up)',
      () async {
        final now = DateTime(2024, 1, 15, 10); // Monday
        // 2 lbs under target, 30-day correction window → surplus = 2*3500/30 ≈ 233 cal/day
        const correctionWindowDays = 30;
        const anchorWeight = 100.0;
        const currentWeight = 98.0; // 2 lbs under
        const expectedCorrection =
            (currentWeight - anchorWeight) *
            3500 /
            correctionWindowDays; // negative

        final settings = GoalSettings(
          anchorWeight: anchorWeight,
          maintenanceCaloriesStart: 2000,
          proteinTarget: 150,
          fatTarget: 70,
          carbTarget: 200,
          mode: GoalMode.maintain,
          calculationMode: MacroCalculationMode.proteinCarbs,
          proteinTargetMode: ProteinTargetMode.fixed,
          proteinMultiplier: 1.0,
          fixedDelta: 0,
          lastTargetUpdate: DateTime(
            2024,
            1,
            1,
          ), // old → triggers Monday recalc
          fiberTarget: 37.0,
          enableSmartTargets: true,
          correctionWindowDays: correctionWindowDays,
        );

        SharedPreferences.setMockInitialValues({
          'goal_settings': jsonEncode(settings.toJson()),
        });
        final weights = buildRecentWeights(now, 20, weight: currentWeight);
        when(
          mockDatabaseService.getWeightsForRange(any, any),
        ).thenAnswer((_) async => weights);
        when(
          mockDatabaseService.getLoggedMacrosForDateRange(any, any),
        ).thenAnswer((_) async => []);

        final provider = GoalsProvider(
          databaseService: mockDatabaseService,
          clock: () => now,
        );
        await Future.delayed(Duration.zero);

        // TDEE stays near 2000 (no valid intake). Target should be above TDEE.
        expect(provider.currentGoals.calories, greaterThan(2000.0));
        expect(
          provider.currentGoals.calories,
          closeTo(2000.0 - expectedCorrection, 100.0),
        );
      },
    );

    test('lose mode: target = Kalman TDEE - fixedDelta', () async {
      final now = DateTime(2024, 1, 15, 10);
      final provider = await createWarmProvider(
        clock: () => now,
        settings: baseSettings(mode: GoalMode.lose, fixedDelta: 500),
      );

      // TDEE near 2000, lose mode subtracts 500
      expect(provider.currentGoals.calories, closeTo(1500.0, 100.0));
    });

    test('gain mode: target = Kalman TDEE + fixedDelta', () async {
      final now = DateTime(2024, 1, 15, 10);
      final provider = await createWarmProvider(
        clock: () => now,
        settings: baseSettings(mode: GoalMode.gain, fixedDelta: 500),
      );

      // TDEE near 2000, gain mode adds 500
      expect(provider.currentGoals.calories, closeTo(2500.0, 100.0));
    });

    test('updates maintenanceCaloriesStart with Kalman result', () async {
      final now = DateTime(2024, 1, 15, 10);
      final provider = await createWarmProvider(
        clock: () => now,
        settings: baseSettings(maintenance: 1800),
      );

      // After Kalman runs, maintenanceCaloriesStart should be updated
      // (it was 1800, Kalman with all-invalid intake stays near 1800)
      expect(
        provider.settings.maintenanceCaloriesStart,
        closeTo(1800.0, 100.0),
      );
    });
  });

  group('GoalsProvider smart targets toggle', () {
    test('smart targets off -> always manual regardless of data', () async {
      final now = DateTime(2024, 1, 15, 10);
      final weights = buildRecentWeights(now, 20);

      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => weights);

      final settings = GoalSettings(
        anchorWeight: 105.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 1),

        fiberTarget: 37.0,
        enableSmartTargets: false,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // Smart targets off: uses manual maintenance = 2000
      expect(provider.currentGoals.calories, 2000.0);
    });
  });

  group('GoalsProvider weekly update with clock', () {
    test('Monday with old lastUpdate -> triggers recalc', () async {
      // Monday
      final now = DateTime(2024, 1, 15, 10);
      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => []);

      final settings = GoalSettings(
        anchorWeight: 100.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 8), // last Monday

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // Should have triggered recalc and notification
      expect(provider.showUpdateNotification, isTrue);
    });

    test('Monday with recent lastUpdate -> no recalc', () async {
      final now = DateTime(2024, 1, 15, 10); // Monday
      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => []);

      final settings = GoalSettings(
        anchorWeight: 100.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 15), // today

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // lastUpdate is today, no recalc needed
      expect(provider.showUpdateNotification, isFalse);
    });

    test(
      'Tuesday after missed Monday with old lastUpdate -> triggers recalc',
      () async {
        // Tuesday Jan 16, lastUpdate is Jan 8 (before Monday Jan 15)
        final now = DateTime(2024, 1, 16, 10); // Tuesday
        when(
          mockDatabaseService.getWeightsForRange(any, any),
        ).thenAnswer((_) async => []);

        final settings = GoalSettings(
          anchorWeight: 100.0,
          maintenanceCaloriesStart: 2000,
          proteinTarget: 150,
          fatTarget: 70,
          carbTarget: 200,
          mode: GoalMode.maintain,
          calculationMode: MacroCalculationMode.proteinCarbs,
          proteinTargetMode: ProteinTargetMode.fixed,
          proteinMultiplier: 1.0,
          fixedDelta: 0,
          lastTargetUpdate: DateTime(2024, 1, 8), // before last Monday (Jan 15)

          fiberTarget: 37.0,
          enableSmartTargets: true,
        );

        final provider = await createProvider(
          clock: () => now,
          initialSettings: settings,
        );

        // Tuesday, but lastUpdate is before last Monday -> triggers recalc
        expect(provider.showUpdateNotification, isTrue);
      },
    );

    test('Wednesday after already-updated Tuesday -> no recalc', () async {
      // Wednesday Jan 17, lastUpdate is Tuesday Jan 16 (after Monday Jan 15)
      final now = DateTime(2024, 1, 17, 10); // Wednesday
      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => []);

      final settings = GoalSettings(
        anchorWeight: 100.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 16), // Tuesday, after last Monday

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // lastUpdate (Tue Jan 16) is after lastMonday (Mon Jan 15) -> no recalc
      expect(provider.showUpdateNotification, isFalse);
    });
  });

  group('GoalsProvider intake validity', () {
    test(
      'day with 0 cal + logCount > 0 -> included as valid (fasted day)',
      () async {
        final now = DateTime(2024, 1, 15, 10); // Monday
        final weights = buildRecentWeights(now, 20);

        when(
          mockDatabaseService.getWeightsForRange(any, any),
        ).thenAnswer((_) async => weights);

        // Create a DTO with 0 grams (fasted day marker)
        final today = DateTime(now.year, now.month, now.day);
        final dtos = [
          LoggedMacroDTO(
            logTimestamp: today,
            grams: 0.0,
            caloriesPerGram: 0.0,
            proteinPerGram: 0.0,
            fatPerGram: 0.0,
            carbsPerGram: 0.0,
            fiberPerGram: 0.0,
          ),
        ];

        when(
          mockDatabaseService.getLoggedMacrosForDateRange(any, any),
        ).thenAnswer((_) async => dtos);

        final settings = GoalSettings(
          anchorWeight: 100.0,
          maintenanceCaloriesStart: 2000,
          proteinTarget: 150,
          fatTarget: 70,
          carbTarget: 200,
          mode: GoalMode.maintain,
          calculationMode: MacroCalculationMode.proteinCarbs,
          proteinTargetMode: ProteinTargetMode.fixed,
          proteinMultiplier: 1.0,
          fixedDelta: 0,
          lastTargetUpdate: DateTime(2024, 1, 1),

          fiberTarget: 37.0,
          enableSmartTargets: true,
        );

        final provider = await createProvider(
          clock: () => now,
          initialSettings: settings,
        );

        // Should complete without error; fasted day is valid intake
        expect(provider.currentGoals.calories, isNotNull);
      },
    );

    test('partial-day intake (today) excluded from Kalman analysis', () async {
      final now = DateTime(2024, 1, 15, 14); // Monday 2pm
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final weights = buildRecentWeights(now, 20);

      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => weights);

      // Build stable 2000 cal intake for past 90 days through yesterday
      final analysisStart = yesterday.subtract(const Duration(days: 90));
      final dtos = <LoggedMacroDTO>[];
      var d = analysisStart;
      while (!d.isAfter(yesterday)) {
        dtos.add(
          LoggedMacroDTO(
            logTimestamp: d,
            grams: 100.0,
            caloriesPerGram: 20.0, // 2000 cal total
            proteinPerGram: 1.5,
            fatPerGram: 0.7,
            carbsPerGram: 2.0,
            fiberPerGram: 0.38,
          ),
        );
        d = d.add(const Duration(days: 1));
      }
      // Add today's partial intake: only 300 cal logged so far
      dtos.add(
        LoggedMacroDTO(
          logTimestamp: today,
          grams: 100.0,
          caloriesPerGram: 3.0, // 300 cal
          proteinPerGram: 0.5,
          fatPerGram: 0.2,
          carbsPerGram: 0.5,
          fiberPerGram: 0.1,
        ),
      );

      when(
        mockDatabaseService.getLoggedMacrosForDateRange(any, any),
      ).thenAnswer((_) async => dtos);

      final settings = GoalSettings(
        anchorWeight: 100.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 1),

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // Today's 300 cal partial log should NOT distort TDEE.
      // With stable weight + 2000 cal intake through yesterday, TDEE ~ 2000.
      expect(provider.currentGoals.calories, closeTo(2000.0, 150.0));
      // Specifically: TDEE should NOT be inflated by treating 300 cal as a full day
      expect(provider.settings.maintenanceCaloriesStart, greaterThan(1500.0));
    });

    test('day with 0 cal + logCount == 0 -> excluded from Kalman', () async {
      final now = DateTime(2024, 1, 15, 10);
      final weights = buildRecentWeights(now, 20);

      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => weights);
      // No DTOs at all = all days have logCount == 0
      when(
        mockDatabaseService.getLoggedMacrosForDateRange(any, any),
      ).thenAnswer((_) async => []);

      final settings = GoalSettings(
        anchorWeight: 100.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 1),

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // All intake excluded -> TDEE stays near initial 2000
      expect(provider.currentGoals.calories, closeTo(2000.0, 100.0));
    });
  });

  group('GoalsProvider Lifecycle and Timezone', () {
    test('AppLifecycleState.resumed triggers checkWeeklyUpdate', () async {
      var now = DateTime(2024, 1, 15, 10); // Monday

      final settings = GoalSettings.defaultSettings().copyWith(
        isSet: true,
        lastTargetUpdate: DateTime(2024, 1, 15),
      );

      // Use the helper which already stubs everything
      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // Wait for any initial background tasks to settle
      await Future.delayed(const Duration(milliseconds: 100));
      expect(provider.isLoading, isFalse);
      expect(provider.showUpdateNotification, isFalse);

      // Simulate time jumping to next Monday
      now = DateTime(2024, 1, 22, 10);

      // Now simulate resume
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // Wait for the async checkWeeklyUpdate to finish
      // Since it's triggered by an observer, we wait a bit
      await Future.delayed(const Duration(milliseconds: 100));

      expect(provider.showUpdateNotification, isTrue);
    });

    test('recalculateTargets unifies lastTargetUpdate to current time', () async {
      final monday = DateTime(2024, 1, 15, 10);
      final provider = await createProvider(clock: () => monday);

      final settings = GoalSettings.defaultSettings().copyWith(
        mode: GoalMode.lose,
        fixedDelta: 500,
        enableSmartTargets: false, // Manual mode
      );

      await provider.saveSettings(settings);

      // In old code, this would have been next Monday. In new code, it's today.
      expect(provider.settings.lastTargetUpdate, monday);
    });
  });

  group('GoalsProvider TDEE clamp', () {
    test('Kalman returns extreme value -> clamped to [800, 6000]', () async {
      final now = DateTime(2024, 1, 15, 10);

      // Create weights that would cause Kalman to produce extreme TDEE
      // Rapidly losing weight with very high intake -> extreme TDEE
      final today = DateTime(now.year, now.month, now.day);
      final analysisStart = today.subtract(const Duration(days: 28));

      final weights = <Weight>[];
      var d = analysisStart;
      var i = 0;
      while (!d.isAfter(today)) {
        // Only add weight entries for last 20 days
        if (d.isAfter(today.subtract(const Duration(days: 20)))) {
          weights.add(
            Weight(weight: 200.0 - (i * 2.0), date: d),
          ); // extreme loss
        }
        d = d.add(const Duration(days: 1));
        i++;
      }

      when(
        mockDatabaseService.getWeightsForRange(any, any),
      ).thenAnswer((_) async => weights);

      // Very high intake DTOs
      final dtos = <LoggedMacroDTO>[];
      d = analysisStart;
      while (!d.isAfter(today)) {
        dtos.add(
          LoggedMacroDTO(
            logTimestamp: d,
            grams: 1000.0,
            caloriesPerGram: 10.0, // 10000 cal/day
            proteinPerGram: 1.0,
            fatPerGram: 1.0,
            carbsPerGram: 1.0,
            fiberPerGram: 0.1,
          ),
        );
        d = d.add(const Duration(days: 1));
      }

      when(
        mockDatabaseService.getLoggedMacrosForDateRange(any, any),
      ).thenAnswer((_) async => dtos);

      final settings = GoalSettings(
        anchorWeight: 200.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2024, 1, 1),

        fiberTarget: 37.0,
        enableSmartTargets: true,
      );

      final provider = await createProvider(
        clock: () => now,
        initialSettings: settings,
      );

      // TDEE should be clamped to max 6000
      expect(
        provider.settings.maintenanceCaloriesStart,
        lessThanOrEqualTo(6000.0),
      );
      expect(
        provider.settings.maintenanceCaloriesStart,
        greaterThanOrEqualTo(800.0),
      );
    });
  });

  group('GoalsProvider target snapshots', () {
    GoalSettings snapshotSettings({DateTime? lastUpdate}) {
      return GoalSettings(
        anchorWeight: 75.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 150,
        fatTarget: 70,
        carbTarget: 200,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: lastUpdate ?? DateTime(2024, 1, 15),
        fiberTarget: 37.0,
      );
    }

    test('first load prepopulates 7 snapshots', () async {
      final now = DateTime(2024, 1, 15); // Monday
      await createProvider(
        clock: () => now,
        initialSettings: snapshotSettings(),
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('target_snapshots');
      expect(raw, isNotNull);
      final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw!) as List).map((e) => Map<String, dynamic>.from(e)),
      );
      expect(list.length, 7);
      expect(list.first['date'], '2024-01-09');
      expect(list.last['date'], '2024-01-15');
    });

    test('Monday recalc overwrites today snapshot', () async {
      final now = DateTime(2024, 1, 15, 10); // Monday
      await createProvider(
        clock: () => now,
        initialSettings: snapshotSettings(lastUpdate: DateTime(2024, 1, 8)),
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('target_snapshots');
      final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw!) as List).map((e) => Map<String, dynamic>.from(e)),
      );
      // Today's snapshot should exist and have been overwritten by recalc
      final todaySnap = list.where((s) => s['date'] == '2024-01-15').toList();
      expect(todaySnap.length, 1);
      expect(todaySnap.first['calories'], isNotNull);
    });

    test('saveSettings overwrites today snapshot', () async {
      final now = DateTime(2024, 1, 15);
      final provider = await createProvider(
        clock: () => now,
        initialSettings: snapshotSettings(),
      );

      // Change settings with different calories
      final newSettings = snapshotSettings().copyWith(
        maintenanceCaloriesStart: 2500,
      );
      await provider.saveSettings(newSettings);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('target_snapshots');
      final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw!) as List).map((e) => Map<String, dynamic>.from(e)),
      );
      final todaySnap = list.lastWhere((s) => s['date'] == '2024-01-15');
      expect(todaySnap['calories'], 2500.0);
    });

    test('previous days retain old snapshots after target change', () async {
      final now = DateTime(2024, 1, 15);
      final provider = await createProvider(
        clock: () => now,
        initialSettings: snapshotSettings(),
      );

      // All 7 days should have calories=2000
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString('target_snapshots');
      var list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw!) as List).map((e) => Map<String, dynamic>.from(e)),
      );
      expect(list.first['calories'], 2000.0);

      // Change settings
      final newSettings = snapshotSettings().copyWith(
        maintenanceCaloriesStart: 2500,
      );
      await provider.saveSettings(newSettings);

      raw = prefs.getString('target_snapshots');
      list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw!) as List).map((e) => Map<String, dynamic>.from(e)),
      );
      // Previous days still have 2000
      expect(list.first['calories'], 2000.0);
      // Today has 2500
      expect(list.last['calories'], 2500.0);
    });

    test('list trims to 7 after 8+ days', () async {
      // Start on day 1 with 7 snapshots
      final day1 = DateTime(2024, 1, 15);
      await createProvider(
        clock: () => day1,
        initialSettings: snapshotSettings(),
      );

      // Manually inject an 8th day by simulating a new day
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString('target_snapshots');
      var list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw!) as List).map((e) => Map<String, dynamic>.from(e)),
      );
      // Add an 8th entry
      list.add({
        'date': '2024-01-16',
        'calories': 2000.0,
        'protein': 150.0,
        'fat': 70.0,
        'carbs': 200.0,
        'fiber': 37.0,
      });
      expect(list.length, 8);

      // Persist the 8-entry list
      await prefs.setString('target_snapshots', jsonEncode(list));

      // Create a new provider for the next day which will reload and save
      final day2 = DateTime(2024, 1, 17);
      SharedPreferences.setMockInitialValues({
        'goal_settings': jsonEncode(snapshotSettings().toJson()),
        'target_snapshots': jsonEncode(list),
      });
      // ignore: unused_local_variable
      final provider2 = GoalsProvider(
        databaseService: mockDatabaseService,
        clock: () => day2,
      );
      await Future.delayed(Duration.zero);

      raw = (await SharedPreferences.getInstance()).getString(
        'target_snapshots',
      );
      final finalList = List<Map<String, dynamic>>.from(
        (jsonDecode(raw!) as List).map((e) => Map<String, dynamic>.from(e)),
      );
      expect(finalList.length, lessThanOrEqualTo(7));
    });

    test(
      'targetFor with date before all snapshots falls back to currentGoals',
      () async {
        final now = DateTime(2024, 1, 15);
        final provider = await createProvider(
          clock: () => now,
          initialSettings: snapshotSettings(),
        );

        // Query a date well before any snapshot
        final oldDate = DateTime(2023, 1, 1);
        final result = provider.targetFor(oldDate);
        expect(result.calories, provider.currentGoals.calories);
      },
    );
  });

  group('GoalsProvider Onboarding', () {
    test('initial hasSeenWelcome should be false', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = GoalsProvider(
        databaseService: mockDatabaseService,
        clock: () => DateTime(2024, 1, 15),
      );
      await Future.delayed(Duration.zero);
      expect(provider.hasSeenWelcome, false);
    });

    test('markWelcomeSeen should persist to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = GoalsProvider(
        databaseService: mockDatabaseService,
        clock: () => DateTime(2024, 1, 15),
      );
      await Future.delayed(Duration.zero);

      await provider.markWelcomeSeen();
      expect(provider.hasSeenWelcome, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('has_seen_welcome'), true);
    });

    test(
      'existing users with goals set should have hasSeenWelcome = true',
      () async {
        final settings = GoalSettings.defaultSettings().copyWith(isSet: true);
        SharedPreferences.setMockInitialValues({
          'goal_settings': jsonEncode(settings.toJson()),
        });

        final provider = GoalsProvider(
          databaseService: mockDatabaseService,
          clock: () => DateTime(2024, 1, 15),
        );
        await Future.delayed(Duration.zero);

        expect(provider.isGoalsSet, true);
        expect(provider.hasSeenWelcome, true);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('has_seen_welcome'), true);
      },
    );
  });
}
