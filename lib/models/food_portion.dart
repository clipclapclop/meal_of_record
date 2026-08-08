import 'package:meal_of_record/models/food.dart';

class FoodPortion {
  final Food food;
  final double grams; // weight of the portion in grams
  final String unit; // unit of measurement of the portion

  FoodPortion({required this.food, required this.grams, required this.unit});

  double get quantity {
    if (unit == 'g') return grams;
    if (food.servings.isEmpty) {
      return grams; // Fallback to grams if no servings defined
    }

    final serving = food.servings.firstWhere(
      (s) => s.unit == unit,
      orElse: () => food.servings.first,
    );
    return serving.quantityFromGrams(grams);
  }
}
