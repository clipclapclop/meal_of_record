import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/models/goal_settings.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/providers/weight_provider.dart';
import 'package:meal_of_record/models/weight.dart';
import 'package:meal_of_record/widgets/screen_background.dart';
import 'package:meal_of_record/utils/ui_utils.dart';

class GoalSettingsScreen extends StatefulWidget {
  const GoalSettingsScreen({super.key});

  @override
  State<GoalSettingsScreen> createState() => _GoalSettingsScreenState();
}

class _GoalSettingsScreenState extends State<GoalSettingsScreen> {
  late TextEditingController _anchorWeightController;
  late TextEditingController _maintenanceCalController;
  late TextEditingController _proteinController;
  late TextEditingController _fatController;
  late TextEditingController _carbController;
  late TextEditingController _fiberController;
  late TextEditingController _fixedDeltaController;
  late TextEditingController _proteinMultiplierController;
  late TextEditingController _correctionWindowController;
  late GoalMode _mode;
  late MacroCalculationMode _calcMode;
  late ProteinTargetMode _proteinTargetMode;
  late bool _enableSmartTargets;
  late bool _useNetCarbs;
  late int _tdeeWindowDays;
  late GoalSettings _initialSettings;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<GoalsProvider>(
      context,
      listen: false,
    ).settings;

