import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:meal_of_record/models/recipe_item.dart';
import 'package:meal_of_record/widgets/recipe_item_widget.dart';

class SlidableRecipeItemWidget extends StatelessWidget {
  final RecipeItem item;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  const SlidableRecipeItemWidget({
    super.key,
    required this.item,
    required this.index,
    required this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: ValueKey(item),
      startActionPane: onEdit != null
          ? ActionPane(
              motion: const ScrollMotion(),
              children: [
                SlidableAction(
                  onPressed: (context) => onEdit!(),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  icon: Icons.edit,
                  label: 'Edit',
                ),
              ],
            )
          : null,
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (context) => onDelete(),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
          ),
        ],
      ),
      child: Container(
        color: Theme.of(context).canvasColor,
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(Icons.drag_handle, color: Colors.grey),
              ),
            ),
            Expanded(
              child: RecipeItemWidget(item: item, onEdit: onEdit),
            ),
          ],
        ),
      ),
    );
  }
}
