import 'package:flutter/material.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/recipe_provider.dart';
import 'package:meal_of_record/models/food_portion.dart' as model_portion;
import 'package:meal_of_record/models/recipe.dart' as model_recipe;
import 'package:meal_of_record/models/category.dart' as model_cat;
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/search/slidable_recipe_search_result.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:meal_of_record/models/search_config.dart';

class RecipeSearchView extends StatefulWidget {
  final SearchConfig config;
  const RecipeSearchView({super.key, required this.config});

  @override
  State<RecipeSearchView> createState() => _RecipeSearchViewState();
}

class _RecipeSearchViewState extends State<RecipeSearchView> {
  List<model_cat.Category> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    // Trigger initial search to show all recipes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SearchProvider>(context, listen: false).textSearch('');
    });
  }

  Future<void> _loadCategories() async {
    final cats = await DatabaseService.instance.getCategories();
    if (mounted) {
      setState(() {
        _categories = cats;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchProvider = Provider.of<SearchProvider>(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () async {
                    Provider.of<RecipeProvider>(context, listen: false).reset();
                    final saved = await Navigator.pushNamed(
                      context,
                      AppRouter.recipeEditRoute,
                    );
                    if (saved == true && context.mounted) {
                      searchProvider.textSearch('');
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int?>(
                  initialValue: searchProvider.selectedCategoryId,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                    border: OutlineInputBorder(),
                    labelText: 'Category',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Categories'),
                    ),
                    ..._categories.map(
                      (cat) => DropdownMenuItem(
                        value: cat.id,
                        child: Text(cat.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    searchProvider.setSelectedCategoryId(val);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Consumer<SearchProvider>(
            builder: (context, provider, child) {
              final recipes = provider.searchResults
                  .where((food) => food.source == 'recipe')
                  .toList();

              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (recipes.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant_menu, size: 64, color: Colors.grey),
                      SizedBox(height: 10),
                      Text(
                        'No recipes found',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: recipes.length,
                itemBuilder: (context, index) {
                  final food = recipes[index];
                  final db = DatabaseService.instance;
                  final recipeProvider = Provider.of<RecipeProvider>(
                    context,
                    listen: false,
                  );
                  final searchProvider = Provider.of<SearchProvider>(
                    context,
                    listen: false,
                  );

                  final int existingIndex;
                  if (widget.config.onSaveOverride != null) {
                    // Recipe context: check if already in recipe items
                    existingIndex = recipeProvider.items.indexWhere(
                      (item) =>
                          item.recipe?.id == food.id ||
                          item.food?.id == food.id,
                    );
                  } else {
                    // Day context: check if already in log queue
                    final logProvider = Provider.of<LogProvider>(
                      context,
                      listen: false,
                    );
                    existingIndex = logProvider.logQueue.indexWhere(
                      (p) =>
                          (p.food.id != 0 &&
                              p.food.id == food.id &&
                              p.food.source == food.source) ||
                          (food.id == 0 &&
                              food.source == 'off' &&
                              p.food.source == 'off' &&
                              p.food.sourceBarcode == food.sourceBarcode),
                    );
                  }
                  final bool isUpdate = existingIndex != -1;

                  return FutureBuilder<model_recipe.Recipe>(
                    key: ValueKey('recipe_${food.id}'),
                    future: db.getRecipeById(food.id),
                    builder: (context, snapshot) {
                      final recipe = snapshot.data;
                      String? finalNote = provider.displayNotes[food.id];
                      if (recipe?.isTemplate ?? false) {
                        finalNote = finalNote != null
                            ? 'Only Dumpable • $finalNote'
                            : 'Only Dumpable';
                      }

                      return SlidableRecipeSearchResult(
                        food: food,
                        note: finalNote,
                        isUpdate: isUpdate,
                        onAdd: (selectedUnit) async {
                          if (recipe == null) return;
                          if (recipe.isTemplate && context.mounted) {
                            final quantity = recipe.totalGrams > 0
                                ? selectedUnit.grams / recipe.totalGrams
                                : 1.0;
                            Provider.of<LogProvider>(
                              context,
                              listen: false,
                            ).dumpRecipeToQueue(recipe, quantity: quantity);
                            searchProvider.clearSearch();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Dumped ${recipe.name} (${selectedUnit.grams.toStringAsFixed(0)}g) into Log Queue',
                                ),
                              ),
                            );
                            return;
                          }

                          if (isUpdate &&
                              widget.config.onSaveOverride == null) {
                            // Day context: Edit existing
                            if (context.mounted) {
                              final logProvider = Provider.of<LogProvider>(
                                context,
                                listen: false,
                              );
                              final existingPortion =
                                  logProvider.logQueue[existingIndex];
                              // Reload food from database to get latest changes (e.g., image)
                              final reloadedFood = await DatabaseService
                                  .instance
                                  .getFoodById(food.id, 'live');

                              if (reloadedFood == null) {
                                // Fallback to cached food if reload fails
                                return;
                              }

                              if (!context.mounted) return;

                              final unitServing = reloadedFood.servings
                                  .firstWhere(
                                    (s) => s.unit == existingPortion.unit,
                                    orElse: () => reloadedFood.servings.first,
                                  );

                              final result =
                                  await Navigator.push<
                                    model_portion.FoodPortion
                                  >(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => QuantityEditScreen(
                                        config: QuantityEditConfig(
                                          context: widget.config.context,
                                          food: reloadedFood,
                                          isUpdate: true,
                                          initialUnit: existingPortion.unit,
                                          initialQuantity: unitServing
                                              .quantityFromGrams(
                                                existingPortion.grams,
                                              ),
                                          originalGrams: existingPortion.grams,
                                        ),
                                      ),
                                    ),
                                  );
                              if (result != null && context.mounted) {
                                logProvider.updateFoodInQueue(
                                  existingIndex,
                                  result,
                                );
                              }
                            }
                            return;
                          }

                          final portion = model_portion.FoodPortion(
                            food: food,
                            grams: selectedUnit.grams,
                            unit: selectedUnit.unit,
                          );
                          if (widget.config.onSaveOverride != null) {
                            widget.config.onSaveOverride!(portion);
                          } else {
                            Provider.of<LogProvider>(
                              context,
                              listen: false,
                            ).addFoodToQueue(portion);
                            searchProvider.clearSearch();
                          }
                        },
                        onTap: (selectedUnit) async {
                          if (recipe == null) return;

                          // Dump-only recipes: open QuantityEditScreen with the recipe's food
                          if (recipe.isTemplate && context.mounted) {
                            final recipeFood = recipe.toFood();
                            final result =
                                await Navigator.push<model_portion.FoodPortion>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => QuantityEditScreen(
                                      config: QuantityEditConfig(
                                        context: widget.config.context,
                                        food: recipeFood,
                                        initialUnit: 'g',
                                        initialQuantity: recipe.totalGrams,
                                        canShare: true,
                                        sourceRecipe: recipe,
                                      ),
                                    ),
                                  ),
                                );
                            if (result != null && context.mounted) {
                              final logProvider = Provider.of<LogProvider>(
                                context,
                                listen: false,
                              );
                              final quantity = result.grams / recipe.totalGrams;
                              logProvider.dumpRecipeToQueue(
                                recipe,
                                quantity: quantity,
                              );
                              searchProvider.clearSearch();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Dumped ${recipe.name} (${result.grams.toStringAsFixed(0)}g) into Log Queue',
                                  ),
                                ),
                              );
                            }
                            return;
                          }

                          if (context.mounted) {
                            final logProvider = Provider.of<LogProvider>(
                              context,
                              listen: false,
                            );

                            final existingPortion =
                                (isUpdate &&
                                    widget.config.onSaveOverride == null)
                                ? logProvider.logQueue[existingIndex]
                                : null;
                            final unitServing = existingPortion != null
                                ? food.servings.firstWhere(
                                    (s) => s.unit == existingPortion.unit,
                                    orElse: () => food.servings.first,
                                  )
                                : null;

                            final initialUnit = existingPortion != null
                                ? existingPortion.unit
                                : selectedUnit.unit;
                            // Use quantity from dropdown (which now includes last logged info)
                            final initialQuantity =
                                (existingPortion != null && unitServing != null)
                                ? unitServing.quantityFromGrams(
                                    existingPortion.grams,
                                  )
                                : selectedUnit.quantity;
                            final originalGrams = existingPortion != null
                                ? existingPortion.grams
                                : 0.0;

                            final result =
                                await Navigator.push<model_portion.FoodPortion>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => QuantityEditScreen(
                                      config: QuantityEditConfig(
                                        context: widget.config.context,
                                        food: food,
                                        isUpdate:
                                            isUpdate &&
                                            widget.config.onSaveOverride ==
                                                null,
                                        initialUnit: initialUnit,
                                        initialQuantity: initialQuantity,
                                        originalGrams: originalGrams,
                                        canShare: true,
                                        sourceRecipe: recipe,
                                      ),
                                    ),
                                  ),
                                );
                            if (result != null && context.mounted) {
                              if (widget.config.onSaveOverride != null) {
                                widget.config.onSaveOverride!(result);
                              } else {
                                if (isUpdate) {
                                  logProvider.updateFoodInQueue(
                                    existingIndex,
                                    result,
                                  );
                                } else {
                                  logProvider.addFoodToQueue(result);
                                  searchProvider.clearSearch();
                                }
                              }
                            }
                          }
                        },
                        onEdit: () async {
                          if (recipe == null) return;
                          final isLogged = await db.isRecipeLogged(food.id);
                          if (isLogged) {
                            recipeProvider.prepareVersion(recipe);
                          } else {
                            recipeProvider.loadFromRecipe(recipe);
                          }
                          if (context.mounted) {
                            final saved = await Navigator.pushNamed(
                              context,
                              AppRouter.recipeEditRoute,
                            );
                            if (saved == true) {
                              searchProvider.textSearch('');
                            }
                          }
                        },
                        onCopy: () async {
                          if (recipe == null) return;
                          recipeProvider.prepareCopy(recipe);
                          if (context.mounted) {
                            final saved = await Navigator.pushNamed(
                              context,
                              AppRouter.recipeEditRoute,
                            );
                            if (saved == true) {
                              searchProvider.textSearch('');
                            }
                          }
                        },
                        onDelete: () async {
                          await db.deleteRecipe(food.id);
                          searchProvider.textSearch('');
                        },
                        onDecompose: (selectedUnit) async {
                          if (recipe == null) return;
                          if (context.mounted) {
                            final quantity = recipe.totalGrams > 0
                                ? selectedUnit.grams / recipe.totalGrams
                                : 1.0;
                            Provider.of<LogProvider>(
                              context,
                              listen: false,
                            ).dumpRecipeToQueue(recipe, quantity: quantity);
                            searchProvider.clearSearch();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Dumped ${recipe.name} (${selectedUnit.grams.toStringAsFixed(0)}g) into Log Queue',
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