    _anchorWeightController = TextEditingController(
      text: settings.anchorWeight.toString(),
    );
    _maintenanceCalController = TextEditingController(
      text: settings.maintenanceCaloriesStart.toString(),
    );
    _proteinController = TextEditingController(
      text: settings.proteinTarget.toString(),
    );
    _fatController = TextEditingController(text: settings.fatTarget.toString());
    _carbController = TextEditingController(
      text: settings.carbTarget.toString(),
    );
    _fiberController = TextEditingController(
      text: settings.fiberTarget.toString(),
    );
    _fixedDeltaController = TextEditingController(
      text: settings.fixedDelta.toString(),
    );
    _proteinMultiplierController = TextEditingController(
      text: settings.proteinMultiplier.toString(),
    );
    _correctionWindowController = TextEditingController(
      text: settings.correctionWindowDays.toString(),
    );
    _mode = settings.mode;
    _calcMode = settings.calculationMode;
    _proteinTargetMode = settings.proteinTargetMode;
    _enableSmartTargets = settings.enableSmartTargets;
    _useNetCarbs = settings.useNetCarbs;
    _tdeeWindowDays = settings.tdeeWindowDays;
    _initialSettings = settings;
  }

  @override
  void dispose() {
    _anchorWeightController.dispose();
    _maintenanceCalController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbController.dispose();
    _fiberController.dispose();
    _fixedDeltaController.dispose();
    _proteinMultiplierController.dispose();
    _correctionWindowController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Validate required fields
    final maintenanceCal = double.tryParse(_maintenanceCalController.text);
    if (maintenanceCal == null || maintenanceCal <= 0) {
      UiUtils.showAutoDismissDialog(
        context,
        'Please enter valid maintenance calories',
      );
      return;
    }

    final protein = double.tryParse(_proteinController.text);
    if (_proteinTargetMode == ProteinTargetMode.fixed &&
        (protein == null || protein <= 0)) {
      UiUtils.showAutoDismissDialog(
        context,
        'Please enter valid protein target',
      );
      return;
    }

    final proteinMultiplier = double.tryParse(
      _proteinMultiplierController.text,
    );
    if (_proteinTargetMode == ProteinTargetMode.percentageOfWeight &&
        (proteinMultiplier == null || proteinMultiplier <= 0)) {
      UiUtils.showAutoDismissDialog(
        context,
        'Please enter valid protein multiplier',
      );
      return;
    }

    final fat = double.tryParse(_fatController.text);
    if (_calcMode == MacroCalculationMode.proteinFat &&
        (fat == null || fat <= 0)) {
      UiUtils.showAutoDismissDialog(context, 'Please enter valid fat target');
      return;
    }

    final carbs = double.tryParse(_carbController.text);
    if (_calcMode == MacroCalculationMode.proteinCarbs &&
        (carbs == null || carbs <= 0)) {
      UiUtils.showAutoDismissDialog(context, 'Please enter valid carb target');
      return;
    }

    final fiber = double.tryParse(_fiberController.text);
    if (fiber == null || fiber <= 0) {
      UiUtils.showAutoDismissDialog(context, 'Please enter valid fiber target');
      return;
    }

    // Validate target weight
    final targetWeight = double.tryParse(_anchorWeightController.text);
    if (targetWeight == null || targetWeight <= 0) {
      UiUtils.showAutoDismissDialog(context, 'Please enter a valid weight');
      return;
    }

    // For lose/gain modes, validate delta
    double? delta;
    if (_mode != GoalMode.maintain) {
      delta = double.tryParse(_fixedDeltaController.text);
      if (delta == null || delta <= 0) {
        UiUtils.showAutoDismissDialog(context, 'Please enter a valid delta');
        return;
      }
    }

    // Detect if this is initial setup
    final goalsProvider = Provider.of<GoalsProvider>(context, listen: false);
    final isInitialSetup = !goalsProvider.isGoalsSet;

    final newSettings = GoalSettings(
      anchorWeight: targetWeight,
      maintenanceCaloriesStart: maintenanceCal,
      proteinTarget: protein ?? 0.0, // May be recalculated if multiplier
      fatTarget: fat ?? 0.0,
      carbTarget: carbs ?? 0.0,
      fiberTarget: fiber,
      mode: _mode,
      calculationMode: _calcMode,
      proteinTargetMode: _proteinTargetMode,
      proteinMultiplier: proteinMultiplier ?? 1.0,
      fixedDelta: _mode != GoalMode.maintain ? delta! : 0.0,
      lastTargetUpdate: goalsProvider.settings.lastTargetUpdate,
      isSet: true,
      enableSmartTargets: _enableSmartTargets,
      correctionWindowDays:
          int.tryParse(_correctionWindowController.text) ?? 30,
      tdeeWindowDays: _tdeeWindowDays,
      useNetCarbs: _useNetCarbs,
    );

    await goalsProvider.saveSettings(
      newSettings,
      isInitialSetup: isInitialSetup,
    );

    if (!mounted) return;

    // Switch to Overview tab
    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    navProvider.changeTab(0);

    Navigator.pop(context);
  }

  bool _hasChanges() {
    final maintenanceCal =
        double.tryParse(_maintenanceCalController.text) ?? 0.0;
    final protein = double.tryParse(_proteinController.text) ?? 0.0;
    final proteinMultiplier =
        double.tryParse(_proteinMultiplierController.text) ?? 0.0;
    final fat = double.tryParse(_fatController.text) ?? 0.0;
    final carbs = double.tryParse(_carbController.text) ?? 0.0;
    final fiber = double.tryParse(_fiberController.text) ?? 0.0;
    final anchorWeight = double.tryParse(_anchorWeightController.text) ?? 0.0;
    final delta = double.tryParse(_fixedDeltaController.text) ?? 0.0;

    return _mode != _initialSettings.mode ||
        _calcMode != _initialSettings.calculationMode ||
        _proteinTargetMode != _initialSettings.proteinTargetMode ||
        _enableSmartTargets != _initialSettings.enableSmartTargets ||
        maintenanceCal != _initialSettings.maintenanceCaloriesStart ||
        protein != _initialSettings.proteinTarget ||
        proteinMultiplier != _initialSettings.proteinMultiplier ||
        fat != _initialSettings.fatTarget ||
        carbs != _initialSettings.carbTarget ||
        fiber != _initialSettings.fiberTarget ||
        anchorWeight != _initialSettings.anchorWeight ||
        (_mode != GoalMode.maintain && delta != _initialSettings.fixedDelta) ||
        (int.tryParse(_correctionWindowController.text) ?? 30) !=
            _initialSettings.correctionWindowDays ||
        _tdeeWindowDays != _initialSettings.tdeeWindowDays;
  }

  Future<void> _showDiscardChangesDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
          'You have unsaved changes. Do you want to save them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == 'discard') {
      if (mounted) Navigator.pop(context);
    } else if (result == 'save') {
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_hasChanges()) {
          Navigator.pop(context);
          return;
        }
        await _showDiscardChangesDialog();
      },
      child: ScreenBackground(
        appBar: AppBar(
          title: const Text('Goals & Targets'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        child: ListView(
          padding: const EdgeInsets.all(12.0),
          children: [
            const Text(
              'Goal Mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildModeSelector(),
            //const Divider(height: 40),
            const Divider(height: 20),
            SwitchListTile(
              title: const Text('Smart Target Calculations'),
              subtitle: const Text(
                'Targets are auto-adjusted based on weight/food trends after the first week.',
              ),
              value: _enableSmartTargets,
              onChanged: (val) => setState(() => _enableSmartTargets = val),
            ),
            SwitchListTile(
              title: const Text('Use Net Carbs'),
              subtitle: const Text('Display and track carbs minus fiber.'),
              value: _useNetCarbs,
              onChanged: (val) => setState(() => _useNetCarbs = val),
            ),
            if (_enableSmartTargets) _buildTdeeWindowSelector(),
            const Divider(height: 20),
            _buildTextField(
              controller: _anchorWeightController,
              label: _mode == GoalMode.maintain
                  ? 'Target Weight (lb)'
                  : 'Starting Weight (lb)',
              hint: 'Your weight',
            ),
            _buildTextField(
              controller: _maintenanceCalController,
              label: 'Initial TDEE',
              hint: 'Your estimated TDEE',
              keyboardType: TextInputType.number,
            ),
            if (_mode != GoalMode.maintain)
              _buildTextField(
                controller: _fixedDeltaController,
                label: _mode == GoalMode.gain ? 'Serplus' : 'Deficit',
                hint: 'e.g. 500',
                keyboardType: TextInputType.number,
              ),
            if (_mode == GoalMode.maintain)
              _buildTextField(
                controller: _correctionWindowController,
                label: 'Correct Weight Drift Back to the Target (days)',
                hint: 'e.g. 30',
                keyboardType: TextInputType.number,
              ),
            const Divider(height: 24),
            const Text(
              'Macro Split Strategy',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildCalcModeSelector(),
            const SizedBox(height: 10),
            _buildProteinSection(),
            const SizedBox(height: 10),
            if (_calcMode == MacroCalculationMode.proteinFat)
              _buildTextField(
                controller: _fatController,
                label: 'Fat (g)',
                keyboardType: TextInputType.number,
              ),
            if (_calcMode == MacroCalculationMode.proteinCarbs)
              _buildTextField(
                controller: _carbController,
                label: _useNetCarbs ? 'Net Carbs (g)' : 'Carbs (g)',
                keyboardType: TextInputType.number,
              ),
            _buildTextField(
              controller: _fiberController,
              label: 'Fiber (g)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(12),
              ),
              child: const Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runPreview() async {
    final goalsProvider = Provider.of<GoalsProvider>(context, listen: false);

    final previewSettings = GoalSettings(
      anchorWeight: double.tryParse(_anchorWeightController.text) ?? 0.0,
      maintenanceCaloriesStart:
          double.tryParse(_maintenanceCalController.text) ?? 2000.0,
      proteinTarget: double.tryParse(_proteinController.text) ?? 0.0,
      fatTarget: double.tryParse(_fatController.text) ?? 0.0,
      carbTarget: double.tryParse(_carbController.text) ?? 0.0,
      fiberTarget: double.tryParse(_fiberController.text) ?? 30.0,
      mode: _mode,
      calculationMode: _calcMode,
      proteinTargetMode: _proteinTargetMode,
      proteinMultiplier:
          double.tryParse(_proteinMultiplierController.text) ?? 1.0,
      fixedDelta: double.tryParse(_fixedDeltaController.text) ?? 0.0,
      lastTargetUpdate: goalsProvider.settings.lastTargetUpdate,
      isSet: goalsProvider.isGoalsSet,
      enableSmartTargets: _enableSmartTargets,
      correctionWindowDays:
          int.tryParse(_correctionWindowController.text) ?? 30,
      tdeeWindowDays: _tdeeWindowDays,
    );

    final result = await goalsProvider.recalculateTargets(previewSettings);

    if (!mounted) return;
    setState(() {
      _maintenanceCalController.text = result.settings.maintenanceCaloriesStart
          .roundToDouble()
          .toString();
      if (_proteinTargetMode == ProteinTargetMode.percentageOfWeight) {
        _proteinController.text = result.settings.proteinTarget
            .roundToDouble()
            .toString();
      }
    });
  }

  Widget _buildTdeeWindowSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Daily Energy Expenditure (TDEE) Window',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 14, label: Text('Responsive (14d)')),
              ButtonSegment(value: 28, label: Text('Balanced (28d)')),
              ButtonSegment(value: 60, label: Text('Smooth (60d)')),
            ],
            selected: {_tdeeWindowDays},
            onSelectionChanged: (newSelection) {
              setState(() {
                _tdeeWindowDays = newSelection.first;
              });
              _runPreview();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalcModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose what to calculate as the remainder:',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        SegmentedButton<MacroCalculationMode>(
          segments: const [
            ButtonSegment(
              value: MacroCalculationMode.proteinCarbs,
              label: Text('Calc Fat'),
              tooltip: 'Enter Protein & Carbs',
            ),
            ButtonSegment(
              value: MacroCalculationMode.proteinFat,
              label: Text('Calc Carbs'),
              tooltip: 'Enter Protein & Fat',
            ),
          ],
          selected: {_calcMode},
          onSelectionChanged: (newSelection) {
            setState(() {
              _calcMode = newSelection.first;
            });
          },
        ),
      ],
    );
  }

  Widget _buildProteinSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Protein Target',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ProteinTargetMode>(
          segments: const [
            ButtonSegment(value: ProteinTargetMode.fixed, label: Text('Fixed')),
            ButtonSegment(
              value: ProteinTargetMode.percentageOfWeight,
              label: Text('Multiplier'),
            ),
          ],
          selected: {_proteinTargetMode},
          onSelectionChanged: (newSelection) {
            setState(() {
              _proteinTargetMode = newSelection.first;
            });
          },
        ),
        const SizedBox(height: 10),
        if (_proteinTargetMode == ProteinTargetMode.fixed)
          _buildTextField(
            controller: _proteinController,
            label: 'Protein Target (g)',
            keyboardType: TextInputType.number,
          )
        else ...[
          _buildTextField(
            controller: _proteinMultiplierController,
            label: 'Multiplier (g per lb)',
            hint: 'e.g. 1.0',
            keyboardType: TextInputType.number,
          ),
        ],
      ],
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<GoalMode>(
      segments: const [
        ButtonSegment(value: GoalMode.lose, label: Text('Lose')),
        ButtonSegment(value: GoalMode.maintain, label: Text('Maintain')),
        ButtonSegment(value: GoalMode.gain, label: Text('Gain')),
      ],
      selected: {_mode},
      onSelectionChanged: (newSelection) {
        final newMode = newSelection.first;
        if (newMode == GoalMode.maintain && _mode != GoalMode.maintain) {
          // Switching TO maintain mode - set to latest raw weight
          final weightProvider = Provider.of<WeightProvider>(
            context,
            listen: false,
          );
          final weights = weightProvider.weights;
          if (weights.isNotEmpty) {
            final sorted = List<Weight>.from(weights)
              ..sort((a, b) => a.date.compareTo(b.date));
            _anchorWeightController.text = sorted.last.weight.toStringAsFixed(
              1,
            );
          }
        }
        setState(() {
          _mode = newMode;
        });
        _runPreview();
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboardType = const TextInputType.numberWithOptions(
      decimal: true,
    ),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        keyboardType: keyboardType,
      ),
    );
  }
}
