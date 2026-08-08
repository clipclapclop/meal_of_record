import 'package:flutter/foundation.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/services/database_service.dart';

class DebugSeeder {
  static Future<void> seed() async {
    if (!kDebugMode) return;

    debugPrint('DebugSeeder: Starting seed process...');
    final now = DateTime.now();

    debugPrint('DebugSeeder: Checking for existing logs...');
    final todayLogs = await DatabaseService.instance.getLoggedPortionsForDate(
      now,
    );
    debugPrint('DebugSeeder: Found ${todayLogs.length} logs for today.');

    if (todayLogs.isNotEmpty) {
      debugPrint('DebugSeeder: Logs already exist for today. Skipping seed.');
      return;
    }

    debugPrint('DebugSeeder: Seeding database with test data...');

    // Fetch some foods from the database to log
    // We'll search for common items
    debugPrint('DebugSeeder: Searching for "apple"...');
    final foods = await DatabaseService.instance.searchFoodsByName('apple');
    debugPrint('DebugSeeder: Found ${foods.length} foods matching "apple".');

    if (foods.isEmpty) {
      debugPrint(
        'DebugSeeder: No foods found to seed. Make sure the DB is initialized.',
      );
      return;
    }

    final apple = foods.first;

    // Create portions for Today
    final todayPortions = [FoodPortion(food: apple, grams: 150, unit: 'g')];

    // Create portions for Yesterday
    final yesterdayPortions = [FoodPortion(food: apple, grams: 100, unit: 'g')];

    debugPrint('DebugSeeder: Logging today portions...');
    await DatabaseService.instance.logPortions(todayPortions, now);
    debugPrint('DebugSeeder: Today portions logged.');

    debugPrint('DebugSeeder: Logging yesterday portions...');
    await DatabaseService.instance.logPortions(
      yesterdayPortions,
      now.subtract(const Duration(days: 1)),
    );
    debugPrint('DebugSeeder: Yesterday portions logged.');

    debugPrint('DebugSeeder: Seeding complete.');
  }
}
