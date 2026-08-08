import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:meal_of_record/models/nutrition_target.dart';
import 'package:meal_of_record/widgets/horizontal_mini_bar_chart.dart';
import 'package:meal_of_record/config/app_colors.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:provider/provider.dart';

class LogHeader extends StatefulWidget {
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final List<NutritionTarget> nutritionTargets;

  const LogHeader({
    super.key,
    required this.date,
    required this.onDateChanged,
    required this.nutritionTargets,
  });

  @override
  State<LogHeader> createState() => _LogHeaderState();
}

class _LogHeaderState extends State<LogHeader> {
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) {
      return 'Today';
    } else if (checkDate == yesterday) {
      return 'Yesterday';
    } else if (checkDate == tomorrow) {
      return 'Tomorrow';
    } else {
      return DateFormat('MMMM d, yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: AppColors.largeWidgetBackground,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () {
                  widget.onDateChanged(
                    DateTime(
                      widget.date.year,
                      widget.date.month,
                      widget.date.day - 1,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8.0),
              Text(
                _formatDate(widget.date),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8.0),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: () {
                  widget.onDateChanged(
                    DateTime(
                      widget.date.year,
                      widget.date.month,
                      widget.date.day + 1,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Consumer<NavigationProvider>(
            builder: (context, navProvider, child) {
              final showConsumed = navProvider.showConsumed;
              return Row(
                children: [
                  Expanded(
                    child: HorizontalMiniBarChart(
                      consumed: widget.nutritionTargets[0].thisAmount,
                      target: widget.nutritionTargets[0].targetAmount,
                      color: widget.nutritionTargets[0].color,
                      macroLabel: widget.nutritionTargets[0].macroLabel,
                      unitLabel: widget.nutritionTargets[0].unitLabel,
                      showConsumed: showConsumed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HorizontalMiniBarChart(
                      consumed: widget.nutritionTargets[1].thisAmount,
                      target: widget.nutritionTargets[1].targetAmount,
                      color: widget.nutritionTargets[1].color,
                      macroLabel: widget.nutritionTargets[1].macroLabel,
                      unitLabel: widget.nutritionTargets[1].unitLabel,
                      showConsumed: showConsumed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HorizontalMiniBarChart(
                      consumed: widget.nutritionTargets[2].thisAmount,
                      target: widget.nutritionTargets[2].targetAmount,
                      color: widget.nutritionTargets[2].color,
                      macroLabel: widget.nutritionTargets[2].macroLabel,
                      unitLabel: widget.nutritionTargets[2].unitLabel,
                      showConsumed: showConsumed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HorizontalMiniBarChart(
                      consumed: widget.nutritionTargets[3].thisAmount,
                      target: widget.nutritionTargets[3].targetAmount,
                      color: widget.nutritionTargets[3].color,
                      macroLabel: widget.nutritionTargets[3].macroLabel,
                      unitLabel: widget.nutritionTargets[3].unitLabel,
                      showConsumed: showConsumed,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
