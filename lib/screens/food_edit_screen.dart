import 'dart:io';
import 'package:flutter/material.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/image_storage_service.dart';
import 'package:meal_of_record/widgets/screen_background.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:meal_of_record/widgets/serving_info_sheet.dart';
import 'package:meal_of_record/config/app_colors.dart';
import 'package:meal_of_record/screens/barcode_scanner_screen.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:meal_of_record/screens/square_camera_screen.dart';
import 'package:meal_of_record/utils/math_evaluator.dart';
import 'package:meal_of_record/widgets/math_input_bar.dart';
import 'package:meal_of_record/widgets/unit_select_field.dart';

enum FoodEditContext {
  search, // From Search Screen (Edit/Copy) -> "Save", "Save & Use"
  editDefinition, // From Log/Receipt (Edit Definition) -> "Update" (same as Save)
}

class FoodEditResult {
  final int foodId;
  final bool useImmediately;

  FoodEditResult(this.foodId, {this.useImmediately = false});
}

class FoodEditScreen extends StatefulWidget {
  final Food? originalFood; // Null for new food
  final FoodEditContext contextType;
  final bool isCopy; // If true, originalFood is used as template but ID is 0
  final String? initialBarcode; // Pre-populated barcode for new food from scan

  const FoodEditScreen({
    super.key,
    this.originalFood,
    this.contextType = FoodEditContext.search,
    this.isCopy = false,
    this.initialBarcode,
  });

  @override
  State<FoodEditScreen> createState() => _FoodEditScreenState();
}

