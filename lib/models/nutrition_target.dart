import 'package:flutter/material.dart';

class NutritionTarget {
  final Color color; // The color of the consuming bar chart
  final double thisAmount; // The day's consumed amount of the macro
  final double targetAmount; // The target daily amount
  final String macroLabel; // The abrev. name/label of the macro
  final String unitLabel; // The unit of measure (grams or nothing)
  final List<double> dailyAmounts; // The amounts of macro per day
  final List<double>
  dailyTargets; // The target amounts per day (from snapshots)

  NutritionTarget({
    required this.color,
    required this.thisAmount,
    required this.targetAmount,
    required this.macroLabel,
    required this.unitLabel,
    required this.dailyAmounts,
    this.dailyTargets = const [],
  });
}
