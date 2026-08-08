import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/utils/math_evaluator.dart';
import 'package:meal_of_record/utils/quantity_edit_utils.dart';
import 'package:meal_of_record/widgets/horizontal_mini_bar_chart.dart';
import 'package:meal_of_record/screens/food_edit_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/utils/ui_utils.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/food_container.dart';
import 'package:meal_of_record/widgets/serving_info_sheet.dart';
import 'package:meal_of_record/widgets/math_input_bar.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:meal_of_record/screens/qr_portion_sharing_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class QuantityEditScreen extends StatefulWidget {
  final QuantityEditConfig config;

  const QuantityEditScreen({super.key, required this.config});

  @override
  State<QuantityEditScreen> createState() => _QuantityEditScreenState();
}

class _QuantityEditScreenState extends State<QuantityEditScreen> {
  final TextEditingController _quantityController = TextEditingController();
  final FocusNode _quantityFocusNode = FocusNode();
  late String _selectedUnit;
  bool _isQuantityFocused = false;
  int _selectedTargetIndex = 0; // 0: Unit, 1: Cal, 2: Protein, 3: Fat, 4: Carbs
  bool _isPerServing = false;
  late Food _food;
  String? _recipeLink;

  @override
  void initState() {
    super.initState();
    _food = widget.config.food;
    _loadRecipeLink();
    _quantityController.text = widget.config.initialQuantity.toString();
    _selectedUnit = widget.config.initialUnit;
    _quantityFocusNode.addListener(_onQuantityFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quantityFocusNode.requestFocus();
      _quantityController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _quantityController.text.length,
      );
    });
  }

  Future<void> _loadRecipeLink() async {
    if (_food.source != 'recipe') return;
    try {
      final recipe = await DatabaseService.instance.getRecipeById(_food.id);
      if (mounted && recipe.link != null && recipe.link!.isNotEmpty) {
        setState(() {
          _recipeLink = recipe.link;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _quantityFocusNode.removeListener(_onQuantityFocusChange);
    _quantityFocusNode.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _onQuantityFocusChange() {
    setState(() {
      _isQuantityFocused = _quantityFocusNode.hasFocus;
    });
    if (!_quantityFocusNode.hasFocus) {
      _evaluateAndReplaceExpression();
    }
  }

  void _evaluateAndReplaceExpression() {
    final text = _quantityController.text;
    if (text.isEmpty) return;

    // Extract suffix if present (e.g., " cal", " g protein")
    final suffixMatch = RegExp(r'(\s+[a-zA-Z].*)$').firstMatch(text);
    final suffix = suffixMatch?.group(0) ?? '';
    final expression = text.replaceAll(RegExp(r'\s+[a-zA-Z].*$'), '').trim();

    // Skip if it's already just a number (no math operators)
    if (double.tryParse(expression) != null) return;

    // Skip if expression is empty after stripping
    if (expression.isEmpty) return;

    final result = MathEvaluator.evaluate(expression);

    if (result == null || result.isInfinite || result.isNaN) {
      // Invalid expression - show error, refocus
      _showExpressionError();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _quantityFocusNode.requestFocus();
      });
      return;
    }

    // Format result and replace
    final formatted = _formatResult(result);
    setState(() {
      _quantityController.text = suffix.isNotEmpty
          ? '$formatted$suffix'
          : formatted;
    });
  }

  String _formatResult(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  void _showExpressionError() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invalid expression')));
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final showOperatorBar = _isQuantityFocused && keyboardHeight > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.config.isUpdate ? 'Update Quantity' : 'Add Quantity',
        ),
        actions: [
          if (widget.config.canShare)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share',
              onPressed: _handleShare,
            ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Definition',
            onPressed: _handleEditDefinition,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 12.0,
              right: 12.0,
              top: 8.0,
              bottom: 8.0 + (showOperatorBar ? 48 + keyboardHeight : 0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFoodHeader(),
                const SizedBox(height: 8),
                _buildMacroDisplay(),
                const SizedBox(height: 8),
                _buildResultsActions(),
                const SizedBox(height: 8),
                _buildInputSection(),
                const SizedBox(height: 8),
                if (widget.config.context == QuantityEditContext.recipe)
                  _buildRecipeToggle(),
                const SizedBox(height: 8),
                _buildTargetSelection(),
                const SizedBox(height: 16),
                if (_recipeLink != null)
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        launchUrl(
                          Uri.parse(_recipeLink!),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.link, size: 18),
                      label: Text(
                        _recipeLink!.length > 40
                            ? '${_recipeLink!.substring(0, 40)}...'
                            : _recipeLink!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showServingInfoSheet(context, _food),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('View Servings'),
                  ),
                ),
              ],
            ),
          ),
          if (showOperatorBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboardHeight,
              child: MathInputBar(controller: _quantityController),
            ),
        ],
      ),
    );
  }

  Widget _buildMacroDisplay() {
    final currentGrams = _calculateCurrentGrams();
    final food = _food;

    return Consumer4<
      LogProvider,
      RecipeProvider,
      GoalsProvider,
      NavigationProvider
    >(
      builder:
          (
            context,
            logProvider,
            recipeProvider,
            goalsProvider,
            navProvider,
            _,
          ) {
            final isRecipe =
                widget.config.context == QuantityEditContext.recipe;
            final showConsumed = navProvider.showConsumed;

            final servings =
                (isRecipe &&
                    widget.config.recipeServings != null &&
                    widget.config.recipeServings! > 0)
                ? widget.config.recipeServings!
                : 1.0;

            final divisor = (isRecipe && _isPerServing) ? servings : 1.0;

            final useNetCarbs = goalsProvider.useNetCarbs;

            // 1. Item Macros
            final itemValues = QuantityEditUtils.calculatePortionMacros(
              food,
              currentGrams,
              divisor,
              useNetCarbs: useNetCarbs,
            );

            // 2. Parent Macros (Projected)
            final parentValues =
                QuantityEditUtils.calculateParentProjectedMacros(
                  totalCalories: isRecipe
                      ? recipeProvider.totalCalories
                      : logProvider.totalCalories,
                  totalProtein: isRecipe
                      ? recipeProvider.totalProtein
                      : logProvider.totalProtein,
                  totalFat: isRecipe
                      ? recipeProvider.totalFat
                      : logProvider.totalFat,
                  totalCarbs: isRecipe
                      ? recipeProvider.totalCarbs
                      : (useNetCarbs
                            ? logProvider.totalNetCarbs
                            : logProvider.totalCarbs),
                  totalFiber: isRecipe
                      ? recipeProvider.totalFiber
                      : logProvider.totalFiber,
                  food: food,
                  currentGrams: currentGrams,
                  originalGrams: widget.config.originalGrams,
                  divisor: divisor,
                );

            final dailyGoals = _getGoals(goalsProvider);
            Map<String, double> portionTargets = dailyGoals;

            if (!showConsumed && !isRecipe) {
              final og = widget.config.originalGrams;
              portionTargets = {
                'Calories':
                    (dailyGoals['Calories']! -
                            logProvider.totalCalories +
                            food.calories * og)
                        .clamp(0, double.infinity),
                'Protein':
                    (dailyGoals['Protein']! -
                            logProvider.totalProtein +
                            food.protein * og)
                        .clamp(0, double.infinity),
                'Fat':
                    (dailyGoals['Fat']! - logProvider.totalFat + food.fat * og)
                        .clamp(0, double.infinity),
                'Carbs':
                    (dailyGoals['Carbs']! -
                            (useNetCarbs
                                ? logProvider.totalNetCarbs
                                : logProvider.totalCarbs) +
                            (useNetCarbs ? food.netCarbs : food.carbs) * og)
                        .clamp(0, double.infinity),
                'Fiber':
                    (dailyGoals['Fiber']! -
                            logProvider.totalFiber +
                            food.fiber * og)
                        .clamp(0, double.infinity),
              };
            }

            return Column(
              children: [
                _buildChartSection(
                  isRecipe ? "Recipe's Macros" : "Day's Macros",
                  parentValues,
                  isRecipe ? null : dailyGoals,
                  showConsumed,
                ),
                const SizedBox(height: 6),
                _buildChartSection(
                  isRecipe ? "Ingredient's Macros" : "Portion's Macros",
                  itemValues,
                  isRecipe ? null : portionTargets,
                  showConsumed,
                ),
              ],
            );
          },
    );
  }

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _quantityController,
          focusNode: _quantityFocusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onTap: () {
            _quantityController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _quantityController.text.length,
            );
          },
        ),
        const SizedBox(height: 8),
        // Action buttons row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Fill to Target button (hidden in recipe context)
            if (widget.config.context != QuantityEditContext.recipe)
              TextButton.icon(
                onPressed: _handleFillToTarget,
                icon: const Icon(Icons.gps_fixed, size: 18),
                label: const Text('Fill to Target'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            else
              const SizedBox.shrink(),
            // Minus Container button
            TextButton.icon(
              onPressed: _showContainerSelection,
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              label: const Text('Minus Container'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Unit', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Result: ${_calculateCurrentGrams().toStringAsFixed(0)}g',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _food.servings.map((s) {
            final isSelected = _selectedUnit == s.unit;
            return ChoiceChip(
              label: Text(s.unit),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedUnit = s.unit;
                    _selectedTargetIndex =
                        0; // Selecting a unit switches target to "Unit"
                  });
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTargetSelection() {
    final targets = ['Unit', 'Calories', 'Protein', 'Fat', 'Carbs', 'Fiber'];
    return ToggleButtons(
      isSelected: List.generate(
        targets.length,
        (i) => i == _selectedTargetIndex,
      ),
      onPressed: (index) => setState(() {
        _selectedTargetIndex = index;
        if (index != 0) {
          // Selecting a macro target switches unit to "g" (if available)
          final gramServing = _food.servings.firstWhere(
            (s) => s.unit == 'g' || s.unit == 'gram',
            orElse: () => _food.servings.first,
          );
          if (gramServing.unit == 'g' || gramServing.unit == 'gram') {
            _selectedUnit = gramServing.unit;
          }
        }
      }),
      children: targets
          .map(
            (t) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(t),
            ),
          )
          .toList(),
    );
  }

  Widget _buildResultsActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _handleSave,
            child: Text(widget.config.isUpdate ? 'Update' : 'Add'),
          ),
        ),
      ],
    );
  }

  Widget _buildRecipeToggle() {
    return Row(
      children: [
        const Text('Visualize: '),
        const SizedBox(width: 8),
        ToggleButtons(
          isSelected: [!_isPerServing, _isPerServing],
          onPressed: (index) => setState(() => _isPerServing = index == 1),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Total'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Per Serving'),
            ),
          ],
        ),
      ],
    );
  }

  double _calculateCurrentGrams() {
    // Strip any trailing suffix text (e.g., " cal", " g protein")
    final text = _quantityController.text
        .replaceAll(RegExp(r'\s+[a-zA-Z].*$'), '')
        .trim();
    final quantity = MathEvaluator.evaluate(text) ?? 0.0;
    final useNetCarbs = Provider.of<GoalsProvider>(
      context,
      listen: false,
    ).useNetCarbs;
    return QuantityEditUtils.calculateGrams(
      quantity: quantity,
      food: _food,
      selectedUnit: _selectedUnit,
      selectedTargetIndex: _selectedTargetIndex,
      useNetCarbs: useNetCarbs,
    );
  }

  Map<String, double> _getGoals(GoalsProvider provider) {
    final goals = provider.currentGoals;
    return {
      'Calories': goals.calories,
      'Protein': goals.protein,
      'Fat': goals.fat,
      'Carbs': goals.carbs,
      'Fiber': goals.fiber,
    };
  }

  Widget _buildChartSection(
    String title,
    Map<String, double> values,
    Map<String, double>? targets,
    bool showConsumed,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _buildMiniBar(
                    '🔥',
                    values['Calories']!,
                    targets?['Calories'] ?? 0,
                    Colors.orange,
                    showConsumed,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildMiniBar(
                    'P',
                    values['Protein']!,
                    targets?['Protein'] ?? 0,
                    Colors.red,
                    showConsumed,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildMiniBar(
                    'F',
                    values['Fat']!,
                    targets?['Fat'] ?? 0,
                    Colors.yellow,
                    showConsumed,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildMiniBar(
                    'C',
                    values['Carbs']!,
                    targets?['Carbs'] ?? 0,
                    Colors.green,
                    showConsumed,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildMiniBar(
                    'Fb',
                    values['Fiber']!,
                    targets?['Fiber'] ?? 0,
                    Colors.brown,
                    showConsumed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBar(
    String label,
    double value,
    double target,
    Color color,
    bool showConsumed,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: HorizontalMiniBarChart(
        consumed: value,
        target: target,
        color: color,
        macroLabel: label,
        showConsumed: showConsumed,
      ),
    );
  }

  Widget _buildFoodHeader() {
    return Column(
      children: [
        FoodImageWidget(food: _food, size: 80.0),
        const SizedBox(height: 8),
        Text(
          _food.name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _handleSave() {
    final grams = _calculateCurrentGrams();
    if (grams > 0) {
      Navigator.pop(
        context,
        FoodPortion(food: _food, grams: grams, unit: _selectedUnit),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
    }
  }

  void _handleShare() {
    final grams = _calculateCurrentGrams();
    if (grams <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    final recipe = widget.config.sourceRecipe;
    List<FoodPortion> portions;

    if (recipe != null && recipe.isTemplate) {
      // Dump-only recipe: compute proportionally-scaled ingredient list
      final quantity = grams / recipe.totalGrams;
      final logProvider = Provider.of<LogProvider>(context, listen: false);
      portions = logProvider.dumpRecipePortionsAsList(
        recipe,
        quantity: quantity,
      );
    } else if (recipe != null) {
      // Normal recipe: share the single portion
      portions = [FoodPortion(food: _food, grams: grams, unit: _selectedUnit)];
    } else {
      // Plain food
      portions = [FoodPortion(food: _food, grams: grams, unit: _selectedUnit)];
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrPortionSharingScreen(portions: portions),
      ),
    );
  }

  void _handleFillToTarget() {
    // Check if Unit target is selected
    if (_selectedTargetIndex == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a macro target first')),
      );
      return;
    }

    // Get providers
    final goalsProvider = Provider.of<GoalsProvider>(context, listen: false);
    final logProvider = Provider.of<LogProvider>(context, listen: false);

    // Calculate remaining (subtract original contribution when editing)
    final goal = _getGoalForTarget(goalsProvider, _selectedTargetIndex);
    final total = _getTotalForTarget(logProvider, _selectedTargetIndex);
    final originalContribution =
        _getFoodMacroPerGram(_food, _selectedTargetIndex) *
        widget.config.originalGrams;
    final remaining = goal - total + originalContribution;

    // Check if already at/over target
    if (remaining <= 0) {
      final macroName = _getMacroName(_selectedTargetIndex);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Already at or over target for $macroName')),
      );
      return;
    }

    // Check if food has this macro
    final macroPerGram = _getFoodMacroPerGram(_food, _selectedTargetIndex);
    if (macroPerGram <= 0) {
      final macroName = _getMacroName(_selectedTargetIndex);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('This food has no $macroName')));
      return;
    }

    // Fill quantity field with remaining macro value and label
    setState(() {
      final suffix = _getTargetSuffix();
      final valueText = remaining.toStringAsFixed(1);
      _quantityController.text = suffix != null
          ? '$valueText $suffix'
          : valueText;
    });
  }

  double _getGoalForTarget(GoalsProvider provider, int targetIndex) {
    final goals = provider.currentGoals;
    switch (targetIndex) {
      case 1:
        return goals.calories;
      case 2:
        return goals.protein;
      case 3:
        return goals.fat;
      case 4:
        return goals.carbs;
      case 5:
        return goals.fiber;
      default:
        return 0;
    }
  }

  double _getTotalForTarget(LogProvider provider, int targetIndex) {
    final useNetCarbs = Provider.of<GoalsProvider>(
      context,
      listen: false,
    ).useNetCarbs;
    switch (targetIndex) {
      case 1:
        return provider.totalCalories;
      case 2:
        return provider.totalProtein;
      case 3:
        return provider.totalFat;
      case 4:
        return useNetCarbs ? provider.totalNetCarbs : provider.totalCarbs;
      case 5:
        return provider.totalFiber;
      default:
        return 0;
    }
  }

  double _getFoodMacroPerGram(Food food, int targetIndex) {
    final useNetCarbs = Provider.of<GoalsProvider>(
      context,
      listen: false,
    ).useNetCarbs;
    switch (targetIndex) {
      case 1:
        return food.calories;
      case 2:
        return food.protein;
      case 3:
        return food.fat;
      case 4:
        return useNetCarbs ? food.netCarbs : food.carbs;
      case 5:
        return food.fiber;
      default:
        return 0;
    }
  }

  String _getMacroName(int targetIndex) {
    switch (targetIndex) {
      case 1:
        return 'Calories';
      case 2:
        return 'Protein';
      case 3:
        return 'Fat';
      case 4:
        return 'Carbs';
      case 5:
        return 'Fiber';
      default:
        return '';
    }
  }

  /// Returns suffix text for the amount field based on selected target.
  /// Only shows suffix for macro targets, not for Unit target.
  String? _getTargetSuffix() {
    switch (_selectedTargetIndex) {
      case 1:
        return 'cal';
      case 2:
        return 'g protein';
      case 3:
        return 'g fat';
      case 4:
        return 'g carbs';
      case 5:
        return 'g fiber';
      default:
        return null; // No suffix for Unit target
    }
  }

  Future<void> _handleEditDefinition() async {
    if (_food.source == 'recipe') {
      try {
        final recipe = await DatabaseService.instance.getRecipeById(_food.id);
        if (!mounted) return;

        final recipeProvider = Provider.of<RecipeProvider>(
          context,
          listen: false,
        );
        recipeProvider.loadFromRecipe(recipe);

        final result = await Navigator.pushNamed(
          context,
          AppRouter.recipeEditRoute,
        );

        if (result == true && mounted) {
          // Reload food from database to get latest changes
          final updatedFood = await DatabaseService.instance.getFoodById(
            _food.id,
            'live',
          );

          if (updatedFood != null && mounted) {
            setState(() {
              _food = updatedFood;
              // Also update selected unit if it no longer exists
              if (!_food.servings.any((s) => s.unit == _selectedUnit)) {
                _selectedUnit = _food.servings.first.unit;
              }
            });

            // Refresh the food in the log queue to propagate name/image changes
            final logProvider = Provider.of<LogProvider>(
              context,
              listen: false,
            );
            await logProvider.refreshFoodInQueue(_food.id, updatedFood);

            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Recipe updated')));
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error updating recipe: $e')));
        }
      }
      return;
    }

    try {
      final result = await Navigator.push<FoodEditResult>(
        context,
        MaterialPageRoute(
          builder: (context) => FoodEditScreen(
            originalFood: _food,
            contextType: FoodEditContext.editDefinition,
          ),
        ),
      );

      if (result != null && mounted) {
        // Reload food from database to get latest changes
        // Always query from 'live' since edited foods are saved there
        final updatedFood = await DatabaseService.instance.getFoodById(
          result.foodId,
          'live',
        );

        if (updatedFood != null && mounted) {
          setState(() {
            _food = updatedFood;
            // Also update selected unit if it no longer exists
            if (!_food.servings.any((s) => s.unit == _selectedUnit)) {
              // Try to find matching unit, otherwise default
              _selectedUnit = _food.servings.first.unit;
            }
          });

          // Refresh the food in the log queue to propagate name/image changes
          final logProvider = Provider.of<LogProvider>(context, listen: false);
          await logProvider.refreshFoodInQueue(result.foodId, updatedFood);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Food definition updated')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating food: $e')));
      }
    }
  }

  Future<void> _showContainerSelection() async {
    // Load containers
    final containers = await DatabaseService.instance.getAllContainers();
    if (!mounted) return;

    if (containers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No containers found. Add them in Settings.'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<FoodContainer>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              'Select Container to Subtract',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: containers.length,
              itemBuilder: (context, index) {
                final container = containers[index];
                return ListTile(
                  leading: SizedBox(
                    width: 40,
                    height: 40,
                    child: container.thumbnail != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: FoodImageWidget(
                              thumbnail: container.thumbnail,
                              size: 40,
                            ),
                          )
                        : const Icon(Icons.inventory_2_outlined),
                  ),
                  title: Text(container.name),
                  subtitle: Text('${container.weight} ${container.unit}'),
                  onTap: () => Navigator.pop(context, container),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (selected != null) {
      final currentVal = double.tryParse(_quantityController.text) ?? 0.0;
      // Assume container weight is in grams.
      // If selected unit is NOT grams, we might need conversion?
      // Plan implied simple gram subtraction.
      // If user is in "oz", subtracting "50g" is tricky if we just subtract numbers.
      // Ideally we convert container weight to selected unit.

      double weightToSubtract = selected.weight;

      // Minus Container assumes grams - warn if using a different unit
      if (_selectedUnit != 'g' && _selectedUnit != 'gram') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please switch unit to "g" to subtract container weight correctly.',
              ),
            ),
          );
        }
        return;
      }

      final newValue = currentVal - weightToSubtract;
      if (newValue < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Container weight is larger than total weight!'),
            ),
          );
        }
      } else {
        setState(() {
          _quantityController.text = newValue.toStringAsFixed(0);
        });
        if (mounted) {
          await UiUtils.showAutoDismissDialog(
            context,
            'Subtracted ${selected.weight}g for ${selected.name}',
          );
        }
      }
    }
  }
}
