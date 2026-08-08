import 'dart:math';
import 'package:meal_of_record/models/daily_macro_stats.dart';
import 'package:meal_of_record/models/weight.dart';

class KalmanEstimate {
  final double tdee;
  final double weight;

  const KalmanEstimate({required this.tdee, required this.weight});
}

class GoalLogicService {
  static const int kTdeeWindowDays = 28;
  static const int kMinWeightDays = 20; // 70% of default 28
  static const double kCalPerLb = 3500.0;

  /// Calculates the smoothed "Trend Weight" from history.
  /// Uses a simple Exponential Moving Average (EMA).
  static double calculateTrendWeight(List<Weight> history) {
    if (history.isEmpty) return 0.0;
    if (history.length == 1) return history.first.weight;

    // Sort history by date just in case
    final sorted = List<Weight>.from(history)
      ..sort((a, b) => a.date.compareTo(b.date));

    // Alpha for EMA. 0.1 to 0.2 is typically good for weight.
    // We'll use 0.15 to be responsive but stable.
    const double alpha = 0.15;
    double ema = sorted.first.weight;

    for (var i = 1; i < sorted.length; i++) {
      ema = alpha * sorted[i].weight + (1 - alpha) * ema;
    }

    return ema;
  }

  /// Calculates a list of trend weights corresponding to each entry in history.
  static List<double> calculateTrendHistory(List<Weight> history) {
    if (history.isEmpty) return [];

    final sorted = List<Weight>.from(history)
      ..sort((a, b) => a.date.compareTo(b.date));

    const double alpha = 0.15;
    double ema = sorted.first.weight;
    final trends = <double>[ema];

    for (var i = 1; i < sorted.length; i++) {
      ema = alpha * sorted[i].weight + (1 - alpha) * ema;
      trends.add(ema);
    }

    return trends;
  }

  /// Calculates the macro targets based on a calorie budget and fixed P/F targets.
  /// Carbs are the remainder.
  static Map<String, double> calculateMacrosFromProteinFat({
    required double targetCalories,
    required double proteinGrams,
    required double fatGrams,
  }) {
    final proteinCalories = proteinGrams * 4.0;
    final fatCalories = fatGrams * 9.0;

    final remainingCalories = targetCalories - proteinCalories - fatCalories;
    final carbGrams = max(0.0, remainingCalories / 4.0);

    return {
      'calories': targetCalories,
      'protein': proteinGrams,
      'fat': fatGrams,
      'carbs': carbGrams,
    };
  }

  /// Calculates the macro targets based on a calorie budget and fixed P/C targets.
  /// Fat is the remainder.
  static Map<String, double> calculateMacrosFromProteinCarbs({
    required double targetCalories,
    required double proteinGrams,
    required double carbGrams,
  }) {
    final proteinCalories = proteinGrams * 4.0;
    final carbCalories = carbGrams * 4.0;

    final remainingCalories = targetCalories - proteinCalories - carbCalories;
    final fatGrams = max(0.0, remainingCalories / 9.0);

    return {
      'calories': targetCalories,
      'protein': proteinGrams,
      'fat': fatGrams,
      'carbs': carbGrams,
    };
  }

  /// Legacy helper for calculateMacros (defaults to Protein + Fat input)
  static Map<String, double> calculateMacros({
    required double targetCalories,
    required double proteinGrams,
    required double fatGrams,
  }) {
    return calculateMacrosFromProteinFat(
      targetCalories: targetCalories,
      proteinGrams: proteinGrams,
      fatGrams: fatGrams,
    );
  }

  /// Estimates TDEE using a Kalman Filter approach.
  /// x = [Weight, TDEE]
  static List<KalmanEstimate> calculateKalmanTDEE({
    required List<double> weights, // Daily weights (0.0 if missing)
    required List<double> intakes, // Daily caloric intakes
    required double initialTDEE,
    required double initialWeight,
    List<bool>? intakeIsValid, // null = all valid
  }) {
    if (weights.isEmpty || intakes.isEmpty) return [];

    final double C = kCalPerLb;
    final double invC = 1.0 / C;

    // State initialization
    double xWeight = initialWeight;
    double xTdee = initialTDEE;

    // Covariance initialization
    double pWW = 1.0;
    double pWT = 0.0;
    double pTW = 0.0;
    double pTT = 10000.0; // High uncertainty for TDEE

    // Noise parameters
    const double qWW = 0.0001;
    const double qTT = 400.0; // TDEE can drift (std dev ~20 cal)
    const double rW = 1.0; // Weight scale noise

    final List<KalmanEstimate> estimates = [];

    for (int i = 0; i < weights.length; i++) {
      final double observedWeight = weights[i];

      // Use current TDEE estimate as intake when data is missing (neutral)
      final double effectiveIntake = (intakeIsValid == null || intakeIsValid[i])
          ? intakes[i]
          : xTdee;

      // 1. Predict
      // x = Fx + Bu
      // F = [1, -invC; 0, 1], B = [invC; 0]
      xWeight = xWeight + invC * (effectiveIntake - xTdee);
      // xTdee remains same

      // P = FPF' + Q
      final double nextPWW = pWW - invC * pTW - invC * (pWT - invC * pTT) + qWW;
      final double nextPWT = pWT - invC * pTT;
      final double nextPTW = pTW - invC * pTT;
      final double nextPTT = pTT + qTT;

      pWW = nextPWW;
      pWT = nextPWT;
      pTW = nextPTW;
      pTT = nextPTT;

      // 2. Update (if weight is available)
      if (observedWeight > 0) {
        final double z = observedWeight - xWeight;
        final double s = pWW + rW;
        final double kW = pWW / s;
        final double kT = pTW / s;

        xWeight = xWeight + kW * z;
        xTdee = xTdee + kT * z;

        // P = (I - KH)P
        final oldPWW = pWW;
        final oldPWT = pWT;
        pWW = (1.0 - kW) * oldPWW;
        pWT = (1.0 - kW) * oldPWT;
        pTW = pTW - kT * oldPWW;
        pTT = pTT - kT * oldPWT;
      }

      estimates.add(KalmanEstimate(tdee: xTdee, weight: xWeight));
    }

    return estimates;
  }

