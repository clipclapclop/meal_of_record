import 'package:meal_of_record/models/recipe_item.dart';
import 'package:meal_of_record/models/category.dart';
import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/food_serving.dart';

class Recipe {
  final int id;
  final String name;
  final double servingsCreated;
  final double? finalWeightGrams;
  final String portionName;
  final String? notes;
  final String? link;
  final bool isTemplate;
  final bool hidden;
  final int? parentId;
  final int createdTimestamp;
  final String? emoji;
  final String? thumbnail;
  final List<RecipeItem> items;
  final List<Category> categories;

  Recipe({
    required this.id,
    required this.name,
    this.servingsCreated = 1.0,
    this.finalWeightGrams,
    this.portionName = 'portion',
    this.notes,
    this.link,
    this.isTemplate = false,
    this.hidden = false,
    this.parentId,
    this.emoji,
    this.thumbnail,
    required this.createdTimestamp,
    this.items = const [],
    this.categories = const [],
  });

  double get totalGrams =>
      finalWeightGrams ?? items.fold(0, (sum, item) => sum + item.grams);

  double get totalCalories =>
      items.fold(0, (sum, item) => sum + (item.calories * item.grams));
  double get totalProtein =>
      items.fold(0, (sum, item) => sum + (item.protein * item.grams));
  double get totalFat =>
      items.fold(0, (sum, item) => sum + (item.fat * item.grams));
  double get totalCarbs =>
      items.fold(0, (sum, item) => sum + (item.carbs * item.grams));
  double get totalFiber =>
      items.fold(0, (sum, item) => sum + (item.fiber * item.grams));

  double get caloriesPerGram => totalCalories / totalGrams;
  double get proteinPerGram => totalProtein / totalGrams;
  double get fatPerGram => totalFat / totalGrams;
  double get carbsPerGram => totalCarbs / totalGrams;
  double get fiberPerGram => totalFiber / totalGrams;
  double get netCarbsPerGram =>
      (carbsPerGram - fiberPerGram).clamp(0.0, double.infinity);

  double get caloriesPerPortion => totalCalories / servingsCreated;
  double get proteinPerPortion => totalProtein / servingsCreated;
  double get fatPerPortion => totalFat / servingsCreated;
  double get carbsPerPortion => totalCarbs / servingsCreated;
  double get fiberPerPortion => totalFiber / servingsCreated;
  double get totalNetCarbs =>
      (totalCarbs - totalFiber).clamp(0.0, double.infinity);
  double get netCarbsPerPortion =>
      (carbsPerPortion - fiberPerPortion).clamp(0.0, double.infinity);

  double get gramsPerPortion => totalGrams / servingsCreated;

  Food toFood() {
    return Food(
      id: id,
      name: name,
      source: 'recipe',
      calories: caloriesPerGram,
      protein: proteinPerGram,
      fat: fatPerGram,
      carbs: carbsPerGram,
      fiber: fiberPerGram,
      emoji: emoji,
      thumbnail: thumbnail,
      database: FoodDatabase.live,
      servings: [
        FoodServing(
          foodId: id,
          unit: portionName,
          grams: gramsPerPortion,
          quantity: 1.0,
        ),
        FoodServing(foodId: id, unit: 'g', grams: 1.0, quantity: 1.0),
      ],
    );
  }

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as int,
      name: json['name'] as String,
      servingsCreated: (json['servingsCreated'] as num).toDouble(),
      finalWeightGrams: (json['finalWeightGrams'] as num?)?.toDouble(),
      portionName: json['portionName'] as String,
      notes: json['notes'] as String?,
      link: json['link'] as String?,
      isTemplate: json['isTemplate'] as bool? ?? false,
      hidden: json['hidden'] as bool? ?? false,
      parentId: json['parentId'] as int?,
      emoji: json['emoji'] as String?,
      thumbnail: json['thumbnail'] as String?,
      createdTimestamp: json['createdTimestamp'] as int,
      items:
          (json['items'] as List<dynamic>?)
              ?.map((e) => RecipeItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      categories:
          (json['categories'] as List<dynamic>?)
              ?.map((e) => Category.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'servingsCreated': servingsCreated,
      'finalWeightGrams': finalWeightGrams,
      'portionName': portionName,
      'notes': notes,
      'link': link,
      'isTemplate': isTemplate,
      'hidden': hidden,
      'parentId': parentId,
      'emoji': emoji,
      'thumbnail': thumbnail,
      'createdTimestamp': createdTimestamp,
      'items': items.map((e) => e.toJson()).toList(),
      'categories': categories.map((e) => e.toJson()).toList(),
    };
  }
}
