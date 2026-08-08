import 'package:flutter/material.dart';
import 'package:meal_of_record/models/nutrition_target.dart';
import 'package:meal_of_record/widgets/horizontal_mini_bar_chart.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:provider/provider.dart';

class LogQueueTopRibbon extends StatelessWidget {
  final IconData arrowDirection;
  final VoidCallback onArrowPressed;
  final LogProvider logProvider;
  final Widget? leading;

  const LogQueueTopRibbon({
    super.key,
    required this.arrowDirection,
    required this.onArrowPressed,
    required this.logProvider,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final goalsProvider = Provider.of<GoalsProvider>(context);
    final goals = goalsProvider.currentGoals;
    final useNetCarbs = goalsProvider.useNetCarbs;
    // Helper to create targets for the charts
    NutritionTarget createTarget(
      String label,
      double value,
      double target,
      Color color,
    ) {
      return NutritionTarget(
        color: color,
        thisAmount: value,
        targetAmount: target,
        macroLabel: label,
        unitLabel: label == '🔥' ? '' : 'g',
        dailyAmounts: [],
      );
    }

    // Queue targets are always goals minus what's already logged (no clamp)
    final double targetCal = goals.calories - logProvider.loggedCalories;
    final double targetProt = goals.protein - logProvider.loggedProtein;
    final double targetFat = goals.fat - logProvider.loggedFat;
    final double targetCarb =
        goals.carbs -
        (useNetCarbs ? logProvider.loggedNetCarbs : logProvider.loggedCarbs);
    final double targetFib = goals.fiber - logProvider.loggedFiber;

    final projectedTargets = [
      createTarget(
        '🔥',
        logProvider.totalCalories,
        goals.calories,
        Colors.blue,
      ),
      createTarget('P', logProvider.totalProtein, goals.protein, Colors.red),
      createTarget('F', logProvider.totalFat, goals.fat, Colors.orange),
      createTarget(
        'C',
        useNetCarbs ? logProvider.totalNetCarbs : logProvider.totalCarbs,
        goals.carbs,
        Colors.green,
      ),
      createTarget('Fb', logProvider.totalFiber, goals.fiber, Colors.brown),
    ];

    final queueOnlyTargets = [
      createTarget(
        '🔥',
        logProvider.queuedCalories,
        targetCal,
        Colors.blue.withValues(alpha: 0.7),
      ),
      createTarget(
        'P',
        logProvider.queuedProtein,
        targetProt,
        Colors.red.withValues(alpha: 0.7),
      ),
      createTarget(
        'F',
        logProvider.queuedFat,
        targetFat,
        Colors.orange.withValues(alpha: 0.7),
      ),
      createTarget(
        'C',
        useNetCarbs ? logProvider.queuedNetCarbs : logProvider.queuedCarbs,
        targetCarb,
        Colors.green.withValues(alpha: 0.7),
      ),
      createTarget(
        'Fb',
        logProvider.queuedFiber,
        targetFib,
        Colors.brown.withValues(alpha: 0.7),
      ),
    ];

    Widget buildChartRow(List<NutritionTarget> targets, String label) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 2.0),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Consumer<NavigationProvider>(
            builder: (context, navProvider, child) {
              final showConsumed = navProvider.showConsumed;
              return Row(
                children: targets
                    .map(
                      (target) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: HorizontalMiniBarChart(
                            consumed: target.thisAmount,
                            target: target.targetAmount,
                            color: target.color,
                            macroLabel: target.macroLabel,
                            unitLabel: target.unitLabel,
                            showConsumed: showConsumed,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min, // Important for AppBar usage
      children: [
        // Row 1: Icons
        Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8.0)],
            Expanded(
              child: Container(
                height: 30.0,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(5.0),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: logProvider.logQueue.map((serving) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: FoodImageWidget(food: serving.food, size: 26.0),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            IconButton(icon: Icon(arrowDirection), onPressed: onArrowPressed),
          ],
        ),
        const SizedBox(height: 8.0),
        // Row 2: Day's Charts
        buildChartRow(projectedTargets, "Day's Macros (Projected)"),
        const SizedBox(height: 4.0),
        // Row 3: Queue's Charts
        buildChartRow(queueOnlyTargets, "Queue's Macros"),
      ],
    );
  }
}
