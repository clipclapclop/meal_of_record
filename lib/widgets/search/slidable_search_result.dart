import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart' as model_unit;
import 'package:meal_of_record/widgets/search_result_tile.dart';

class SlidableSearchResult extends StatelessWidget {
  final Food food;
  final void Function(model_unit.FoodServing) onTap;
  final void Function(model_unit.FoodServing)? onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;
  final String? note;
  final bool isUpdate;

  const SlidableSearchResult({
    super.key,
    required this.food,
    required this.onTap,
    this.onAdd,
    this.onEdit,
    this.onCopy,
    this.onDelete,
    this.note,
    this.isUpdate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: ValueKey('${food.id}_${food.source}_${food.sourceBarcode ?? ''}'),
      startActionPane: (onEdit != null || onCopy != null)
          ? ActionPane(
              motion: const ScrollMotion(),
              children: [
                if (onEdit != null)
                  SlidableAction(
                    onPressed: (context) => onEdit!(),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    icon: Icons.edit,
                    label: 'Edit',
                  ),
                if (onCopy != null)
                  SlidableAction(
                    onPressed: (context) => onCopy!(),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    icon: Icons.copy,
                    label: 'Copy',
                  ),
              ],
            )
          : null,
      endActionPane: onDelete != null
          ? ActionPane(
              motion: const ScrollMotion(),
              children: [
                SlidableAction(
                  onPressed: (context) => _confirmDelete(context),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  icon: Icons.delete,
                  label: 'Delete',
                ),
              ],
            )
          : null,
      child: SearchResultTile(
        food: food,
        onTap: onTap,
        onAdd: onAdd,
        note: note,
        isUpdate: isUpdate,
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    if (onDelete == null) return;

    // Only live database foods can be deleted
    if (food.database != FoodDatabase.live) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Delete'),
          content: const Text('Reference foods cannot be deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Food'),
        content: Text('Are you sure you want to delete "${food.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete!();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
