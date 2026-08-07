import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/models/recipe.dart';
import 'package:meal_of_record/models/recipe_item.dart';
import 'package:meal_of_record/config/app_colors.dart';
import 'package:meal_of_record/widgets/horizontal_mini_bar_chart.dart';
import 'package:meal_of_record/screens/search_screen.dart';
import 'package:meal_of_record/models/search_config.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/open_food_facts_service.dart';
import 'package:meal_of_record/services/search_service.dart';
import 'package:meal_of_record/services/food_sorting_service.dart';
import 'package:meal_of_record/widgets/slidable_recipe_item_widget.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart' as model_unit;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/services/emoji_service.dart';
import 'package:meal_of_record/models/category.dart' as model_cat;
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:meal_of_record/screens/square_camera_screen.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:meal_of_record/services/image_storage_service.dart';
import 'package:meal_of_record/widgets/unit_select_field.dart';
import 'package:meal_of_record/utils/math_evaluator.dart';
import 'package:meal_of_record/widgets/math_input_bar.dart';
import 'package:meal_of_record/models/food_container.dart';
import 'package:meal_of_record/utils/ui_utils.dart';

class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key});

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  late TextEditingController _nameController;
  late TextEditingController _portionsController;
  late TextEditingController _portionNameController;
  late TextEditingController _weightController;
  late TextEditingController _notesController;
  late TextEditingController _linkController;
  late TextEditingController _emojiController;
  final FocusNode _weightFocusNode = FocusNode();
  bool _isWeightFocused = false;
  List<model_cat.Category> _allCategories = [];
  List<String> _availableUnits = [];

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<RecipeProvider>(context, listen: false);
    _nameController = TextEditingController(text: provider.name);
    _portionsController = TextEditingController(
      text: provider.servingsCreated.toString(),
    );
    _portionNameController = TextEditingController(text: provider.portionName);
    _weightController = TextEditingController(
      text: provider.finalWeightGrams?.toString() ?? '',
    );
    _notesController = TextEditingController(text: provider.notes);
    _linkController = TextEditingController(text: provider.link);
    _emojiController = TextEditingController(text: provider.emoji);
    _weightFocusNode.addListener(_onWeightFocusChange);
    _loadCategories();
    _loadAvailableUnits();
  }

  Future<void> _loadCategories() async {
    final cats = await DatabaseService.instance.getCategories();
    if (mounted) {
      setState(() {
        _allCategories = cats;
      });
    }
  }

  Future<void> _loadAvailableUnits() async {
    final units = await DatabaseService.instance.getDistinctUnits();
    if (mounted) {
      setState(() {
        _availableUnits = units;
      });
    }
  }

  @override
  void dispose() {
    _weightFocusNode.removeListener(_onWeightFocusChange);
    _weightFocusNode.dispose();
    _nameController.dispose();
    _portionsController.dispose();
    _portionNameController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    _linkController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _onWeightFocusChange() {
    setState(() {
      _isWeightFocused = _weightFocusNode.hasFocus;
    });
    if (!_weightFocusNode.hasFocus) {
      _evaluateWeightExpression();
    }
  }

  void _evaluateWeightExpression() {
    final text = _weightController.text;
    if (text.isEmpty) return;

    // Skip if it's already just a number
    if (double.tryParse(text) != null) return;

    final result = MathEvaluator.evaluate(text);
    if (result == null || result.isInfinite || result.isNaN) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid expression')),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _weightFocusNode.requestFocus();
      });
      return;
    }

    final formatted =
        result == result.roundToDouble()
            ? result.toStringAsFixed(0)
            : result.toStringAsFixed(2);
    setState(() {
      _weightController.text = formatted;
    });
    final provider = Provider.of<RecipeProvider>(context, listen: false);
    provider.setFinalWeightGrams(result);
  }

  Future<void> _showWeightContainerSelection() async {
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

    if (selected != null && mounted) {
      final currentVal = double.tryParse(_weightController.text) ?? 0.0;
      final weightToSubtract = selected.weight;
      final newValue = currentVal - weightToSubtract;

      if (newValue < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Container weight is larger than total weight!'),
          ),
        );
      } else {
        setState(() {
          _weightController.text = newValue.toStringAsFixed(0);
        });
        final provider = Provider.of<RecipeProvider>(context, listen: false);
        provider.setFinalWeightGrams(newValue);
        if (mounted) {
          await UiUtils.showAutoDismissDialog(
            context,
            'Subtracted ${selected.weight}g for ${selected.name}',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RecipeProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(provider.name.isEmpty ? 'New Recipe' : provider.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);

                  // Check if this edit would trigger versioning
                  final wouldVersion =
                      await provider.wouldTriggerVersioning();

                  bool forceUpdateInPlace = false;
                  if (wouldVersion && mounted) {
                    final choice = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Save Recipe'),
                        content: const Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'This recipe has been logged. '
                              'How would you like to save it?',
                            ),
                            SizedBox(height: 10),
                            Text(
                              'New Version — historical logs keep '
                              'their original nutrition values.',
                              style: TextStyle(fontSize: 13),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Fix in Place — all logs using this '
                              'recipe will reflect the changes.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, 'version'),
                            child: const Text('New Version'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, 'fix'),
                            child: const Text('Fix in Place'),
                          ),
                        ],
                      ),
                    );

                    if (choice == null) return; // dismissed
                    forceUpdateInPlace = choice == 'fix';
                  }

                  final success = await provider.saveRecipe(
                    forceUpdateInPlace: forceUpdateInPlace,
                  );

                  if (!mounted) return;

                  if (success) {
                    navigator.pop(true);
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          provider.errorMessage ?? 'Failed to save recipe.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
              // Only show Import (Scan) button if creating a new recipe AND it's empty
              if (provider.id == 0 &&
                  provider.name.isEmpty &&
                  provider.items.isEmpty)
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Import Recipe',
                  onPressed: () async {
                    final importedId = await Navigator.pushNamed(
                      context,
                      AppRouter.qrSharingRoute,
                    );

                    if (importedId != null && importedId is int && mounted) {
                      final newRecipe = await DatabaseService.instance
                          .getRecipeById(importedId);
                      provider.loadFromRecipe(newRecipe);
                      // Update controllers
                      _nameController.text = newRecipe.name;
                      _portionsController.text = newRecipe.servingsCreated
                          .toString();
                      _portionNameController.text = newRecipe.portionName;
                      _weightController.text =
                          newRecipe.finalWeightGrams?.toString() ?? '';
                      _notesController.text = newRecipe.notes ?? '';
                      _linkController.text = newRecipe.link ?? '';
                      // Refresh categories
                      setState(() {});
                    }
                  },
                ),
              // Only show Share button if the recipe is saved (id > 0)
              if (provider.id > 0)
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () async {
                    // Reconstruct recipe object from provider state to share
                    // (Logic same as before but inside condition)
                    final recipeToShare = Recipe(
                      id: provider.id,
                      name: provider.name,
                      servingsCreated: provider.servingsCreated,
                      finalWeightGrams: provider.finalWeightGrams,
                      portionName: provider.portionName,
                      notes: provider.notes,
                      link: provider.link.isEmpty ? null : provider.link,
                      isTemplate: provider.isTemplate,
                      hidden: false,
                      parentId: provider.parentId,
                      createdTimestamp: DateTime.now().millisecondsSinceEpoch,
                      items: provider.items,
                      categories: provider.selectedCategories,
                      emoji: provider.emoji,
                      thumbnail: provider.thumbnail,
                    );

                    Navigator.pushNamed(
                      context,
                      AppRouter.qrSharingRoute,
                      arguments: recipeToShare,
                    );
                  },
                ),
            ],
          ),
          resizeToAvoidBottomInset: false,
          body: Builder(
            builder: (context) {
              final keyboardHeight =
                  MediaQuery.of(context).viewInsets.bottom;
              final showOperatorBar =
                  _isWeightFocused && keyboardHeight > 0;
              return Stack(
                children: [
                  SlidableAutoCloseBehavior(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 12.0,
                right: 12.0,
                top: 8.0,
                bottom: 8.0 + (showOperatorBar ? 48 + keyboardHeight : 0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMetadataFields(provider),
                  const SizedBox(height: 10),
                  _buildMacroSummary(provider),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ingredients',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: () async {
                          final databaseService = DatabaseService.instance;
                          final offApiService = OffApiService();
                          final emojiService = emojiForFoodName;
                          final searchService = SearchService(
                            databaseService: databaseService,
                            offApiService: offApiService,
                            emojiForFoodName: emojiService,
                            sortingService: FoodSortingService(),
                          );

                          final item = await Navigator.push<RecipeItem>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChangeNotifierProvider(
                                create: (_) => SearchProvider(
                                  databaseService: databaseService,
                                  offApiService: offApiService,
                                  searchService: searchService,
                                ),
                                child: SearchScreen(
                                  config: SearchConfig(
                                    context: QuantityEditContext.recipe,
                                    title: 'Add Ingredient',
                                    showQueueStats: false,
                                    onSaveOverride: (portion) {
                                      Navigator.pop(
                                        context,
                                        RecipeItem(
                                          id: 0,
                                          food: portion.food,
                                          grams: portion.grams,
                                          unit: portion.unit,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          );

                          if (item != null && mounted) {
                            provider.addItem(item);
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  _buildIngredientList(provider),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _linkController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Link',
                      hintText: 'https://...',
                      prefixIcon: Icon(Icons.link),
                    ),
                    onChanged: provider.setLink,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      hintText: 'Preparation steps, cooking time...',
                    ),
                    onChanged: provider.setNotes,
                  ),
                ],
              ),
            ),
          ),
                  if (showOperatorBar)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: keyboardHeight,
                      child: MathInputBar(controller: _weightController),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMetadataFields(RecipeProvider provider) {
    return Column(
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Recipe Name',
            hintText: 'e.g. Grandma\'s Apple Pie',
          ),
          onChanged: provider.setName,
        ),
        Row(
          children: [
            SizedBox(
              width: 60,
              child: TextFormField(
                controller: _emojiController,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: 'Emoji'),
                onChanged: provider.setEmoji,
              ),
            ),
            const SizedBox(width: 12),
            _buildImagePreview(provider),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _pickImage(provider),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Add Image'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _portionsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Portions Count'),
                onChanged: (val) {
                  final d = double.tryParse(val);
                  if (d != null) provider.setServingsCreated(d);
                },
                onTap: () {
                  _portionsController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _portionsController.text.length,
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: UnitSelectField(
                label: 'Portion Unit Name',
                value: provider.portionName,
                availableUnits: _availableUnits,
                onChanged: provider.setPortionName,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _weightController,
                focusNode: _weightFocusNode,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Final Weight (g)',
                  hintText: 'Optional',
                ),
                onChanged: (val) {
                  // Only update provider if it's a plain number
                  final d = double.tryParse(val);
                  provider.setFinalWeightGrams(d);
                },
                onTap: () {
                  _weightController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _weightController.text.length,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: TextButton.icon(
                onPressed: _showWeightContainerSelection,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text(
                  'Minus Container',
                  style: TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Only Dumpable',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Switch(
              value: provider.isTemplate,
              onChanged: provider.setIsTemplate,
            ),
          ],
        ),
        const Text(
          'When enabled, this recipe can only be dumped as individual ingredients into your log.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: _showCategorySelectionDialog,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Categories',
              suffixIcon: Icon(Icons.arrow_drop_down),
            ),
            child: provider.selectedCategories.isEmpty
                ? const Text(
                    'None selected',
                    style: TextStyle(color: Colors.grey),
                  )
                : Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: provider.selectedCategories.map((cat) {
                      return Chip(
                        label: Text(
                          cat.name,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onDeleted: () => provider.toggleCategory(cat),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview(RecipeProvider provider) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[600]!, width: 2),
      ),
      child: FoodImageWidget(
        thumbnail: provider.thumbnail,
        emoji: provider.emoji,
        name: provider.name,
        size: 60,
        onTap: () => _pickImage(provider),
      ),
    );
  }

  Future<void> _pickImage(RecipeProvider provider) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Image'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (provider.thumbnail != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Image'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'remove') {
      provider.setThumbnail(null);
      return;
    }

    if (!mounted) return;

    final String? pickedPath;
    if (choice == 'camera') {
      pickedPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const SquareCameraScreen()),
      );
    } else {
      final pickedFile = await image_picker.ImagePicker().pickImage(
        source: image_picker.ImageSource.gallery,
      );
      pickedPath = pickedFile?.path;
    }

    if (pickedPath == null) return;

    try {
      final guid = await ImageStorageService.instance.saveImage(
        File(pickedPath),
      );
      provider.setThumbnail('${ImageStorageService.localPrefix}$guid');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCategorySelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final provider = Provider.of<RecipeProvider>(context);
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Categories'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () async {
                      final name = await _showAddCategorySimpleDialog();
                      if (name != null) {
                        final newCategoryId = await DatabaseService.instance
                            .addCategory(name);
                        await _loadCategories();
                        // Find and auto-select the newly created category
                        final newCategory = _allCategories.firstWhere(
                          (cat) => cat.id == newCategoryId,
                          orElse: () => _allCategories.last,
                        );
                        provider.toggleCategory(newCategory);
                        setDialogState(() {});
                      }
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _allCategories.length,
                  itemBuilder: (context, index) {
                    final cat = _allCategories[index];
                    final isSelected = provider.selectedCategories.any(
                      (c) => c.id == cat.id,
                    );
                    return CheckboxListTile(
                      title: Text(cat.name),
                      value: isSelected,
                      onChanged: (_) {
                        provider.toggleCategory(cat);
                        setDialogState(() {});
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _showAddCategorySimpleDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Category Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroSummary(RecipeProvider provider) {
    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: AppColors.largeWidgetBackground,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMacroRow(
            'Total Recipe Macros',
            provider.totalCalories,
            provider.totalProtein,
            provider.totalFat,
            Provider.of<GoalsProvider>(context, listen: false).useNetCarbs ? provider.totalNetCarbs : provider.totalCarbs,
            provider.totalFiber,
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white24),
          const SizedBox(height: 8),
          _buildMacroRow(
            'Macros per ${provider.portionName}',
            provider.caloriesPerPortion,
            provider.totalProtein / provider.servingsCreated,
            provider.totalFat / provider.servingsCreated,
            (Provider.of<GoalsProvider>(context, listen: false).useNetCarbs ? provider.totalNetCarbs : provider.totalCarbs) / provider.servingsCreated,
            provider.totalFiber / provider.servingsCreated,
          ),
        ],
      ),
    );
  }

  Widget _buildMacroRow(
    String title,
    double cal,
    double protein,
    double fat,
    double carbs,
    double fiber,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildMacroItem('🔥', cal, 2000, Colors.blue),
            _buildMacroItem('P', protein, 150, Colors.red),
            _buildMacroItem('F', fat, 70, Colors.yellow),
            _buildMacroItem('C', carbs, 250, Colors.green),
            _buildMacroItem('Fb', fiber, 30, Colors.brown),
          ],
        ),
      ],
    );
  }

  Widget _buildMacroItem(String label, double val, double target, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: HorizontalMiniBarChart(
          consumed: val,
          target: target,
          color: color,
          macroLabel: label,
          unitLabel: '',
        ),
      ),
    );
  }

  Widget _buildIngredientList(RecipeProvider provider) {
    if (provider.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: Text(
            'No ingredients added yet',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: provider.items.length,
      onReorderItem: (oldIndex, newIndex) =>
          provider.reorderItem(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final item = provider.items[index];
        return SlidableRecipeItemWidget(
          key: ValueKey('${item.id}_$index'),
          item: item,
          index: index,
          onDelete: () => provider.removeItem(index),
          onEdit: () async {
            // Determine food object (either food itself or converted recipe)
            final Food food = item.isFood ? item.food! : item.recipe!.toFood();

            // Find best matching serving
            final model_unit.FoodServing serving = food.servings.firstWhere(
              (s) => s.unit == item.unit,
              orElse: () => food.servings.first,
            );

            // Reload food from database to get latest changes (e.g., image)
            final reloadedFood = await DatabaseService.instance.getFoodById(
              food.id,
              'live',
            );

            if (reloadedFood == null) {
              // Fallback to cached food if reload fails
              return;
            }

            if (!mounted) return;

            // Navigate to QuantityEditScreen
            final updatedPortion = await Navigator.push<FoodPortion>(
              context,
              MaterialPageRoute(
                builder: (_) => QuantityEditScreen(
                  config: QuantityEditConfig(
                    context: QuantityEditContext.recipe,
                    food: reloadedFood,
                    isUpdate: true,
                    initialUnit: serving.unit,
                    initialQuantity: serving.quantityFromGrams(item.grams),
                    originalGrams: item.grams,
                    recipeServings: provider.servingsCreated,
                  ),
                ),
              ),
            );

            if (updatedPortion != null && mounted) {
              // Convert FoodPortion back to RecipeItem
              final newItem = RecipeItem(
                id: item.id,
                food: item.isFood ? updatedPortion.food : null,
                recipe: item.isRecipe ? item.recipe : null,
                grams: updatedPortion.grams,
                unit: updatedPortion.unit,
              );
              provider.updateItem(index, newItem);
            }
          },
        );
      },
    );
  }
}
