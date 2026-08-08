import 'package:flutter/material.dart';
import 'package:meal_of_record/config/app_colors.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/food_serving.dart' as model_unit;
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:provider/provider.dart';

class SearchResultTile extends StatefulWidget {
  final Food food;
  final void Function(model_unit.FoodServing) onTap;
  final void Function(model_unit.FoodServing)? onAdd;
  final String? note;
  final bool isUpdate;

  const SearchResultTile({
    super.key,
    required this.food,
    required this.onTap,
    this.onAdd,
    this.note,
    this.isUpdate = false,
  });

  @override
  State<SearchResultTile> createState() => SearchResultTileState();
}

class SearchResultTileState extends State<SearchResultTile> {
  model_unit.FoodServing get currentServing => _getServingWithDisplayQuantity();

  late model_unit.FoodServing _selectedUnit;
  late List<model_unit.FoodServing> _availableServings;
  late double _displayQuantity;

  @override
  void initState() {
    super.initState();
    _initializeServings();

    if (widget.food.id != 0) {
      _loadLastLoggedInfo();
    }
  }

  @override
  void didUpdateWidget(covariant SearchResultTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list view recycles State objects. When this tile is reused for a
    // different food (notably OFF results, which all share id 0/source 'off'),
    // rebuild the serving dropdown so it doesn't show the previous food's units.
    final oldFood = oldWidget.food;
    final newFood = widget.food;
    if (!_isSameFood(oldFood, newFood)) {
      _initializeServings();
      if (newFood.id != 0) {
        _loadLastLoggedInfo();
      }
    }
  }

  void _initializeServings() {
    _availableServings = List.of(widget.food.servings);

    // Default to first non-g serving (the "primary serving")
    // Fall back to 'g' if no other servings exist
    _selectedUnit = _availableServings.firstWhere(
      (u) => u.unit != 'g',
      orElse: () => _availableServings.firstWhere(
        (u) => u.unit == 'g',
        orElse: () => _availableServings.first,
      ),
    );
    _displayQuantity = _selectedUnit.quantity;
  }

  bool _isSameFood(Food first, Food second) {
    return first.id == second.id &&
        first.source == second.source &&
        first.sourceBarcode == second.sourceBarcode;
  }

  Future<void> _loadLastLoggedInfo() async {
    final food = widget.food;
    try {
      final LastLoggedInfo? lastInfo;
      if (food.source == 'recipe') {
        lastInfo = await DatabaseService.instance.getLastLoggedInfoForRecipe(
          food.id,
        );
      } else {
        lastInfo = await DatabaseService.instance.getLastLoggedInfo(food.id);
      }
      if (!mounted || !_isSameFood(food, widget.food)) return;

      if (lastInfo != null) {
        final info = lastInfo;
        final servingIndex = _availableServings.indexWhere(
          (s) => s.unit == info.unit,
        );
        if (servingIndex != -1) {
          setState(() {
            final serving = _availableServings.removeAt(servingIndex);
            _availableServings.insert(0, serving);
            _selectedUnit = serving;
            _displayQuantity = info.quantity;
          });
        }
      }
    } catch (e) {
      // Ignore DB errors in UI
      debugPrint('Error loading last logged info: $e');
    }
  }

  Color _getBackgroundColor(BuildContext context) {
    // Live foods use default color (logged), except recipes keep their color
    if (widget.food.database == FoodDatabase.live) {
      if (widget.food.source == 'recipe') {
        return AppColors.searchResultRecipe;
      }
      return Theme.of(context).canvasColor;
    }

    // Reference/OFF foods get color-coded by source
    switch (widget.food.source) {
      case 'FOUNDATION':
        return AppColors.searchResultBetter;
      case 'SR_LEGACY':
        return AppColors.searchResultGood;
      case 'off':
        return AppColors.searchResultBest;
      default:
        return Theme.of(context).canvasColor;
    }
  }

  void _showImagePopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Dialog(
          child: GestureDetector(
            onTap: () {}, // Prevent tap from propagating to parent
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 300,
                    height: 300,
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: _buildPopupImage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopupImage() {
    return FoodImageWidget(food: widget.food, size: 300);
  }

  /// Creates a FoodServing with the current display quantity
  model_unit.FoodServing _getServingWithDisplayQuantity() {
    return model_unit.FoodServing(
      id: _selectedUnit.id,
      foodId: _selectedUnit.foodId,
      unit: _selectedUnit.unit,
      grams: _selectedUnit.gramsPerUnit * _displayQuantity,
      quantity: _displayQuantity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayGrams = _selectedUnit.gramsPerUnit * _displayQuantity;
    final useNetCarbs = Provider.of<GoalsProvider>(
      context,
      listen: false,
    ).useNetCarbs;
    final calories = widget.food.calories * displayGrams;
    final protein = widget.food.protein * displayGrams;
    final fat = widget.food.fat * displayGrams;
    final carbs =
        (useNetCarbs ? widget.food.netCarbs : widget.food.carbs) * displayGrams;
    final fiber = widget.food.fiber * displayGrams;

    return ListTile(
      tileColor: _getBackgroundColor(context),
      leading: FoodImageWidget(
        food: widget.food,
        size: 40.0,
        onTap: () => _showImagePopup(context),
      ),
      title: Row(
        children: [
          Expanded(child: Text(widget.food.name)),
          if (widget.note != null)
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                widget.note!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${calories.round()}🔥 • ${protein.toStringAsFixed(0)}P • ${fat.toStringAsFixed(0)}F • ${carbs.toStringAsFixed(0)}C • ${fiber.toStringAsFixed(0)}Fb',
          ),
          DropdownButton<model_unit.FoodServing>(
            value: _selectedUnit,
            items: _availableServings.map((unit) {
              // Show _displayQuantity for selected unit, serving definition for others
              final qty = (unit == _selectedUnit)
                  ? _displayQuantity
                  : unit.quantity;
              // For 'g' unit, just show "1 g" (no redundant grams display)
              // For other units, show "1 serving (27g)"
              final label = unit.unit == 'g'
                  ? '$qty ${unit.unit}'
                  : '$qty ${unit.unit} (${(unit.gramsPerUnit * qty).toStringAsFixed(0)}g)';
              return DropdownMenuItem(value: unit, child: Text(label));
            }).toList(),
            onChanged: (unit) {
              if (unit != null) {
                setState(() {
                  _selectedUnit = unit;
                  _displayQuantity =
                      unit.quantity; // Reset to serving definition
                });
              }
            },
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(widget.isUpdate ? Icons.edit : Icons.add),
        onPressed: () {
          final servingToPass = _getServingWithDisplayQuantity();
          if (widget.onAdd != null) {
            widget.onAdd!(servingToPass);
          } else {
            final logProvider = Provider.of<LogProvider>(
              context,
              listen: false,
            );
            final serving = FoodPortion(
              food: widget.food,
              grams: servingToPass.grams,
              unit: servingToPass.unit,
            );
            logProvider.addFoodToQueue(serving);
          }
        },
      ),
      onTap: () => widget.onTap(_getServingWithDisplayQuantity()),
    );
  }
}
