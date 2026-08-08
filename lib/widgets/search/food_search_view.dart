import 'package:flutter/material.dart';
import 'package:meal_of_record/models/food_portion.dart' as model_portion;
import 'package:meal_of_record/models/quantity_edit_config.dart';
import 'package:meal_of_record/models/search_config.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/screens/food_edit_screen.dart';
import 'package:meal_of_record/screens/quantity_edit_screen.dart';
import 'package:meal_of_record/screens/qr_portion_sharing_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/quick_add_dialog.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:provider/provider.dart';

class FoodSearchView extends StatelessWidget {
  final SearchConfig config;
  const FoodSearchView({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildQuickAddButton(context),
          const SizedBox(height: 8),
          _buildCreateFoodButton(context),
          if (config.onSaveOverride == null) ...[
            const SizedBox(height: 8),
            _buildScanPortionsButton(context),
          ],
          const SizedBox(height: 8),
          _buildFastedDayButton(context),
        ],
      ),
    );
  }

  Widget _buildQuickAddButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.flash_on, size: 32),
        label: const Text('Quick Add', style: TextStyle(fontSize: 18)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: () async {
          final portion = await Navigator.push<model_portion.FoodPortion>(
            context,
            MaterialPageRoute(builder: (context) => const QuickAddScreen()),
          );

          if (portion != null && context.mounted) {
            if (config.onSaveOverride != null) {
              config.onSaveOverride!(portion);
            } else {
              Provider.of<LogProvider>(
                context,
                listen: false,
              ).addFoodToQueue(portion);
            }
          }
        },
      ),
    );
  }

  Widget _buildCreateFoodButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.add_circle_outline, size: 32),
        label: const Text('Create New Food', style: TextStyle(fontSize: 18)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: () async {
          final result = await Navigator.push<FoodEditResult>(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  const FoodEditScreen(contextType: FoodEditContext.search),
            ),
          );

          if (result != null && result.useImmediately && context.mounted) {
            // If user chose "Save & Use", navigate to quantity edit
            final food = await DatabaseService.instance.getFoodById(
              result.foodId,
              'live',
            );
            if (!context.mounted) return;

            if (food != null) {
              // Open quantity edit screen
              final result = await Navigator.push<model_portion.FoodPortion>(
                context,
                MaterialPageRoute(
                  builder: (_) => QuantityEditScreen(
                    config: QuantityEditConfig(
                      context: config.context,
                      food: food,
                      isUpdate: false,
                      initialUnit: food.servings.first.unit,
                      initialQuantity: 1.0,
                      originalGrams: 0.0,
                    ),
                  ),
                ),
              );
              if (result != null && context.mounted) {
                if (config.onSaveOverride != null) {
                  config.onSaveOverride!(result);
                } else {
                  Provider.of<LogProvider>(
                    context,
                    listen: false,
                  ).addFoodToQueue(result);
                }
              }
            }
          }
        },
      ),
    );
  }

  Widget _buildScanPortionsButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.qr_code_scanner, size: 32),
        label: const Text('Scan Portions', style: TextStyle(fontSize: 18)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QrPortionSharingScreen()),
          );
        },
      ),
    );
  }

  Widget _buildFastedDayButton(BuildContext context) {
    return Consumer<LogProvider>(
      builder: (context, logProvider, child) {
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.no_meals, size: 32),
            label: const Text('Fasted Day', style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: () async {
              await logProvider.logFasted(logProvider.currentDate);
              if (context.mounted) {
                context.read<NavigationProvider>().changeTab(0);
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
          ),
        );
      },
    );
  }
}
