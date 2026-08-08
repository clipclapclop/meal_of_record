import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzy;
import 'package:meal_of_record/models/food.dart' as model;
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/open_food_facts_service.dart';
import 'package:meal_of_record/services/food_sorting_service.dart';

/// Holds search results with a separate display notes map,
/// so user-entered usageNotes are never overwritten.
class SearchResults {
  final List<model.Food> foods;
  final Map<int, String?> displayNotes; // "Logged", "In Recipe", etc.

  const SearchResults({required this.foods, required this.displayNotes});
}

class SearchService {
  final DatabaseService databaseService;
  final OffApiService offApiService;
  final String Function(String) emojiForFoodName;
  final FoodSortingService sortingService;

  SearchService({
    required this.databaseService,
    required this.offApiService,
    required this.emojiForFoodName,
    required this.sortingService,
  });

  static String _normalizeQuery(String q) =>
      q.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  // Helper function to apply fuzzy matching and sorting
  List<model.Food> _applyFuzzyMatching(String query, List<model.Food> foods) {
    if (query.isEmpty || foods.isEmpty) {
      return [];
    }
    final lowerCaseQuery = _normalizeQuery(query.toLowerCase());

    // Score each food based on match quality
    final scoredFoods = foods.map((food) {
      final lowerCaseName = _normalizeQuery(food.name.toLowerCase());
      int score;

      if (lowerCaseName == lowerCaseQuery) {
        score = 0; // Exact match = perfect score
      } else if (lowerCaseName.startsWith(lowerCaseQuery)) {
        score = 1; // Starts with = very high score
      } else if (lowerCaseName.contains(' $lowerCaseQuery')) {
        score = 2; // Contains as whole word = high score
      } else {
        // Use token set ratio for everything else.
        // We subtract from 100 because a higher ratio is better, but a lower sort score is better.
        score = 100 - fuzzy.tokenSetRatio(lowerCaseName, lowerCaseQuery);
      }
      return {'food': food, 'score': score};
    }).toList();

    // Sort by score (lower is better), then alphabetically as a tie-breaker
    scoredFoods.sort((a, b) {
      final scoreA = a['score'] as int;
      final scoreB = b['score'] as int;
      if (scoreA != scoreB) {
        return scoreA.compareTo(scoreB);
      }
      return (a['food'] as model.Food).name.toLowerCase().compareTo(
        (b['food'] as model.Food).name.toLowerCase(),
      );
    });

    final sortedFoods = scoredFoods
        .map((e) => e['food'] as model.Food)
        .toList();

    // Map back to list of foods and limit to a reasonable number
    return sortedFoods.take(50).toList();
  }

  Future<SearchResults> searchLocal(String query, {int? categoryId}) async {
    if (query.isEmpty) {
      if (categoryId != null) {
        return searchRecipesOnly(query, categoryId: categoryId);
      }
      return const SearchResults(foods: [], displayNotes: {});
    }

    final normalizedQuery = _normalizeQuery(query);

    // 1. Query live and reference databases separately
    final liveFoods = await databaseService.searchLiveFoodsByName(
      normalizedQuery,
    );
    final referenceFoods = await databaseService.searchReferenceFoodsByName(
      normalizedQuery,
    );

    // 2. Get usage statistics for live foods
    final liveFoodIds = liveFoods.map((f) => f.id).toList();
    final foodUsageStats = await databaseService.getFoodUsageStats(liveFoodIds);

    // 3. Filter reference foods that have live versions
    final filteredReferenceFoods = await databaseService
        .filterReferenceFoodsWithLiveVersions(referenceFoods, liveFoods);

    // 4. Sort live foods with complex weighted algorithm
    final sortedLiveFoods = sortingService.sortLiveFoods(
      liveFoods,
      foodUsageStats,
      normalizedQuery,
    );

    // 5. Sort reference foods with fuzzy matching
    final sortedReferenceFoods = sortingService.sortReferenceFoods(
      filteredReferenceFoods,
      normalizedQuery,
    );

    // 6. Combine results: strictly Live first, then Reference
    final combinedResults = [...sortedLiveFoods, ...sortedReferenceFoods];

    // 7. Limit to a reasonable number to avoid UI lag
    final limitedResults = combinedResults.take(50).toList();

    // 8. Get usage notes separately (not written to food.usageNote)
    final usageNotes = await databaseService.getFoodsUsageNotes(limitedResults);

    // 9. Apply emojis only (no usageNote overwrite)
    final resultsWithEmoji = limitedResults
        .map(
          (food) => food.copyWith(
            emoji:
                (food.emoji == null || food.emoji == '🍴' || food.emoji == '')
                ? emojiForFoodName(food.name)
                : food.emoji,
          ),
        )
        .toList();

    return SearchResults(foods: resultsWithEmoji, displayNotes: usageNotes);
  }

