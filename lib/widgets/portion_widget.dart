import 'package:flutter/material.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:provider/provider.dart';

class PortionWidget extends StatelessWidget {
  final FoodPortion portion;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  const PortionWidget({
    super.key,
    required this.portion,
    this.onEdit,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate totals based on the serving size
    // Note: serving.grams is actually the quantity/multiplier for the unit
    // We need to find the unit definition to get the grams per unit
    final unitDef = portion.food.servings.firstWhere(
      (u) => u.unit == portion.unit,
      orElse: () => portion.food.servings.first,
    );

    // serving.grams is now the actual weight in grams
    final totalGrams = portion.grams;
    final useNetCarbs = Provider.of<GoalsProvider>(
      context,
      listen: false,
    ).useNetCarbs;

    final calories = portion.food.calories * totalGrams;
    final protein = portion.food.protein * totalGrams;
    final fat = portion.food.fat * totalGrams;
    final carbs =
        (useNetCarbs ? portion.food.netCarbs : portion.food.carbs) * totalGrams;
    final fiber = portion.food.fiber * totalGrams;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Stack(
            children: [
              FoodImageWidget(food: portion.food, size: 40.0),
              if (isSelected)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(portion.food.name),
          subtitle: Text(
            '${calories.round()}🔥 • ${protein.toStringAsFixed(0)}P • ${fat.toStringAsFixed(0)}F • ${carbs.toStringAsFixed(0)}C • ${fiber.toStringAsFixed(0)}Fb',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${unitDef.quantityFromGrams(totalGrams).toStringAsFixed(0)} ${unitDef.unit}',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
