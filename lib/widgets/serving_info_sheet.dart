import 'package:flutter/material.dart';
import 'package:meal_of_record/config/app_colors.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:provider/provider.dart';

/// Shows a bottom sheet with all serving sizes and their calculated macros.
/// Designed for easy reading, not editing.
Future<void> showServingInfoSheet(BuildContext context, Food food) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ServingInfoSheet(food: food),
  );
}

class ServingInfoSheet extends StatelessWidget {
  final Food food;

  const ServingInfoSheet({super.key, required this.food});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.largeWidgetBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        food.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Servings list
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  children: [
                    // Always show per 100g first
                    _buildServingCard(context, label: '100g', grams: 100),
                    const SizedBox(height: 8),
                    // Then show all other servings
                    ...food.servings
                        .where((s) => s.unit != 'g')
                        .map(
                          (serving) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildServingCard(
                              context,
                              label: _formatServingLabel(serving),
                              grams: serving.grams,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatServingLabel(FoodServing serving) {
    final qty = serving.quantity;
    final qtyStr = qty == qty.roundToDouble()
        ? qty.round().toString()
        : qty.toStringAsFixed(1);
    return '$qtyStr ${serving.unit} (${serving.grams.toStringAsFixed(0)}g)';
  }

  Widget _buildServingCard(
    BuildContext context, {
    required String label,
    required double grams,
  }) {
    // Calculate macros for this serving size
    final useNetCarbs = Provider.of<GoalsProvider>(
      context,
      listen: false,
    ).useNetCarbs;
    final calories = food.calories * grams;
    final protein = food.protein * grams;
    final fat = food.fat * grams;
    final carbs = (useNetCarbs ? food.netCarbs : food.carbs) * grams;
    final fiber = food.fiber * grams;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.smallWidgetBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildMacroRow('Calories', _formatMacro(calories), 'cal'),
          _buildMacroRow('Protein', _formatMacro(protein), 'g'),
          _buildMacroRow('Fat', _formatMacro(fat), 'g'),
          _buildMacroRow(
            useNetCarbs ? 'Net Carbs' : 'Carbs',
            _formatMacro(carbs),
            'g',
          ),
          _buildMacroRow('Fiber', _formatMacro(fiber), 'g'),
        ],
      ),
    );
  }

  Widget _buildMacroRow(String label, String value, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: Text(
              '$value $unit',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMacro(double value) {
    if (value == 0) return '0';
    if (value < 1) return value.toStringAsFixed(1);
    return value.toStringAsFixed(0);
  }
}
