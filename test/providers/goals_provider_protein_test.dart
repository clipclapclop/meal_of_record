import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/models/goal_settings.dart';
import 'package:meal_of_record/models/weight.dart';

import 'goals_provider_test.mocks.dart';

@GenerateMocks([DatabaseService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDatabaseService mockDatabaseService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockDatabaseService = MockDatabaseService();
  });

  Future<GoalsProvider> createProvider({
    required DateTime now,
    GoalSettings? initialSettings,
    List<Weight>? weights,
  }) async {
    if (initialSettings != null) {
      SharedPreferences.setMockInitialValues({
        'goal_settings': jsonEncode(initialSettings.toJson()),
      });
    }

    // Mock DB calls
    when(
      mockDatabaseService.getWeightsForRange(any, any),
    ).thenAnswer((_) async => weights ?? []);
    when(
      mockDatabaseService.getLoggedMacrosForDateRange(any, any),
    ).thenAnswer((_) async => []);

    final provider = GoalsProvider(
      databaseService: mockDatabaseService,
      clock: () => now,
    );
    await Future.delayed(Duration.zero);
    return provider;
  }

  group('GoalsProvider Protein Targets', () {
    final now = DateTime(2024, 1, 15);

    test('Fixed mode: proteinTarget remains as set', () async {
      final settings = GoalSettings(
        anchorWeight: 150.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 200, // Fixed value
        fatTarget: 70,
        carbTarget: 200,
        fiberTarget: 30,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 2.0, // Should be ignored
        fixedDelta: 0,
        lastTargetUpdate: now,
      );

      final provider = await createProvider(
        now: now,
        initialSettings: settings,
        weights: [Weight(date: now, weight: 180.0)], // Weight differs
      );

      // Force recalculate — now returns a result
      final result = await provider.recalculateTargets(settings);

      expect(result.settings.proteinTarget, 200.0);
      expect(result.goals.protein, 200.0);
    });

    test('Multiplier mode: uses latest weight when Kalman unavailable', () async {
      final settings = GoalSettings(
        anchorWeight: 150.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 100, // Should be overwritten
        fatTarget: 70,
        carbTarget: 200,
        fiberTarget: 30,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.percentageOfWeight,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: now,
      );

      // Two weights of 200 — Kalman won't run (not enough data), falls back to latest raw weight
      final weights = [
        Weight(date: now.subtract(const Duration(days: 1)), weight: 200.0),
        Weight(date: now, weight: 200.0),
      ];

      final provider = await createProvider(
        now: now,
        initialSettings: settings,
        weights: weights,
      );

      final result = await provider.recalculateTargets(settings);

      // Latest weight is 200. Multiplier 1.0 -> 200g protein.
      expect(result.settings.proteinTarget, 200.0);
      expect(result.goals.protein, 200.0);
    });

    test(
      'Multiplier mode: falls back to latest weight if single weight entry',
      () async {
        final settings = GoalSettings(
          anchorWeight: 150.0,
          maintenanceCaloriesStart: 2000,
          proteinTarget: 100,
          fatTarget: 70,
          carbTarget: 200,
          fiberTarget: 30,
          mode: GoalMode.maintain,
          calculationMode: MacroCalculationMode.proteinCarbs,
          proteinTargetMode: ProteinTargetMode.percentageOfWeight,
          proteinMultiplier: 1.5,
          fixedDelta: 0,
          lastTargetUpdate: now,
        );

        // Only one weight — Kalman won't run, falls back to latest raw weight.
        final weights = [Weight(date: now, weight: 180.0)];

        final provider = await createProvider(
          now: now,
          initialSettings: settings,
          weights: weights,
        );

        final result = await provider.recalculateTargets(settings);

        // Latest weight is 180. 180 * 1.5 = 270.
        expect(result.settings.proteinTarget, 270.0);
      },
    );

    test(
      'Multiplier mode: falls back to Anchor Weight if no weights',
      () async {
        final settings = GoalSettings(
          anchorWeight: 160.0,
          maintenanceCaloriesStart: 2000,
          proteinTarget: 100,
          fatTarget: 70,
          carbTarget: 200,
          fiberTarget: 30,
          mode: GoalMode.maintain,
          calculationMode: MacroCalculationMode.proteinCarbs,
          proteinTargetMode: ProteinTargetMode.percentageOfWeight,
          proteinMultiplier: 0.5,
          fixedDelta: 0,
          lastTargetUpdate: now,
        );

        final provider = await createProvider(
          now: now,
          initialSettings: settings,
          weights: [], // No weights
        );

        final result = await provider.recalculateTargets(settings);

        // 160 * 0.5 = 80.
        expect(result.settings.proteinTarget, 80.0);
      },
    );

    test('Changing mode refreshes calculation', () async {
      final settings = GoalSettings(
        anchorWeight: 150.0,
        maintenanceCaloriesStart: 2000,
        proteinTarget: 200, // Fixed
        fatTarget: 70,
        carbTarget: 0,
        fiberTarget: 30,
        mode: GoalMode.maintain,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 2.0,
        fixedDelta: 0,
        lastTargetUpdate: now,
      );

      final provider = await createProvider(
        now: now,
        initialSettings: settings,
        weights: [Weight(date: now, weight: 180.0)],
      );

      // Initially fixed at 200
      expect(provider.settings.proteinTarget, 200.0);

      // Switch to multiplier
      final newSettings = settings.copyWith(
        proteinTargetMode: ProteinTargetMode.percentageOfWeight,
      );

      // We must manually trigger saveSettings which calls recalculate
      await provider.saveSettings(newSettings);

      // 180 * 2.0 = 360
      expect(provider.settings.proteinTarget, 360.0);
    });
  });
}
