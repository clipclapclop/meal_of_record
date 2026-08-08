import 'package:flutter_test/flutter_test.dart';
import 'package:meal_of_record/models/goal_settings.dart';
import 'package:meal_of_record/models/macro_goals.dart';

void main() {
  group('GoalSettings', () {
    test('toJson and fromJson should be symmetric', () {
      final settings = GoalSettings(
        anchorWeight: 80.0,
        maintenanceCaloriesStart: 2500,
        proteinTarget: 160,
        fatTarget: 70,
        carbTarget: 250,
        fiberTarget: 38,
        mode: GoalMode.lose,
        calculationMode: MacroCalculationMode.proteinCarbs,
        proteinTargetMode: ProteinTargetMode.fixed,
        proteinMultiplier: 1.0,
        fixedDelta: 0,
        lastTargetUpdate: DateTime(2023, 10, 1),
      );

      final json = settings.toJson();
      final decoded = GoalSettings.fromJson(json);

      expect(decoded.anchorWeight, settings.anchorWeight);
      expect(
        decoded.maintenanceCaloriesStart,
        settings.maintenanceCaloriesStart,
      );
      expect(decoded.proteinTarget, settings.proteinTarget);
      expect(decoded.fatTarget, settings.fatTarget);
      expect(decoded.carbTarget, settings.carbTarget);
      expect(decoded.mode, settings.mode);
      expect(decoded.calculationMode, settings.calculationMode);
      expect(decoded.fixedDelta, settings.fixedDelta);
      expect(
        decoded.lastTargetUpdate.millisecondsSinceEpoch,
        settings.lastTargetUpdate.millisecondsSinceEpoch,
      );
    });

    test('default settings should be correct', () {
      final settings = GoalSettings.defaultSettings();
      expect(settings.mode, GoalMode.maintain);
      expect(settings.anchorWeight, 0.0);
    });

    test('old JSON without tdeeWindowDays defaults to 28', () {
      final oldJson = {
        'anchorWeight': 80.0,
        'maintenanceCaloriesStart': 2500.0,
        'proteinTarget': 160.0,
        'fatTarget': 70.0,
        'carbTarget': 250.0,
        'fiberTarget': 38.0,
        'mode': 'GoalMode.lose',
        'calculationMode': 'MacroCalculationMode.proteinCarbs',
        'fixedDelta': 500.0,
        'lastTargetUpdate': DateTime(2023, 10, 1).millisecondsSinceEpoch,
        'isSet': true,
        'enableSmartTargets': true,
      };

      final decoded = GoalSettings.fromJson(oldJson);
      expect(decoded.tdeeWindowDays, 28);
    });

    test('toJson includes tdeeWindowDays', () {
      final settings = GoalSettings.defaultSettings();
      final json = settings.toJson();
      expect(json['tdeeWindowDays'], 28);
    });

    test('tdeeWindowDays roundtrips through JSON', () {
      final settings = GoalSettings.defaultSettings().copyWith(
        tdeeWindowDays: 60,
      );
      final json = settings.toJson();
      final decoded = GoalSettings.fromJson(json);
      expect(decoded.tdeeWindowDays, 60);
    });
  });

  group('MacroGoals', () {
    test('toJson and fromJson should be symmetric', () {
      final goals = MacroGoals(
        calories: 2000,
        protein: 150,
        fat: 60,
        carbs: 215,
        fiber: 30,
      );

      final json = goals.toJson();
      final decoded = MacroGoals.fromJson(json);

      expect(decoded.calories, goals.calories);
      expect(decoded.protein, goals.protein);
      expect(decoded.fat, goals.fat);
      expect(decoded.carbs, goals.carbs);
      expect(decoded.fiber, goals.fiber);
    });
  });
}
