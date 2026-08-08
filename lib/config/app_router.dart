import 'package:flutter/material.dart';
import 'package:meal_of_record/screens/goal_settings_screen.dart';
import 'package:meal_of_record/screens/qr_sharing_screen.dart';
import 'package:meal_of_record/screens/qr_portion_sharing_screen.dart';
import 'package:meal_of_record/screens/meal_portion_screen.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/meal.dart';
import 'package:meal_of_record/screens/data_management_screen.dart';
import 'package:meal_of_record/screens/search_screen.dart';
import 'package:meal_of_record/models/recipe.dart';
import 'package:meal_of_record/screens/navigation_container_screen.dart';
import 'package:meal_of_record/screens/log_queue_screen.dart';
import 'package:meal_of_record/screens/recipe_edit_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/services/open_food_facts_service.dart';
import 'package:meal_of_record/services/search_service.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/providers/search_provider.dart';
import 'package:meal_of_record/models/search_config.dart';
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/screens/container_settings_screen.dart';
import 'package:meal_of_record/screens/duplicate_merge_screen.dart';

class AppRouter {
  static const String homeRoute = '/';
  static const String searchRoute = '/food_search';
  static const String logQueueRoute = '/log_queue';
  static const String recipeEditRoute = '/recipe_edit';
  static const String dataManagementRoute = '/data_management';
  static const String qrSharingRoute = '/qr_sharing';
  static const String goalSettingsRoute = '/goal_settings';
  static const String containerSettingsRoute = '/container_settings';
  static const String qrPortionSharingRoute = '/qr_portion_sharing';
  static const String mealPortionRoute = '/meal_portion';
  static const String duplicateMergeRoute = '/duplicate_merge';

  final DatabaseService databaseService;
  final OffApiService offApiService;
  final SearchService searchService;

  AppRouter({
    required this.databaseService,
    required this.offApiService,
    required this.searchService,
  });

  Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case homeRoute:
        return MaterialPageRoute(
          builder: (_) => const NavigationContainerScreen(),
        );
      case searchRoute:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => SearchProvider(
              databaseService: databaseService,
              offApiService: offApiService,
              searchService: searchService,
            ),
            child: const SearchScreen(
              config: SearchConfig(
                context: QuantityEditContext.day,
                title: 'Food Search',
                showQueueStats: true,
              ),
            ),
          ),
        );
      case logQueueRoute:
        return MaterialPageRoute(builder: (_) => const LogQueueScreen());
      case recipeEditRoute:
        return MaterialPageRoute(builder: (_) => const RecipeEditScreen());
      case dataManagementRoute:
        return MaterialPageRoute(builder: (_) => const DataManagementScreen());
      case qrSharingRoute:
        final recipe = settings.arguments as Recipe?;
        return MaterialPageRoute(
          builder: (_) => QrSharingScreen(recipeToShare: recipe),
        );
      case goalSettingsRoute:
        return MaterialPageRoute(builder: (_) => const GoalSettingsScreen());
      case containerSettingsRoute:
        return MaterialPageRoute(
          builder: (_) => const ContainerSettingsScreen(),
        );
      case qrPortionSharingRoute:
        final portions = settings.arguments as List<FoodPortion>?;
        return MaterialPageRoute(
          builder: (_) => QrPortionSharingScreen(portions: portions),
        );
      case mealPortionRoute:
        final meal = settings.arguments as Meal;
        return MaterialPageRoute(builder: (_) => MealPortionScreen(meal: meal));
      case duplicateMergeRoute:
        return MaterialPageRoute(builder: (_) => const DuplicateMergeScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text(
                'No route defined for ${settings.name ?? ''}',
              ), // Handle null settings.name
            ),
          ),
        );
    }
  }
}
