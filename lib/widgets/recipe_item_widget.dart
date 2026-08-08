import 'package:flutter/material.dart';
import 'package:meal_of_record/models/recipe_item.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:provider/provider.dart';

class RecipeItemWidget extends StatelessWidget {
  final RecipeItem item;
  final VoidCallback? onEdit;

  const RecipeItemWidget({super.key, required this.item, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final useNetCarbs = Provider.of<GoalsProvider>(
      context,
      listen: false,
    ).useNetCarbs;
    final calories = item.calories * item.grams;
    final protein = item.protein * item.grams;
    final fat = item.fat * item.grams;
    final carbs = (useNetCarbs ? item.netCarbs : item.carbs) * item.grams;
    final fiber = item.fiber * item.grams;

    return ListTile(
      leading: FoodImageWidget(
        food: item.isFood ? item.food : item.recipe?.toFood(),
        size: 40.0,
      ),
      title: Text(item.name),
      subtitle: Text(
        '${calories.round()}🔥 • ${protein.toStringAsFixed(0)}P • ${fat.toStringAsFixed(0)}F • ${carbs.toStringAsFixed(0)}C • ${fiber.toStringAsFixed(0)}Fb',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${item.grams.toStringAsFixed(0)}g', // Currently RecipeItem only stores grams natively
          ),
          const SizedBox(width: 8),
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}
