import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/models/nutrition_target.dart';
import 'package:meal_of_record/widgets/log_header.dart';
import 'package:meal_of_record/widgets/screen_background.dart';
import 'package:meal_of_record/widgets/search_ribbon.dart';
import 'package:meal_of_record/widgets/confirm_delete_dialog.dart';
import 'package:meal_of_record/models/food_portion.dart';
import 'package:meal_of_record/models/logged_portion.dart';
import 'package:meal_of_record/models/meal.dart';
import 'package:meal_of_record/widgets/meal_widget.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:meal_of_record/main.dart' show routeObserver;

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> with RouteAware {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _initData();
  }

  Future<void> _initData() async {
    if (mounted) {
      // Load logs for the selected date
      final logProvider = Provider.of<LogProvider>(context, listen: false);
      await logProvider.loadLoggedPortionsForDate(_selectedDate);
    }
  }

  void _handleDateChanged(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
    });
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    logProvider.clearSelection();
    logProvider.loadLoggedPortionsForDate(newDate);
  }

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);
    final goalsProvider = Provider.of<GoalsProvider>(context);
    final goals = goalsProvider.currentGoals;
    final useNetCarbs = goalsProvider.useNetCarbs;

    final List<NutritionTarget> nutritionTargets = [
      NutritionTarget(
        color: Colors.blue,
        thisAmount: logProvider.loggedCalories,
        targetAmount: goals.calories,
        macroLabel: '🔥',
        unitLabel: '',
        dailyAmounts: [],
      ),
      NutritionTarget(
        color: Colors.red,
        thisAmount: logProvider.loggedProtein,
        targetAmount: goals.protein,
        macroLabel: 'P',
        unitLabel: 'g',
        dailyAmounts: [],
      ),
      NutritionTarget(
        color: Colors.orange,
        thisAmount: logProvider.loggedFat,
        targetAmount: goals.fat,
        macroLabel: 'F',
        unitLabel: 'g',
        dailyAmounts: [],
      ),
      NutritionTarget(
        color: Colors.green,
        thisAmount: useNetCarbs
            ? logProvider.loggedNetCarbs
            : logProvider.loggedCarbs,
        targetAmount: goals.carbs,
        macroLabel: 'C',
        unitLabel: 'g',
        dailyAmounts: [],
      ),
      NutritionTarget(
        color: Colors.brown,
        thisAmount: logProvider.loggedFiber,
        targetAmount: goals.fiber,
        macroLabel: 'Fb',
        unitLabel: 'g',
        dailyAmounts: [],
      ),
    ];

    return ScreenBackground(
      child: Column(
        children: [
          LogHeader(
            date: _selectedDate,
            onDateChanged: _handleDateChanged,
            nutritionTargets: nutritionTargets,
          ),
          Consumer<LogProvider>(
            builder: (context, logProvider, child) {
              // Show context-sensitive buttons when portions are selected
              if (logProvider.hasSelectedPortions) {
                return _buildMultiselectActions(context, logProvider);
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: Consumer<LogProvider>(
              builder: (context, logProvider, child) {
                final meals = _groupLogsIntoMeals(logProvider.loggedPortion);

                if (meals.isEmpty) {
                  return const Center(child: Text('No logs for this day'));
                }

                return GestureDetector(
                  onTap: () {
                    // Clear selection when tapping outside portions
                    if (logProvider.hasSelectedPortions) {
                      logProvider.clearSelection();
                    }
                  },
                  child: ListView.builder(
                    itemCount: meals.length,
                    itemBuilder: (context, index) {
                      return MealWidget(
                        meal: meals[index],
                        onFoodUpdated: _updateLoggedFood,
                        onFoodDeleted: _deleteLoggedFood,
                        onBackgroundTap: () {
                          // Clear selection when tapping on meal background
                          if (logProvider.hasSelectedPortions) {
                            logProvider.clearSelection();
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const SearchRibbon(),
        ],
      ),
    );
  }

  List<Meal> _groupLogsIntoMeals(List<LoggedPortion> loggedPortions) {
    if (loggedPortions.isEmpty) return [];

    // Sort by timestamp
    final sortedPortions = List<LoggedPortion>.from(loggedPortions)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final meals = <Meal>[];

    if (loggedPortions.isEmpty) return [];

    var currentMealLogs = <LoggedPortion>[sortedPortions.first];
    for (var i = 1; i < sortedPortions.length; i++) {
      final current = sortedPortions[i];
      final previous = sortedPortions[i - 1];

      // Group essentially by exact timestamp (strict grouping)
      // Since queue items are logged with the same timestamp, they will group.
      // Separate logs (even 1 minute apart) will split.
      if (!current.timestamp.isAtSameMomentAs(previous.timestamp)) {
        // Start new meal
        meals.add(
          Meal(
            timestamp: currentMealLogs.first.timestamp,
            loggedPortion: List.from(currentMealLogs),
          ),
        );
        currentMealLogs = [current];
      } else {
        currentMealLogs.add(current);
      }
    }

    // Add the last meal
    meals.add(
      Meal(
        timestamp: currentMealLogs.first.timestamp,
        loggedPortion: List.from(currentMealLogs),
      ),
    );

    return meals;
  }

  void _updateLoggedFood(LoggedPortion oldFood, FoodPortion newPortion) {
    Provider.of<LogProvider>(
      context,
      listen: false,
    ).updateLoggedPortion(oldFood, newPortion);
  }

  void _deleteLoggedFood(LoggedPortion food) {
    Provider.of<LogProvider>(context, listen: false).deleteLoggedPortion(food);
  }

  Future<void> _showMoveDialog(
    BuildContext context,
    LogProvider logProvider,
  ) async {
    final result = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _DateTimePickerDialog(initialDateTime: DateTime.now());
      },
    );

    if (result == null || !mounted) {
      // User cancelled the dialog or widget was disposed
      return;
    }

    // Move the selected portions to the new date and time
    await logProvider.moveSelectedPortions(result);

    // Navigate to the selected date
    if (mounted) {
      _handleDateChanged(result);
    }
  }

  Widget _buildMultiselectActions(
    BuildContext context,
    LogProvider logProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                // Copy selected portions to log queue and navigate to Log Queue Screen
                logProvider.copySelectedPortionsToQueue();
                Navigator.pushNamed(context, AppRouter.logQueueRoute);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showMoveDialog(context, logProvider),
              icon: const Icon(Icons.move_down),
              label: const Text('Move'),
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                // Show confirmation dialog
                final confirmed = await showConfirmDeleteDialog(
                  context,
                  count: logProvider.selectedPortionCount,
                );

                if (confirmed == true && mounted) {
                  // Delete the selected portions
                  await logProvider.deleteSelectedPortions();

                  // User stays on the current date (no navigation)
                  // Selection is automatically cleared by deleteSelectedPortions()
                }
              },
              icon: const Icon(Icons.delete),
              label: const Text('Delete'),
              style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dialog that combines date and time pickers in a single popup
class _DateTimePickerDialog extends StatefulWidget {
  final DateTime initialDateTime;

  const _DateTimePickerDialog({required this.initialDateTime});

  @override
  State<_DateTimePickerDialog> createState() => _DateTimePickerDialogState();
}

class _DateTimePickerDialogState extends State<_DateTimePickerDialog> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDateTime;
    _selectedTime = TimeOfDay.fromDateTime(widget.initialDateTime);
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Move to Date & Time'),
      content: SizedBox(
        width: 300,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Date picker
            Expanded(
              flex: 2,
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                onDateChanged: (DateTime newDate) {
                  setState(() {
                    _selectedDate = newDate;
                  });
                },
              ),
            ),
            const Divider(height: 1),
            // Time picker button
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: InkWell(
                onTap: _selectTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time),
                      const SizedBox(width: 8.0),
                      Text(
                        _selectedTime.format(context),
                        style: const TextStyle(fontSize: 18.0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final result = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _selectedTime.hour,
              _selectedTime.minute,
            );
            Navigator.of(context).pop(result);
          },
          child: const Text('Move'),
        ),
      ],
    );
  }
}