  /// Returns true if there are at least 70% of [windowDays] weight entries
  /// within the last [windowDays] days.
  static bool hasEnoughWeightData(
    List<Weight> weights, {
    int windowDays = kTdeeWindowDays,
    int? minDays,
    DateTime? now,
  }) {
    final threshold = minDays ?? (windowDays * 0.7).ceil();
    final today = now ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final cutoff = DateTime(
      todayDate.year,
      todayDate.month,
      todayDate.day - windowDays,
    );
    final recentCount = weights.where((w) {
      final d = DateTime(w.date.year, w.date.month, w.date.day);
      return !d.isBefore(cutoff);
    }).length;
    return recentCount >= threshold;
  }

  /// Determines the effective TDEE window based on available data.
  /// Falls back to the largest tier <= userWindow that has enough data.
  /// Returns 0 if not enough data for any tier.
  static int effectiveWindow(int userWindow, int daysOfData) {
    const tiers = [60, 28, 14];
    for (final t in tiers) {
      if (t <= userWindow && t <= daysOfData) return t;
    }
    return 0; // not enough data
  }

  /// Computes the Kalman TDEE as of a given date.
  /// [tdeeWindow] — user-configured TDEE window (e.g. 28).
  /// [tdeeDate] — reference date; TDEE is reported as of dt-1 (yesterday relative to dt).
  /// [weightMap] — pre-loaded {date: weight} map covering the needed range.
  /// [statsMap] — pre-loaded {date: DailyMacroStats} map.
  /// [initialTDEE], [initialWeight], [isMetric] — Kalman seed params.
  /// Returns null if not enough data.
  static KalmanEstimate? computeTdeeAtDate({
    required int tdeeWindow,
    required DateTime tdeeDate,
    required Map<DateTime, double> weightMap,
    required Map<DateTime, DailyMacroStats> statsMap,
    required double initialTDEE,
  }) {
    // Find earliest weight in weightMap to compute daysOfData
    if (weightMap.isEmpty) return null;
    final earliestWeight = weightMap.keys.reduce(
      (a, b) => a.isBefore(b) ? a : b,
    );
    final tdeeDateUtc = DateTime.utc(
      tdeeDate.year,
      tdeeDate.month,
      tdeeDate.day,
    );
    final earliestUtc = DateTime.utc(
      earliestWeight.year,
      earliestWeight.month,
      earliestWeight.day,
    );
    final daysOfData = tdeeDateUtc.difference(earliestUtc).inDays;

    final effectiveWin = effectiveWindow(tdeeWindow, daysOfData);
    if (effectiveWin == 0) return null;

    final windowStart = DateTime(
      tdeeDate.year,
      tdeeDate.month,
      tdeeDate.day - effectiveWin,
    );

    // Build parallel arrays from windowStart to dt-1
    final List<double> dailyWeights = [];
    final List<double> dailyIntakes = [];
    final List<bool> intakeIsValid = [];
    final List<Weight> weightsInWindow = [];

    var current = windowStart;
    final yesterday = DateTime(tdeeDate.year, tdeeDate.month, tdeeDate.day - 1);
    while (!current.isAfter(yesterday)) {
      final dateOnly = DateTime(current.year, current.month, current.day);
      final w = weightMap[dateOnly] ?? 0.0;
      dailyWeights.add(w);
      if (w > 0) {
        weightsInWindow.add(Weight(weight: w, date: dateOnly));
      }

      final stat = statsMap[dateOnly];
      dailyIntakes.add(stat?.calories ?? 0.0);
      intakeIsValid.add(stat != null && stat.logCount > 0 && stat.calories > 0);

      current = DateTime(current.year, current.month, current.day + 1);
    }

    // Check we have enough weight data in this window
    if (!hasEnoughWeightData(
      weightsInWindow,
      windowDays: effectiveWin,
      now: tdeeDate,
    )) {
      return null;
    }

    final estimates = calculateKalmanTDEE(
      weights: dailyWeights,
      intakes: dailyIntakes,
      initialTDEE: initialTDEE,
      initialWeight: weightsInWindow.first.weight,
      intakeIsValid: intakeIsValid,
    );

    return estimates.isNotEmpty ? estimates.last : null;
  }
}