class _FoodEditScreenState extends State<FoodEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _emojiController;
  late TextEditingController _notesController;

  // Macro Controllers
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fatController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fiberController = TextEditingController();

  // Primary serving controllers (for new foods / per-serving mode)
  final _primaryServingQuantityController = TextEditingController(text: '1');
  final _primaryServingGramsController = TextEditingController();
  String _primaryServingUnit = 'serving';

  // FocusNodes for numeric fields (math input support)
  final List<FocusNode> _numericFocusNodes = [];
  TextEditingController? _activeController;

  List<FoodServing> _servings = [];
  bool _isPerServingMode = false;
  FoodServing? _selectedServingForMacroInput;
  String? _thumbnail;

  // Available units from database
  List<String> _availableUnits = [];

  // Barcode management
  List<String> _barcodes = [];
  List<String> _originalBarcodes = [];
  final _barcodeInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initNumericFocusNodes();
    _initData();
    _loadAvailableUnits();
    _loadBarcodes();
  }

  void _initNumericFocusNodes() {
    // 7 numeric fields: calories, protein, fat, carbs, fiber, serving qty, serving grams
    for (int i = 0; i < 7; i++) {
      _numericFocusNodes.add(FocusNode());
    }
  }

  FocusNode _focusNodeFor(TextEditingController controller) {
    final index = _numericControllerIndex(controller);
    return _numericFocusNodes[index];
  }

  int _numericControllerIndex(TextEditingController controller) {
    if (identical(controller, _caloriesController)) return 0;
    if (identical(controller, _proteinController)) return 1;
    if (identical(controller, _fatController)) return 2;
    if (identical(controller, _carbsController)) return 3;
    if (identical(controller, _fiberController)) return 4;
    if (identical(controller, _primaryServingQuantityController)) return 5;
    if (identical(controller, _primaryServingGramsController)) return 6;
    return 0;
  }

  void _onNumericFocusChange(TextEditingController controller, bool hasFocus) {
    if (hasFocus) {
      setState(() {
        _activeController = controller;
      });
    } else {
      _evaluateField(controller);
      // Trigger grams recalculation if this was the grams field
      if (identical(controller, _primaryServingGramsController)) {
        _onGramsFieldEvaluated();
      }
      setState(() {
        if (identical(_activeController, controller)) {
          _activeController = null;
        }
      });
    }
  }

  void _evaluateField(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    if (double.tryParse(text) != null) return;

    final result = MathEvaluator.evaluate(text);
    if (result != null && !result.isInfinite && !result.isNaN) {
      controller.text = _format(result);
    }
  }

  void _onGramsFieldEvaluated() {
    if (widget.originalFood != null) {
      final grams = _parse(_primaryServingGramsController.text);
      if (grams > 0) {
        final food = widget.originalFood!;
        _caloriesController.text = _format(food.calories * grams);
        _proteinController.text = _format(food.protein * grams);
        _fatController.text = _format(food.fat * grams);
        _carbsController.text = _format(food.carbs * grams);
        _fiberController.text = _format(food.fiber * grams);
      }
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

  Future<void> _loadBarcodes() async {
    // Load barcodes for existing food
    if (widget.originalFood != null && !widget.isCopy) {
      final barcodes = await DatabaseService.instance.getBarcodesByFoodId(
        widget.originalFood!.id,
      );
      if (mounted) {
        setState(() {
          _barcodes = barcodes;
          _originalBarcodes = List.from(barcodes);
        });
      }
    }

    // Pick up sourceBarcode from the food object (e.g., OFF foods not yet in DB)
    if (widget.originalFood?.sourceBarcode != null &&
        widget.originalFood!.sourceBarcode!.isNotEmpty &&
        !_barcodes.contains(widget.originalFood!.sourceBarcode)) {
      setState(() {
        _barcodes.add(widget.originalFood!.sourceBarcode!);
      });
    }

    // Handle initial barcode from scan (for new food)
    if (widget.initialBarcode != null) {
      if (mounted) {
        setState(() {
          if (!_barcodes.contains(widget.initialBarcode)) {
            _barcodes.add(widget.initialBarcode!);
          }
        });
      }
    }
  }

  void _initData() {
    final food = widget.originalFood;
    _nameController = TextEditingController(text: food?.name ?? '');
    _emojiController = TextEditingController(text: food?.emoji ?? '🍎');
    _notesController = TextEditingController(text: food?.usageNote ?? '');
    _thumbnail = food?.thumbnail;

    if (food != null) {
      // Editing existing food
      _servings = List.from(food.servings);

      // Find first non-g serving to use as default
      final primaryServing = _servings.firstWhere(
        (s) => s.unit != 'g',
        orElse: () => _servings.first,
      );

      if (primaryServing.unit != 'g') {
        // Has a real serving, default to per-serving mode
        _isPerServingMode = true;
        _selectedServingForMacroInput = primaryServing;
        _primaryServingUnit = primaryServing.unit;
        _primaryServingQuantityController.text = _formatQuantity(
          primaryServing.quantity,
        );
        _primaryServingGramsController.text = _formatServingGrams(
          primaryServing.grams,
        );
        // Set macros for this serving
        _updateMacroFieldsForServing(food, primaryServing);
      } else {
        // Only has grams, use per-100g mode
        _isPerServingMode = false;
        _updateMacroFieldsFromBase(food);
      }
    } else {
      // New food - default to per-serving mode
      _isPerServingMode = true;
      _servings = [
        const FoodServing(foodId: 0, unit: 'g', grams: 1.0, quantity: 1.0),
      ];
      // Primary serving will be created from the inline fields on save
    }

    if (widget.isCopy) {
      _nameController.text = '${_nameController.text} - Copy';
    }
  }

  void _updateMacroFieldsFromBase(Food food) {
    // Populate controllers based on stored per-100g values
    _caloriesController.text = _format(food.calories * 100);
    _proteinController.text = _format(food.protein * 100);
    _fatController.text = _format(food.fat * 100);
    _carbsController.text = _format(food.carbs * 100);
    _fiberController.text = _format(food.fiber * 100);
  }

  void _updateMacroFieldsForServing(Food food, FoodServing serving) {
    // Calculate macros for this serving size
    final grams = serving.grams;
    _caloriesController.text = _format(food.calories * grams);
    _proteinController.text = _format(food.protein * grams);
    _fatController.text = _format(food.fat * grams);
    _carbsController.text = _format(food.carbs * grams);
    _fiberController.text = _format(food.fiber * grams);
  }

  String _format(double val) {
    if (val == 0) return '0';
    if (val < 1) return val.toStringAsFixed(1);
    return val.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  }

  String _formatQuantity(double val) {
    return val == val.roundToDouble()
        ? val.round().toString()
        : val.toStringAsFixed(1);
  }

  /// Format serving weight in grams, preserving up to 2 decimal places.
  String _formatServingGrams(double val) {
    if (val == val.roundToDouble()) return val.round().toString();
    final s = val.toStringAsFixed(2);
    // Strip trailing zeros: "28.50" → "28.5", "28.00" → "28"
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  @override
  void dispose() {
    for (final node in _numericFocusNodes) {
      node.dispose();
    }
    _nameController.dispose();
    _emojiController.dispose();
    _notesController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _fiberController.dispose();
    _primaryServingQuantityController.dispose();
    _primaryServingGramsController.dispose();
    super.dispose();
  }

  double _parse(String text) =>
      double.tryParse(text) ?? MathEvaluator.evaluate(text) ?? 0.0;

  Future<void> _save(bool useImmediately) async {
    if (!_formKey.currentState!.validate()) return;

    // Validation: require grams in per-serving mode
    if (_isPerServingMode) {
      final grams = _parse(_primaryServingGramsController.text);
      if (grams <= 0) {
        _showValidationError('Please enter the serving weight in grams');
        return;
      }

      // Validation: require a valid unit in per-serving mode
      if (_primaryServingUnit.isEmpty) {
        _showValidationError(
          'Please select a serving unit or create a new serving using "Add Servings"',
        );
        return;
      }
    }

    // Build primary serving from inline fields if in per-serving mode
    if (_isPerServingMode) {
      final unit = _primaryServingUnit;
      final quantity = _parse(_primaryServingQuantityController.text);
      final grams = _parse(_primaryServingGramsController.text);

      if (unit.isNotEmpty && grams > 0) {
        final primaryServing = FoodServing(
          foodId: widget.originalFood?.id ?? 0,
          unit: unit,
          grams: grams,
          quantity: quantity > 0 ? quantity : 1.0,
        );

        // Update or add the primary serving
        final existingIndex = _servings.indexWhere((s) => s.unit == unit);
        if (existingIndex >= 0) {
          _servings[existingIndex] = primaryServing;
        } else {
          // Insert after 'g' if exists, or at start
          final gIndex = _servings.indexWhere((s) => s.unit == 'g');
          if (gIndex >= 0) {
            _servings.insert(gIndex + 1, primaryServing);
          } else {
            _servings.insert(0, primaryServing);
          }
        }
        _selectedServingForMacroInput = primaryServing;
      }
    }

    // Calculate per-gram values
    double factor = 1.0;
    final displayGrams =
        _isPerServingMode && _selectedServingForMacroInput != null
        ? _selectedServingForMacroInput!.grams
        : 100.0;
    if (_isPerServingMode && _selectedServingForMacroInput != null) {
      if (_selectedServingForMacroInput!.grams > 0) {
        factor = 1.0 / _selectedServingForMacroInput!.grams;
      }
    } else {
      factor = 0.01;
    }

    double cal = _parse(_caloriesController.text) * factor;
    double prot = _parse(_proteinController.text) * factor;
    double fat = _parse(_fatController.text) * factor;
    double carb = _parse(_carbsController.text) * factor;
    double fib = _parse(_fiberController.text) * factor;

    // Snap per-gram values to originals when the difference is only from
    // display rounding (prevents false revisions on cosmetic-only edits).
    // Max display rounding error is 0.05 (half of 1 decimal place) divided
    // by the display serving grams. This tolerance is always less than the
    // minimum intentional change (0.1 / grams), so real edits are preserved.
    if (widget.originalFood != null && !widget.isCopy && displayGrams > 0) {
      final orig = widget.originalFood!;
      final tolerance =
          0.06 / displayGrams; // slightly above 0.05 for float safety
      if ((cal - orig.calories).abs() < tolerance) cal = orig.calories;
      if ((prot - orig.protein).abs() < tolerance) prot = orig.protein;
      if ((fat - orig.fat).abs() < tolerance) fat = orig.fat;
      if ((carb - orig.carbs).abs() < tolerance) carb = orig.carbs;
      if ((fib - orig.fiber).abs() < tolerance) fib = orig.fiber;
    }

    final newFood = Food(
      id: (widget.isCopy || widget.originalFood == null)
          ? 0
          : widget.originalFood!.id,
      name: _nameController.text.trim(),
      emoji: _emojiController.text.trim(),
      thumbnail: _thumbnail,
      usageNote: _notesController.text.trim(),
      calories: cal,
      protein: prot,
      fat: fat,
      carbs: carb,
      fiber: fib,
      source: widget.originalFood?.source ?? 'user',
      sourceBarcode: widget.originalFood?.sourceBarcode,
      servings: _servings,
      database: widget.originalFood?.database ?? FoodDatabase.live,
    );

    try {
      final id = await DatabaseService.instance.saveFood(newFood);

      // Sync barcodes
      await _syncBarcodes(id);

      if (mounted) {
        Navigator.pop(
          context,
          FoodEditResult(id, useImmediately: useImmediately),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving food: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _syncBarcodes(int foodId) async {
    // Find barcodes to add (in _barcodes but not in _originalBarcodes)
    final toAdd = _barcodes.where((b) => !_originalBarcodes.contains(b));

    // Find barcodes to remove (in _originalBarcodes but not in _barcodes)
    final toRemove = _originalBarcodes.where((b) => !_barcodes.contains(b));

    // Add new barcodes
    for (final barcode in toAdd) {
      await DatabaseService.instance.addBarcodeToFood(foodId, barcode);
    }

    // Remove deleted barcodes
    for (final barcode in toRemove) {
      await DatabaseService.instance.removeBarcodeFromFood(foodId, barcode);
    }
  }

  void _showValidationError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Missing Information'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final showOperatorBar = _activeController != null && keyboardHeight > 0;

    return ScreenBackground(
      resizeToAvoidBottomInset: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(
            widget.originalFood == null ? 'Create Food' : 'Edit Food',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: () => _save(false),
            ),
          ],
        ),
        body: Stack(
          children: [
            Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.only(
                  left: 12.0,
                  right: 12.0,
                  top: 8.0,
                  bottom:
                      8.0 +
                      (showOperatorBar ? 48 + keyboardHeight : keyboardHeight),
                ),
                children: [
                  _buildMetadataSection(),
                  const SizedBox(height: 12),
                  _buildPrimaryServingSection(),
                  const SizedBox(height: 12),
                  _buildMacroSection(),
                  const SizedBox(height: 12),
                  _buildServingsSection(),
                  const SizedBox(height: 16),
                  if (widget.contextType == FoodEditContext.search)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: ElevatedButton.icon(
                        onPressed: () => _save(true),
                        icon: const Icon(Icons.input),
                        label: const Text('Save & Use Immediately'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
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
                child: MathInputBar(controller: _activeController!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataSection() {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 60,
              child: TextFormField(
                controller: _emojiController,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: 'Emoji'),
                onChanged: (val) {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Food Name'),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _notesController,
          decoration: const InputDecoration(labelText: 'Notes (Optional)'),
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildImagePreview(),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_camera),
                label: const Text('Add Image'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildBarcodeSection(),
      ],
    );
  }

  Widget _buildBarcodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Barcodes',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        // List of existing barcodes
        if (_barcodes.isNotEmpty) ...[
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: _barcodes.map((barcode) {
                return ListTile(
                  dense: true,
                  title: Text(
                    barcode,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => _removeBarcode(barcode),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Add barcode row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _barcodeInputController,
                decoration: const InputDecoration(
                  hintText: 'Type barcode...',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _addBarcodeFromInput(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addBarcodeFromInput,
              tooltip: 'Add barcode',
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _scanBarcode,
              tooltip: 'Scan barcode',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addBarcodeFromInput() async {
    final barcode = _barcodeInputController.text.trim();
    if (barcode.isEmpty) return;

    await _addBarcode(barcode);
    _barcodeInputController.clear();
  }

  Future<void> _addBarcode(String barcode) async {
    // Check if already on this food
    if (_barcodes.contains(barcode)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Barcode already assigned to this food'),
          ),
        );
      }
      return;
    }

    // Check if on another food (only for existing foods)
    if (widget.originalFood != null && !widget.isCopy) {
      final otherFood = await DatabaseService.instance.isBarcodeOnOtherFood(
        barcode,
        widget.originalFood!.id,
      );
      if (otherFood != null && mounted) {
        final useAnyway = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Barcode Already Used'),
            content: Text(
              'This barcode is already assigned to "${otherFood.name}". '
              'Do you want to add it anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use Anyway'),
              ),
            ],
          ),
        );
        if (useAnyway != true) return;
      }
    } else {
      // For new foods, check against all foods
      final foods = await DatabaseService.instance.getFoodsByBarcode(barcode);
      if (foods.isNotEmpty && mounted) {
        final otherFood = foods.first;
        final useAnyway = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Barcode Already Used'),
            content: Text(
              'This barcode is already assigned to "${otherFood.name}". '
              'Do you want to add it anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use Anyway'),
              ),
            ],
          ),
        );
        if (useAnyway != true) return;
      }
    }

    setState(() {
      _barcodes.add(barcode);
    });
  }

  void _removeBarcode(String barcode) {
    setState(() {
      _barcodes.remove(barcode);
    });
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (barcode != null && barcode.isNotEmpty && mounted) {
      await _addBarcode(barcode);
    }
  }

  Widget _buildImagePreview() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[600]!, width: 2),
      ),
      child: FoodImageWidget(
        thumbnail: _thumbnail,
        emoji: _emojiController.text,
        name: _nameController.text,
        size: 80,
        onTap: _pickImage,
      ),
    );
  }

  Widget _buildPrimaryServingSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.largeWidgetBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Serving Size',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Row(
                children: [
                  const Text('Per: '),
                  DropdownButton<bool>(
                    value: _isPerServingMode,
                    dropdownColor: Colors.grey[800],
                    items: const [
                      DropdownMenuItem(value: false, child: Text('100g')),
                      DropdownMenuItem(value: true, child: Text('Serving')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _isPerServingMode = val!;
                        // Recalculate macros when switching modes
                        if (widget.originalFood != null) {
                          if (_isPerServingMode &&
                              _selectedServingForMacroInput != null) {
                            _updateMacroFieldsForServing(
                              widget.originalFood!,
                              _selectedServingForMacroInput!,
                            );
                          } else {
                            _updateMacroFieldsFromBase(widget.originalFood!);
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          if (_isPerServingMode) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                // Quantity field
                SizedBox(
                  width: 60,
                  child: Focus(
                    onFocusChange: (hasFocus) => _onNumericFocusChange(
                      _primaryServingQuantityController,
                      hasFocus,
                    ),
                    child: TextFormField(
                      controller: _primaryServingQuantityController,
                      focusNode: _focusNodeFor(
                        _primaryServingQuantityController,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'Qty',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 8,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Unit dropdown
                Expanded(
                  child: UnitSelectField(
                    label: 'Unit',
                    value: _primaryServingUnit,
                    availableUnits: widget.originalFood == null
                        ? _availableUnits // New food: show all database units
                        : _servings
                              //.where((s) => s.unit != 'g')
                              .map((s) => s.unit)
                              .toList(), // Existing food: only this food's serving units
                    allowCustom:
                        widget.originalFood ==
                        null, // Only allow custom for new foods
                    onChanged: (val) {
                      setState(() {
                        _primaryServingUnit = val;
                        // If selecting an existing serving, update grams field
                        final existingServing = _servings.firstWhere(
                          (s) => s.unit == val,
                          orElse: () => const FoodServing(
                            foodId: 0,
                            unit: '',
                            grams: 0,
                            quantity: 1,
                          ),
                        );
                        if (existingServing.grams > 0) {
                          _primaryServingGramsController.text =
                              _formatServingGrams(existingServing.grams);
                          _primaryServingQuantityController.text =
                              _formatQuantity(existingServing.quantity);
                          _selectedServingForMacroInput = existingServing;
                          // Auto-calculate macros
                          if (widget.originalFood != null) {
                            _updateMacroFieldsForServing(
                              widget.originalFood!,
                              existingServing,
                            );
                          }
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('='),
                const SizedBox(width: 8),
                // Grams field
                SizedBox(
                  width: 80,
                  child: Focus(
                    onFocusChange: (hasFocus) => _onNumericFocusChange(
                      _primaryServingGramsController,
                      hasFocus,
                    ),
                    child: TextFormField(
                      controller: _primaryServingGramsController,
                      focusNode: _focusNodeFor(_primaryServingGramsController),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.end,
                      decoration: const InputDecoration(
                        labelText: 'Grams',
                        suffixText: 'g',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 8,
                        ),
                      ),
                      onChanged: (val) {
                        // Auto-calculate macros if we have a food with existing data
                        if (widget.originalFood != null) {
                          final grams = _parse(val);
                          if (grams > 0) {
                            final food = widget.originalFood!;
                            _caloriesController.text = _format(
                              food.calories * grams,
                            );
                            _proteinController.text = _format(
                              food.protein * grams,
                            );
                            _fatController.text = _format(food.fat * grams);
                            _carbsController.text = _format(food.carbs * grams);
                            _fiberController.text = _format(food.fiber * grams);
                          }
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.largeWidgetBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nutrition', style: Theme.of(context).textTheme.titleMedium),
          if (_isPerServingMode &&
              _primaryServingGramsController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Values for ${_primaryServingQuantityController.text} $_primaryServingUnit (${_primaryServingGramsController.text}g)',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ),
          if (!_isPerServingMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Values per 100g',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ),
          const SizedBox(height: 6),
          _buildMacroRow(_caloriesController, 'Calories', 'cal'),
          _buildMacroRow(_fatController, 'Fat', 'g'),
          _buildMacroRow(_carbsController, 'Carbs', 'g'),
          _buildMacroRow(_fiberController, 'Fiber', 'g'),
          _buildMacroRow(_proteinController, 'Protein', 'g'),
        ],
      ),
    );
  }

  Widget _buildMacroRow(
    TextEditingController controller,
    String label,
    String suffix,
  ) {
    final focusNode = _focusNodeFor(controller);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: Focus(
              onFocusChange: (hasFocus) =>
                  _onNumericFocusChange(controller, hasFocus),
              child: TextFormField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.end,
                decoration: InputDecoration(
                  suffixText: suffix,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Additional Servings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: _addServing,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._servings.asMap().entries.map((entry) {
          final index = entry.key;
          final serving = entry.value;
          // Don't show 'g' unit or the primary serving being edited
          if (serving.unit == 'g') return const SizedBox.shrink();
          if (_isPerServingMode && serving.unit == _primaryServingUnit) {
            return const SizedBox.shrink();
          }

          return Card(
            color: Colors.white.withValues(alpha: 0.05),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(_formatServingLabel(serving)),
              subtitle: Text('= ${_formatServingGrams(serving.grams)}g'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _editServing(index),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete,
                      size: 20,
                      color: Colors.white54,
                    ),
                    onPressed: () => _deleteServing(index),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        // View Servings Info button
        if (widget.originalFood != null || _servings.length > 1)
          Center(
            child: TextButton.icon(
              onPressed: _showServingInfo,
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('View Servings'),
            ),
          ),
      ],
    );
  }

  String _formatServingLabel(FoodServing serving) {
    final qty = serving.quantity;
    final qtyStr = qty == qty.roundToDouble()
        ? qty.round().toString()
        : qty.toStringAsFixed(1);
    return '$qtyStr ${serving.unit}';
  }

  void _showServingInfo() {
    // Build a temporary food with current state for the info sheet
    final grams = _parse(_primaryServingGramsController.text);
    double factor = 1.0;
    if (_isPerServingMode && grams > 0) {
      factor = 1.0 / grams;
    } else {
      factor = 0.01;
    }

    final tempFood = Food(
      id: widget.originalFood?.id ?? 0,
      name: _nameController.text.isNotEmpty ? _nameController.text : 'New Food',
      source: widget.originalFood?.source ?? 'user',
      calories: _parse(_caloriesController.text) * factor,
      protein: _parse(_proteinController.text) * factor,
      fat: _parse(_fatController.text) * factor,
      carbs: _parse(_carbsController.text) * factor,
      fiber: _parse(_fiberController.text) * factor,
      servings: _servings,
    );

    showServingInfoSheet(context, tempFood);
  }

  Future<void> _addServing() async {
    await _showServingDialog();
  }

  Future<void> _editServing(int index) async {
    await _showServingDialog(index: index, serving: _servings[index]);
  }

  void _deleteServing(int index) {
    setState(() {
      final removed = _servings.removeAt(index);
      if (_selectedServingForMacroInput?.unit == removed.unit) {
        _selectedServingForMacroInput = _servings.firstWhere(
          (s) => s.unit != 'g',
          orElse: () => _servings.first,
        );
      }
    });
  }

  Future<void> _pickImage() async {
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
            if (_thumbnail != null)
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
      if (_thumbnail != null) {
        final guid = widget.originalFood?.getLocalImageGuid();
        if (guid != null) {
          await ImageStorageService.instance.deleteImage(guid);
        }
      }
      setState(() {
        _thumbnail = null;
      });
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
      final pickedFile = await picker.ImagePicker().pickImage(
        source: picker.ImageSource.gallery,
      );
      pickedPath = pickedFile?.path;
    }

    if (pickedPath == null) return;

    try {
      final guid = await ImageStorageService.instance.saveImage(
        File(pickedPath),
      );

      if (_thumbnail != null) {
        final oldGuid = widget.originalFood?.getLocalImageGuid();
        if (oldGuid != null) {
          await ImageStorageService.instance.deleteImage(oldGuid);
        }
      }

      setState(() {
        _thumbnail = '${ImageStorageService.localPrefix}$guid';
      });
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

  Future<void> _showServingDialog({int? index, FoodServing? serving}) async {
    final nameCtrl = TextEditingController(text: serving?.unit ?? '');
    final gramsCtrl = TextEditingController(
      text: serving?.grams.toString() ?? '',
    );
    final quantityCtrl = TextEditingController(
      text: serving?.quantity.toString() ?? '1.0',
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(serving == null ? 'Add Serving' : 'Edit Serving'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UnitSelectField(
                  label: 'Unit Name (e.g. cup, slice)',
                  value: nameCtrl.text,
                  availableUnits: _availableUnits,
                  onChanged: (val) {
                    setDialogState(() {
                      nameCtrl.text = val;
                    });
                  },
                ),
                TextFormField(
                  controller: quantityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quantity (e.g. 1.0)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                TextFormField(
                  controller: gramsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Weight for Quantity (g)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final grams = double.tryParse(gramsCtrl.text) ?? 0.0;
                  final qty = double.tryParse(quantityCtrl.text) ?? 1.0;
                  if (name.isNotEmpty && grams > 0) {
                    setState(() {
                      final newServing = FoodServing(
                        foodId: widget.originalFood?.id ?? 0,
                        unit: name,
                        grams: grams,
                        quantity: qty,
                      );
                      if (index != null) {
                        _servings[index] = newServing;
                      } else {
                        _servings.add(newServing);
                      }
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
