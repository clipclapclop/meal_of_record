import 'package:meal_of_record/models/logged_portion.dart';

class Meal {
  final DateTime timestamp;
  final List<LoggedPortion> loggedPortion;

  Meal({required this.timestamp, required this.loggedPortion});

  double get totalCalories => loggedPortion.fold(
    0,
    (sum, item) => sum + item.portion.food.calories * item.portion.grams,
  );
  double get totalProtein => loggedPortion.fold(
    0,
    (sum, item) => sum + item.portion.food.protein * item.portion.grams,
  );
  double get totalFat => loggedPortion.fold(
    0,
    (sum, item) => sum + item.portion.food.fat * item.portion.grams,
  );
  double get totalCarbs => loggedPortion.fold(
    0,
    (sum, item) => sum + item.portion.food.carbs * item.portion.grams,
  );
  double get totalFiber => loggedPortion.fold(
    0,
    (sum, item) => sum + item.portion.food.fiber * item.portion.grams,
  );
  double get totalNetCarbs =>
      (totalCarbs - totalFiber).clamp(0.0, double.infinity);
}
