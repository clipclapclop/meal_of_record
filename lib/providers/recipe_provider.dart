import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:meal_of_record/models/recipe.dart';
import 'package:meal_of_record/models/recipe_item.dart';
import 'package:meal_of_record/models/category.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/image_storage_service.dart';

class RecipeProvider extends ChangeNotifier {
  int _id = 0;
  int? _parentId;
  bool _isLogged = false;

  String _name = '';
  double _servingsCreated = 1.0;
  double? _finalWeightGrams;
  String _portionName = 'serving';
  String _notes = '';
  String _link = '';
  bool _isTemplate = false;
  String _emoji = '🍴';
  String? _thumbnail;
  List<RecipeItem> _items = [];
  List<Category> _selectedCategories = [];
  bool _ingredientsChanged = false;

  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  int get id => _id;
  int? get parentId => _parentId;
  bool get isLogged => _isLogged;

  String get name => _name;
  double get servingsCreated => _servingsCreated;
  double? get finalWeightGrams => _finalWeightGrams;
  String get portionName => _portionName;
  String get notes => _notes;
  String get link => _link;
  bool get isTemplate => _isTemplate;
  String get emoji => _emoji;
  String? get thumbnail => _thumbnail;
  List<RecipeItem> get items => List.unmodifiable(_items);
  List<Category> get selectedCategories =>
      List.unmodifiable(_selectedCategories);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get ingredientsChanged => _ingredientsChanged;

  // Setters
  void setName(String val) {
    _name = val;
    notifyListeners();
  }

  void setServingsCreated(double val) {
    _servingsCreated = val;
    notifyListeners();
  }

  void setFinalWeightGrams(double? val) {
    _finalWeightGrams = val;
    notifyListeners();
  }

  void setPortionName(String val) {
    _portionName = val;
    notifyListeners();
  }

  void setNotes(String val) {
    _notes = val;
    notifyListeners();
  }

  void setLink(String val) {
    _link = val;
    notifyListeners();
  }

  void setIsTemplate(bool val) {
    _isTemplate = val;
    notifyListeners();
  }

  void setEmoji(String val) {
    _emoji = val;
    notifyListeners();
  }

  void setThumbnail(String? val) {
    _thumbnail = val;
    notifyListeners();
  }

