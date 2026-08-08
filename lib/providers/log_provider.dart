import 'package:flutter/material.dart';
import 'package:meal_of_record/models/food_portion.dart' as model;
import 'package:meal_of_record/models/logged_portion.dart' as model;
import 'package:meal_of_record/models/recipe.dart' as model;
import 'package:meal_of_record/models/food.dart' as model_food;
import 'package:meal_of_record/services/emoji_service.dart';
import 'package:meal_of_record/models/daily_macro_stats.dart';
import 'package:meal_of_record/services/database_service.dart';

class LogProvider extends ChangeNotifier {
  LogProvider() {
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      await loadLoggedPortionsForDate(DateTime.now());
    } catch (_) {
      // Database may not be initialized yet (e.g. in tests)
    }
  }

  final List<model.FoodPortion> _logQueue = [];
  List<model.LoggedPortion> _loggedPortion = [];
  bool _isFasted = false;
  DateTime _currentDate = DateTime.now();

  // Multiselect state
  final Set<int> _selectedPortionIds = {};

  // Computed getters — logged macros
  double get loggedCalories => _loggedPortion.fold(
    0.0,
    (sum, item) => sum + item.portion.food.calories * item.portion.grams,
  );
  double get loggedProtein => _loggedPortion.fold(
    0.0,
    (sum, item) => sum + item.portion.food.protein * item.portion.grams,
  );
  double get loggedFat => _loggedPortion.fold(
    0.0,
    (sum, item) => sum + item.portion.food.fat * item.portion.grams,
  );
  double get loggedCarbs => _loggedPortion.fold(
    0.0,
    (sum, item) => sum + item.portion.food.carbs * item.portion.grams,
  );
  double get loggedFiber => _loggedPortion.fold(
    0.0,
    (sum, item) => sum + item.portion.food.fiber * item.portion.grams,
  );

  // Computed getters — queued macros
  double get queuedCalories =>
      _logQueue.fold(0.0, (sum, item) => sum + item.food.calories * item.grams);
  double get queuedProtein =>
      _logQueue.fold(0.0, (sum, item) => sum + item.food.protein * item.grams);
  double get queuedFat =>
      _logQueue.fold(0.0, (sum, item) => sum + item.food.fat * item.grams);
  double get queuedCarbs =>
      _logQueue.fold(0.0, (sum, item) => sum + item.food.carbs * item.grams);
  double get queuedFiber =>
      _logQueue.fold(0.0, (sum, item) => sum + item.food.fiber * item.grams);

  // Total getters
  double get totalCalories => loggedCalories + queuedCalories;
  double get totalProtein => loggedProtein + queuedProtein;
  double get totalFat => loggedFat + queuedFat;
  double get totalCarbs => loggedCarbs + queuedCarbs;
  double get totalFiber => loggedFiber + queuedFiber;

  // Net carb getters (gross carbs minus fiber, clamped to 0)
  double get loggedNetCarbs =>
      (loggedCarbs - loggedFiber).clamp(0.0, double.infinity);
  double get queuedNetCarbs =>
      (queuedCarbs - queuedFiber).clamp(0.0, double.infinity);
  double get totalNetCarbs =>
      (totalCarbs - totalFiber).clamp(0.0, double.infinity);

  List<model.FoodPortion> get logQueue => _logQueue;
  List<model.LoggedPortion> get loggedPortion => _loggedPortion;
  bool get isFasted => _isFasted;
  DateTime get currentDate => _currentDate;
  Set<int> get selectedPortionIds => _selectedPortionIds;
  bool get hasSelectedPortions => _selectedPortionIds.isNotEmpty;
  int get selectedPortionCount => _selectedPortionIds.length;

  // Queue Operations
  void addFoodToQueue(model.FoodPortion serving) {
    _logQueue.add(serving);
    notifyListeners();
  }

  void addRecipeToQueue(model.Recipe recipe, {double quantity = 1.0}) {
    if (recipe.isTemplate) {
      dumpRecipeToQueue(recipe, quantity: quantity);
    } else {
      // Not a template: Add as a single item (frozen)
      final food = recipe.toFood();
      // Ensure emoji is set correctly for the recipe food
      final enrichedFood = food.copyWith(
        emoji: (food.emoji == null || food.emoji == '🍴' || food.emoji == '')
            ? emojiForFoodName(food.name)
            : food.emoji,
      );
      addFoodToQueue(
        model.FoodPortion(
          food: enrichedFood,
          grams: recipe.gramsPerPortion * quantity,
          unit: recipe.portionName,
        ),
      );
    }
  }

  void dumpRecipeToQueue(model.Recipe recipe, {double quantity = 1.0}) {
    final portions = dumpRecipePortionsAsList(recipe, quantity: quantity);
    for (final portion in portions) {
      addFoodToQueue(portion);
    }
  }

  /// Returns the flattened list of FoodPortions for a recipe dump without
  /// adding them to the queue. Useful for sharing and meal portioning.
  List<model.FoodPortion> dumpRecipePortionsAsList(
    model.Recipe recipe, {
    double quantity = 1.0,
  }) {
    final result = <model.FoodPortion>[];
    _collectRecipePortions(recipe, quantity, result);
    return result;
  }

  void _collectRecipePortions(
    model.Recipe recipe,
    double quantity,
    List<model.FoodPortion> result,
  ) {
    for (final item in recipe.items) {
      if (item.isFood) {
        final food = item.food!;
        final enrichedFood = food.copyWith(
          emoji: (food.emoji == null || food.emoji == '🍴' || food.emoji == '')
              ? emojiForFoodName(food.name)
              : food.emoji,
        );
        result.add(
          model.FoodPortion(
            food: enrichedFood,
            grams: item.grams * quantity,
            unit: item.unit,
          ),
        );
      } else if (item.isRecipe) {
        _collectRecipePortions(
          item.recipe!,
          (item.grams / item.recipe!.totalGrams) * quantity,
          result,
        );
      }
    }
  }

  void updateFoodInQueue(int index, model.FoodPortion newPortion) {
    if (index >= 0 && index < _logQueue.length) {
      _logQueue[index] = newPortion;
      notifyListeners();
    }
  }

  void removeFoodFromQueue(model.FoodPortion serving) {
    _logQueue.remove(serving);
    notifyListeners();
  }

  void clearQueue() {
    _logQueue.clear();
    notifyListeners();
  }

  /// Refreshes food references in the log queue after a food is edited
  /// This ensures that when a food's name, image, or other metadata is updated,
  /// the log queue reflects the latest version of the food.
  Future<void> refreshFoodInQueue(
    int foodId,
    model_food.Food updatedFood,
  ) async {
    bool changed = false;
    for (int i = 0; i < _logQueue.length; i++) {
      final portion = _logQueue[i];
      // Match by food ID or by barcode (for OFF foods)
      if (portion.food.id == foodId ||
          (portion.food.source == 'off' &&
              portion.food.sourceBarcode != null &&
              portion.food.sourceBarcode == updatedFood.sourceBarcode)) {
        // Update the portion with the new food reference
        _logQueue[i] = model.FoodPortion(
          food: updatedFood,
          grams: portion.grams,
          unit: portion.unit,
        );
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  Future<void> logQueueToDatabase() async {
    if (_logQueue.isEmpty) return;

    await DatabaseService.instance.logPortions(_logQueue, DateTime.now());
    clearQueue();
    await loadLoggedPortionsForDate(DateTime.now());
  }

  // Database Operations
  Future<void> loadLoggedPortionsForDate(DateTime date) async {
    _currentDate = date;
    final portions = await DatabaseService.instance.getLoggedPortionsForDate(
      date,
    );

    // Enrich with smart emojis
    _loggedPortion = portions.map((p) {
      final food = p.portion.food;
      if (food.emoji == null || food.emoji == '🍴' || food.emoji == '') {
        final enrichedFood = food.copyWith(emoji: emojiForFoodName(food.name));
        return model.LoggedPortion(
          id: p.id,
          timestamp: p.timestamp,
          portion: model.FoodPortion(
            food: enrichedFood,
            grams: p.portion.grams,
            unit: p.portion.unit,
          ),
        );
      }
      return p;
    }).toList();

    _isFasted = await DatabaseService.instance.isFastedOnDate(date);
    notifyListeners();
  }

  Future<void> logFasted(DateTime date) async {
    await DatabaseService.instance.logFasted(date);
    clearQueue();
    await loadLoggedPortionsForDate(date);
  }

  Future<void> toggleFasted(DateTime date) async {
    await DatabaseService.instance.toggleFasted(date);
    await loadLoggedPortionsForDate(date);
  }

  Future<void> deleteLoggedPortion(model.LoggedPortion food) async {
    if (food.id == null) return;

    await DatabaseService.instance.deleteLoggedPortion(food.id!);

    _loggedPortion.removeWhere((item) => item.id == food.id);
    notifyListeners();
  }

  Future<void> updateLoggedPortion(
    model.LoggedPortion oldLoggedPortion,
    model.FoodPortion newPortion,
  ) async {
    if (oldLoggedPortion.id == null) return;

    await DatabaseService.instance.updateLoggedPortion(
      oldLoggedPortion.id!,
      newPortion,
    );

    // Reload the logged portions for the current date
    final date = oldLoggedPortion.timestamp;
    await loadLoggedPortionsForDate(date);
  }

  Future<List<DailyMacroStats>> getDailyMacroStats(
    DateTime start,
    DateTime end,
  ) async {
    final dtos = await DatabaseService.instance.getLoggedMacrosForDateRange(
      start,
      end,
    );
    return DailyMacroStats.fromDTOS(dtos, start, end);
  }

  Future<DailyMacroStats> getTodayStats() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final stats = await getDailyMacroStats(today, today);
    return stats.first;
  }

  // Multiselect operations
  void togglePortionSelection(int portionId) {
    if (_selectedPortionIds.contains(portionId)) {
      _selectedPortionIds.remove(portionId);
    } else {
      _selectedPortionIds.add(portionId);
    }
    notifyListeners();
  }

  void selectPortion(int portionId) {
    _selectedPortionIds.add(portionId);
    notifyListeners();
  }

  void deselectPortion(int portionId) {
    _selectedPortionIds.remove(portionId);
    notifyListeners();
  }

  void clearSelection() {
    _selectedPortionIds.clear();
    notifyListeners();
  }

  bool isPortionSelected(int portionId) {
    return _selectedPortionIds.contains(portionId);
  }

  // Copy selected portions to log queue
  void copySelectedPortionsToQueue() {
    if (_selectedPortionIds.isEmpty) return;

    // Find selected portions and copy their FoodPortion to the queue
    for (final loggedPortion in _loggedPortion) {
      if (loggedPortion.id != null &&
          _selectedPortionIds.contains(loggedPortion.id!)) {
        addFoodToQueue(loggedPortion.portion);
      }
    }

    // Clear selection after copying
    clearSelection();
  }

  // Move selected portions to a new date and time
  Future<void> moveSelectedPortions(DateTime newTimestamp) async {
    if (_selectedPortionIds.isEmpty) return;

    // Collect the IDs of selected portions
    final selectedIds = <int>[];
    for (final loggedPortion in _loggedPortion) {
      if (loggedPortion.id != null &&
          _selectedPortionIds.contains(loggedPortion.id!)) {
        selectedIds.add(loggedPortion.id!);
      }
    }

    // Update timestamps in the database
    await DatabaseService.instance.updateLoggedPortionsTimestamp(
      selectedIds,
      newTimestamp,
    );

    // Clear selection after moving
    clearSelection();

    // Reload the logged portions for the current date
    // Note: The caller should handle navigation to the new date
  }

  /// Deletes all currently selected portions from the database
  ///
  /// This method:
  /// 1. Collects the IDs of all selected portions
  /// 2. Deletes them from the database in a batch operation
  /// 3. Removes them from the local state
  /// 4. Recalculates the logged macros
  /// 5. Clears the selection
  ///
  /// The user remains on the current date (no navigation occurs).
  Future<void> deleteSelectedPortions() async {
    if (_selectedPortionIds.isEmpty) return;

    // Collect the IDs of selected portions
    final selectedIds = <int>[];
    for (final loggedPortion in _loggedPortion) {
      if (loggedPortion.id != null &&
          _selectedPortionIds.contains(loggedPortion.id!)) {
        selectedIds.add(loggedPortion.id!);
      }
    }

    // Delete from database
    await DatabaseService.instance.deleteLoggedPortions(selectedIds);

    // Remove from local state
    _loggedPortion.removeWhere(
      (item) => item.id != null && selectedIds.contains(item.id!),
    );

    // Clear selection
    clearSelection();
  }
}
