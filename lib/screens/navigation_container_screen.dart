import 'package:flutter/material.dart';
import 'package:meal_of_record/config/app_router.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/screens/log_screen.dart';
import 'package:meal_of_record/screens/overview_screen.dart';
import 'package:meal_of_record/screens/settings_screen.dart';
import 'package:meal_of_record/screens/weight_screen.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:provider/provider.dart';

class NavigationContainerScreen extends StatelessWidget {
  const NavigationContainerScreen({super.key});

  static const List<Widget> _widgetOptions = <Widget>[
    OverviewScreen(),
    LogScreen(),
    WeightScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final navigationProvider = Provider.of<NavigationProvider>(context);
    final selectedIndex = navigationProvider.selectedIndex;
    final goalsProvider = Provider.of<GoalsProvider>(context);

    // Check for weekly target update notification or first-time setup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      if (!goalsProvider.isLoading) {
        if (!goalsProvider.hasSeenWelcome && !goalsProvider.isGoalsSet) {
          goalsProvider.markWelcomeSeen();
          _showWelcomeDialog(context);
        } else if (goalsProvider.showUpdateNotification) {
          _showUpdateDialog(context, goalsProvider);
        }
      }
    });

    return Scaffold(
      body: Center(
        child: (selectedIndex >= 0 && selectedIndex < _widgetOptions.length)
            ? _widgetOptions.elementAt(selectedIndex)
            : Container(),
      ),
      bottomNavigationBar: (selectedIndex != -1)
          ? BottomNavigationBar(
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Overview',
                ),
                BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Log'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.monitor_weight),
                  label: 'Weight',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
              currentIndex: selectedIndex,
              selectedItemColor: Colors.amber[800],
              unselectedItemColor: Colors.grey,
              onTap: (index) {
                if (index != 1 && selectedIndex == 1) {
                  // Navigating away from Log tab: Clear the queue and selection
                  final logProvider = Provider.of<LogProvider>(
                    context,
                    listen: false,
                  );
                  logProvider.clearQueue();
                  logProvider.clearSelection();
                }
                navigationProvider.changeTab(index);
              },
            )
          : null,
    );
  }

  void _showUpdateDialog(BuildContext context, GoalsProvider goalsProvider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Weekly Goal Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your weight targets have been updated for the new week.',
            ),
            const SizedBox(height: 10),
            Text(
              'New Calorie Target: ${goalsProvider.currentGoals.calories.toInt()} cal',
            ),
            Text('Protein: ${goalsProvider.currentGoals.protein.toInt()}g'),
            Text('Fat: ${goalsProvider.currentGoals.fat.toInt()}g'),
            Text(
              '${goalsProvider.useNetCarbs ? 'Net Carbs' : 'Carbs'}: ${goalsProvider.currentGoals.carbs.toInt()}g',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              goalsProvider.dismissNotification();
              Navigator.pop(context);
            },
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showWelcomeDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Welcome!'),
        content: const Text(
          'To get started, please set up your initial weight goals so we can tailor the app to you. Alternatively, you can restore from a backup if you have one.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
            },
            child: const Text('Stay on Overview'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushNamed(context, AppRouter.dataManagementRoute);
            },
            child: const Text('Restore from Backup'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushNamed(context, AppRouter.goalSettingsRoute);
            },
            child: const Text('Set up Goals'),
          ),
        ],
      ),
    );
  }
}
