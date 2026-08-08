import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/meal.dart';
import 'package:meal_of_record/screens/qr_portion_sharing_screen.dart';
import 'package:meal_of_record/utils/math_evaluator.dart';

class MealPortionScreen extends StatefulWidget {
  final Meal meal;

  const MealPortionScreen({super.key, required this.meal});

  @override
  State<MealPortionScreen> createState() => _MealPortionScreenState();
}

class _MealPortionScreenState extends State<MealPortionScreen> {
  final TextEditingController _gramsController = TextEditingController();

  double get _mealTotalGrams =>
      widget.meal.loggedPortion.fold(0.0, (sum, lp) => sum + lp.portion.grams);

  double get _desiredGrams {
    final text = _gramsController.text.trim();
    return MathEvaluator.evaluate(text) ?? 0.0;
  }

  double get _scaleFactor {
    final total = _mealTotalGrams;
    if (total <= 0) return 0.0;
    return _desiredGrams / total;
  }

  List<FoodPortion> get _scaledPortions {
    final factor = _scaleFactor;
    return widget.meal.loggedPortion.map((lp) {
      return FoodPortion(
        food: lp.portion.food,
        grams: lp.portion.grams * factor,
        unit: lp.portion.unit,
      );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _gramsController.text = _mealTotalGrams.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _gramsController.dispose();
    super.dispose();
  }

  void _share() {
    if (_scaleFactor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrPortionSharingScreen(portions: _scaledPortions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mealTime = DateFormat.jm().format(widget.meal.timestamp);
    final totalGrams = _mealTotalGrams;

    return Scaffold(
      appBar: AppBar(title: Text('Meal at $mealTime')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Total weight: ${totalGrams.toStringAsFixed(0)}g',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gramsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Desired total grams',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            _buildScaledMacros(),
            const SizedBox(height: 8),
            Expanded(child: _buildIngredientList()),
            const SizedBox(height: 8),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildScaledMacros() {
    final factor = _scaleFactor;
    final cal = widget.meal.totalCalories * factor;
    final p = widget.meal.totalProtein * factor;
    final f = widget.meal.totalFat * factor;
    final c = widget.meal.totalCarbs * factor;
    final fb = widget.meal.totalFiber * factor;

    return Wrap(
      spacing: 12,
      children: [
        Text('🔥${cal.toInt()}'),
        Text('P: ${p.toStringAsFixed(0)}'),
        Text('F: ${f.toStringAsFixed(0)}'),
        Text('C: ${c.toStringAsFixed(0)}'),
        Text('Fb: ${fb.toStringAsFixed(0)}'),
      ],
    );
  }

  Widget _buildIngredientList() {
    final factor = _scaleFactor;

    return ListView.separated(
      itemCount: widget.meal.loggedPortion.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final lp = widget.meal.loggedPortion[index];
        final scaledGrams = lp.portion.grams * factor;
        final food = lp.portion.food;

        return ListTile(
          dense: true,
          title: Text(food.name),
          subtitle: Text(
            '${lp.portion.grams.toStringAsFixed(0)}g → ${scaledGrams.toStringAsFixed(0)}g',
          ),
          trailing: Text(
            '🔥${(food.calories * scaledGrams).toInt()} '
            'P${(food.protein * scaledGrams).toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share'),
          ),
        ),
      ],
    );
  }
}