  /// Returns food suggestions for the empty-query state.
  /// Surfaces solo-logged foods scored by time-of-day and recency.
  Future<SearchResults> getSuggestions() async {
    final soloLogs = await databaseService.getSoloFoodLogs();
    if (soloLogs.isEmpty) {
      return const SearchResults(foods: [], displayNotes: {});
    }

    final rankedIds = sortingService.scoreSuggestions(
      soloLogs: soloLogs,
      now: DateTime.now(),
    );
    if (rankedIds.isEmpty) {
      return const SearchResults(foods: [], displayNotes: {});
    }

    final foodsMap = await databaseService.getFoodsByIds(rankedIds, 'live');

    // Reorder to match ranked order
    final orderedFoods = <model.Food>[];
    for (final id in rankedIds) {
      final food = foodsMap[id];
      if (food != null) orderedFoods.add(food);
    }

    final usageNotes = await databaseService.getFoodsUsageNotes(orderedFoods);

    final resultsWithEmoji = orderedFoods
        .map(
          (food) => food.copyWith(
            emoji:
                (food.emoji == null || food.emoji == '🍴' || food.emoji == '')
                ? emojiForFoodName(food.name)
                : food.emoji,
          ),
        )
        .toList();

    return SearchResults(foods: resultsWithEmoji, displayNotes: usageNotes);
  }

  Future<SearchResults> searchOff(String query) async {
    if (query.isEmpty) {
      return const SearchResults(foods: [], displayNotes: {});
    }
    final offResults = await offApiService.searchFoodsByName(query);
    final usageNotes = await databaseService.getFoodsUsageNotes(offResults);

    final resultsWithEmoji = offResults
        .map(
          (food) => food.copyWith(
            emoji:
                (food.emoji == null || food.emoji == '🍴' || food.emoji == '')
                ? emojiForFoodName(food.name)
                : food.emoji,
          ),
        )
        .toList();
    return SearchResults(
      foods: _applyFuzzyMatching(query, resultsWithEmoji),
      displayNotes: usageNotes,
    );
  }

  Future<SearchResults> getAllRecipesAsFoods({int? categoryId}) async {
    final recipes = await databaseService.getRecipesBySearch(
      '',
      categoryId: categoryId,
    );
    final foods = recipes.map((r) => r.toFood()).toList();
    final usageNotes = await databaseService.getFoodsUsageNotes(foods);

    final resultsWithEmoji = foods.map((food) {
      return food.copyWith(
        emoji: (food.emoji == null || food.emoji == '🍴' || food.emoji == '')
            ? emojiForFoodName(food.name)
            : food.emoji,
      );
    }).toList();

    return SearchResults(foods: resultsWithEmoji, displayNotes: usageNotes);
  }

  Future<SearchResults> searchRecipesOnly(
    String query, {
    int? categoryId,
  }) async {
    // 1. Get recipes from DB
    final recipeResults = await databaseService.getRecipesBySearch(
      query,
      categoryId: categoryId,
    );

    // 2. Get usage statistics for recipes
    final recipeIds = recipeResults.map((r) => r.id).toList();
    final recipeUsageStats = await databaseService.getRecipeUsageStats(
      recipeIds,
    );

    // 3. Sort recipes with weighted algorithm (Fuzzy + Usage)
    final sortedRecipes = sortingService.sortRecipes(
      recipeResults,
      recipeUsageStats,
      query,
    );

    final foods = sortedRecipes.map((r) => r.toFood()).toList();

    // 4. Limit to avoid UI lag
    final limitedResults = foods.take(50).toList();

    // 5. Get usage notes separately (not written to food.usageNote)
    final usageNotes = await databaseService.getFoodsUsageNotes(limitedResults);

    final resultsWithEmoji = limitedResults.map((food) {
      return food.copyWith(
        emoji: (food.emoji == null || food.emoji == '🍴' || food.emoji == '')
            ? emojiForFoodName(food.name)
            : food.emoji,
      );
    }).toList();

    return SearchResults(foods: resultsWithEmoji, displayNotes: usageNotes);
  }
}