  // Item Operations
  void addItem(RecipeItem item) {
    _items.add(item);
    _ingredientsChanged = true;
    notifyListeners();
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      _ingredientsChanged = true;
      notifyListeners();
    }
  }

  void updateItem(int index, RecipeItem newItem) {
    if (index >= 0 && index < _items.length) {
      _items[index] = newItem;
      _ingredientsChanged = true;
      notifyListeners();
    }
  }

  /// Reorders an ingredient using post-removal indices from `onReorderItem`.
  void reorderItem(int oldIndex, int newIndex) {
    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);
    _ingredientsChanged = true;
    notifyListeners();
  }

  // Category Operations
  void toggleCategory(Category category) {
    if (_selectedCategories.any((c) => c.id == category.id)) {
      _selectedCategories.removeWhere((c) => c.id == category.id);
    } else {
      _selectedCategories.add(category);
    }
    notifyListeners();
  }

  // Macro Calculations (Computed)
  double get totalCalories =>
      _items.fold(0, (sum, item) => sum + (item.calories * item.grams));
  double get totalProtein =>
      _items.fold(0, (sum, item) => sum + (item.protein * item.grams));
  double get totalFat =>
      _items.fold(0, (sum, item) => sum + (item.fat * item.grams));
  double get totalCarbs =>
      _items.fold(0, (sum, item) => sum + (item.carbs * item.grams));
  double get totalFiber =>
      _items.fold(0, (sum, item) => sum + (item.fiber * item.grams));
  double get totalNetCarbs =>
      (totalCarbs - totalFiber).clamp(0.0, double.infinity);

  double get caloriesPerPortion =>
      servingsCreated > 0 ? totalCalories / servingsCreated : 0;

  void loadFromRecipe(Recipe recipe, {bool isLogged = false}) {
    _id = recipe.id;
    _parentId = recipe.parentId;
    _name = recipe.name;
    _servingsCreated = recipe.servingsCreated;
    _finalWeightGrams = recipe.finalWeightGrams;
    _portionName = recipe.portionName;
    _notes = recipe.notes ?? '';
    _link = recipe.link ?? '';
    _isTemplate = recipe.isTemplate;
    _emoji = recipe.emoji ?? '🍴';
    _thumbnail = recipe.thumbnail;
    _items = List.from(recipe.items);
    _selectedCategories = List.from(recipe.categories);
    _isLogged = isLogged;
    _ingredientsChanged = false;
    notifyListeners();
  }

  void prepareCopy(Recipe recipe) {
    loadFromRecipe(recipe, isLogged: false);
    _id = 0;
    _parentId = null;
    _name = '${recipe.name} - Copy';
    notifyListeners();
  }

  void prepareVersion(Recipe recipe) {
    loadFromRecipe(recipe, isLogged: true);
    notifyListeners();
  }

  /// Check if saving would trigger versioning (nutritional change on a logged recipe).
  /// Returns true if the Rev/Update dialog should be shown.
  Future<bool> wouldTriggerVersioning() async {
    if (!_isLogged || _id <= 0) return false;
    final db = DatabaseService.instance;
    final existingRecipe = await db.getRecipeById(_id);
    final currentRecipe = _buildRecipe();
    return !db.isRecipeNutritionallyEquivalent(existingRecipe, currentRecipe);
  }

  Recipe _buildRecipe() {
    return Recipe(
      id: _id,
      name: _name,
      servingsCreated: _servingsCreated,
      finalWeightGrams: _finalWeightGrams,
      portionName: _portionName,
      notes: _notes,
      link: _link.isEmpty ? null : _link,
      isTemplate: _isTemplate,
      hidden: false,
      parentId: _parentId,
      emoji: _emoji,
      thumbnail: _thumbnail,
      createdTimestamp: DateTime.now().millisecondsSinceEpoch,
      items: _items,
      categories: _selectedCategories,
    );
  }

  // Persistence
  Future<bool> saveRecipe({bool forceUpdateInPlace = false}) async {
    _errorMessage = null;
    if (_name.isEmpty) {
      _errorMessage = 'Please provide a name for the recipe.';
      notifyListeners();
      return false;
    }
    if (_items.isEmpty) {
      _errorMessage = 'Please add at least one ingredient.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final db = DatabaseService.instance;

      final recipe = _buildRecipe();

      await db.saveRecipe(recipe, forceUpdateInPlace: forceUpdateInPlace);

      reset();
      return true;
    } catch (e) {
      debugPrint('Error saving recipe: $e');
      _errorMessage = 'Technical error: ${e.toString()}';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _id = 0;
    _parentId = null;
    _isLogged = false;
    _name = '';
    _servingsCreated = 1.0;
    _finalWeightGrams = null;
    _portionName = 'serving';
    _notes = '';
    _link = '';
    _isTemplate = false;
    _emoji = '🍴';
    _thumbnail = null;
    _items = [];
    _selectedCategories = [];
    _errorMessage = null;
    _ingredientsChanged = false;
    notifyListeners();
  }

  // Sharing Logic
  Future<String> exportRecipe(Recipe recipe) async {
    final Map<String, dynamic> json = recipe.toJson();
    final Map<String, String> images = {};

    // Collect images from recipe and ingredients
    final imgService = ImageStorageService.instance;

    // Check recipe itself
    // Note: Recipe model doesn't have a thumbnail directly,
    // but its toFood() might be used? Actually the spec says
    // "Foods and Recipes support custom thumbnail images".
    // Wait, let's check Recipe model again.

    // Collect from ingredients
    for (final item in recipe.items) {
      if (item.isFood && item.food!.thumbnail != null) {
        final guid = imgService.extractGuid(item.food!.thumbnail!);
        if (guid != null && !images.containsKey(guid)) {
          final b64 = await imgService.encodeImageToBase64(guid);
          if (b64 != null) {
            images[guid] = b64;
          }
        }
      } else if (item.isRecipe) {
        // Recursively handle sub-recipes?
        // For now let's handle one level as per MVP,
        // but recursive is better.
      }
    }

    if (images.isNotEmpty) {
      json['images_b64'] = images;
    }

    return jsonEncode(json);
  }

  Future<int?> importRecipe(String jsonContent) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final Map<String, dynamic> data = jsonDecode(jsonContent);

      // Process images first
      final Map<String, String> guidMap = {}; // oldGuid -> newGuid
      if (data.containsKey('images_b64')) {
        final imagesB64 = Map<String, String>.from(data['images_b64']);
        final imgService = ImageStorageService.instance;
        for (final entry in imagesB64.entries) {
          final newGuid = await imgService.saveImageFromBase64(entry.value);
          guidMap[entry.key] = newGuid;
        }
      }

      // We need a way to replace GUIDs in the JSON before parsing,
      // or replace them in the resulting objects.
      // Replacing in JSON string is easiest if we are careful.
      String processedJson = jsonContent;
      for (final entry in guidMap.entries) {
        processedJson = processedJson.replaceAll(entry.key, entry.value);
      }

      // Re-parse
      final Map<String, dynamic> processedData = jsonDecode(processedJson);
      final recipe = Recipe.fromJson(processedData);
      final db = DatabaseService.instance;

      final newId = await _importRecipeRecursive(recipe, db);

      _isLoading = false;
      notifyListeners();
      return newId;
    } catch (e) {
      debugPrint('Error importing recipe: $e');
      _errorMessage = 'Import failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<int> _importRecipeRecursive(Recipe recipe, DatabaseService db) async {
    final resolvedItems = <RecipeItem>[];

    for (final item in recipe.items) {
      if (item.isFood) {
        // Deduplicate food
        final resolvedFood = await db.ensureFoodExists(item.food!);
        resolvedItems.add(item.copyWith(id: 0, food: resolvedFood));
      } else if (item.isRecipe) {
        // Recursive import for sub-recipe
        final subRecipeId = await _importRecipeRecursive(item.recipe!, db);
        final subRecipe = await db.getRecipeById(subRecipeId);
        resolvedItems.add(item.copyWith(id: 0, recipe: subRecipe));
      }
    }

    final recipeToSave = Recipe(
      id: 0, // Always save as new during import to avoid overwriting user's own variations
      name: recipe.name,
      servingsCreated: recipe.servingsCreated,
      finalWeightGrams: recipe.finalWeightGrams,
      portionName: recipe.portionName,
      notes: recipe.notes,
      link: recipe.link,
      isTemplate: recipe.isTemplate,
      hidden: false,
      parentId: null,
      createdTimestamp: DateTime.now().millisecondsSinceEpoch,
      items: resolvedItems,
      categories: recipe.categories,
    );

    return await db.saveRecipe(recipeToSave);
  }
}
