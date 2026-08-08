import 'package:flutter/material.dart';
import 'package:meal_of_record/widgets/nutrition_targets_overview_chart.dart';
import 'package:meal_of_record/widgets/screen_background.dart';
import 'package:meal_of_record/widgets/search_ribbon.dart';
import 'package:meal_of_record/models/nutrition_target.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/providers/log_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/models/daily_macro_stats.dart';
import 'package:meal_of_record/models/macro_goals.dart';
import 'package:meal_of_record/providers/weight_provider.dart';
import 'package:meal_of_record/widgets/weight_trend_chart.dart';
import 'package:meal_of_record/models/weight.dart';
import 'package:meal_of_record/services/goal_logic_service.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  List<NutritionTarget> _nutritionData = [];
  List<DateTime> _nutritionDates = [];
  List<Weight> _weightHistory = [];
  List<double> _maintenanceHistory = [];
  List<double> _kalmanWeightHistory = [];
  bool _isLoading = true;
  DateTime _weightRangeStart = DateTime.now();
  DateTime _weightRangeEnd = DateTime.now();
  bool _needsReload = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool _isDataLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload data when providers change
    // This will be called whenever LogProvider or GoalsProvider notifies
    Provider.of<LogProvider>(context);
    Provider.of<GoalsProvider>(context);
    _loadData();
  }

  Future<void> _loadData() async {
    if (_isDataLoading) {
      _needsReload = true;
      return;
    }
    _isDataLoading = true;
    _needsReload = false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      today.year,
      today.month,
      today.day - 6,
    ); // Last 7 days

    try {
      final logProvider = Provider.of<LogProvider>(context, listen: false);
      final goalsProvider = Provider.of<GoalsProvider>(context, listen: false);
      final weightProvider = Provider.of<WeightProvider>(
        context,
        listen: false,
      );

      final stats = await logProvider.getDailyMacroStats(start, today);
      if (!mounted) return;

      final goals = goalsProvider.currentGoals;
      final navProvider = Provider.of<NavigationProvider>(
        context,
        listen: false,
      );
      final rangeStart = DateTime(
        today.year,
        today.month,
        today.day - navProvider.weightRangeDays,
      );
      final userWindow = goalsProvider.settings.tdeeWindowDays;
      final analysisStart = DateTime(
        rangeStart.year,
        rangeStart.month,
        rangeStart.day - userWindow,
      );

      final analysisStats = await logProvider.getDailyMacroStats(
        analysisStart,
        DateTime(today.year, today.month, today.day - 1),
      );
      await weightProvider.loadWeights(analysisStart, today);
      final analysisWeights = weightProvider.weights;

      // Build maps once for all per-day Kalman calls
      final weightMap = {
        for (var w in analysisWeights)
          DateTime(w.date.year, w.date.month, w.date.day): w.weight,
      };
      final statsMap = {
        for (var s in analysisStats)
          DateTime(s.date.year, s.date.month, s.date.day): s,
      };

      // Compute TDEE per displayed day using the shared function
      final List<double> displayMaintenance = [];
      final List<double> displayKalmanWeights = [];
      var day = rangeStart;
      while (!day.isAfter(today)) {
        final estimate = GoalLogicService.computeTdeeAtDate(
          tdeeWindow: userWindow,
          tdeeDate: day,
          weightMap: weightMap,
          statsMap: statsMap,
          initialTDEE: goalsProvider.settings.maintenanceCaloriesStart,
        );
        displayMaintenance.add(estimate?.tdee ?? 0.0);
        displayKalmanWeights.add(estimate?.weight ?? 0.0);
        day = DateTime(day.year, day.month, day.day + 1);
      }

      // Process stats into NutritionTargets
      if (mounted) {
        setState(() {
          _nutritionDates = stats.map((s) => s.date).toList();
          _nutritionData = _buildTargets(stats, goals, goalsProvider);
          _weightHistory = weightProvider.weights.where((w) {
            final d = DateTime(w.date.year, w.date.month, w.date.day);
            return !d.isBefore(rangeStart);
          }).toList();
          _maintenanceHistory = displayMaintenance;
          _kalmanWeightHistory = displayKalmanWeights;
          _weightRangeStart = rangeStart;
          _weightRangeEnd = today;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading overview data: $e');
    } finally {
      _isDataLoading = false;
      if (_needsReload && mounted) {
        _loadData();
      }
    }
  }

  Widget _buildGoalsWarning() {
    final goalsProvider = Provider.of<GoalsProvider>(context, listen: false);
    if (goalsProvider.isGoalsSet) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Goals not set. Nutrient targets and trends may not be accurate.',
              style: TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pushNamed(context, '/goal_settings');
            },
            child: const Text('Set up Goals'),
          ),
        ],
      ),
    );
  }

  List<NutritionTarget> _buildTargets(
    List<DailyMacroStats> stats,
    MacroGoals goals,
    GoalsProvider goalsProvider,
  ) {
    // Extract daily lists (ensure 7 days, index 0 is oldest, index 6 is today)
    // DailyMacroStats.fromDTOS usually returns sorted by date
    // We already requested 7 days, so we should map them directly mostly.

    // Helper to map a field across the stats list
    List<double> mapField(double Function(DailyMacroStats) selector) {
      return stats.map(selector).toList();
    }

    final useNetCarbs = goalsProvider.useNetCarbs;

    final calories = mapField((s) => s.calories);
    final protein = mapField((s) => s.protein);
    final fat = mapField((s) => s.fat);
    final carbs = mapField((s) => useNetCarbs ? s.netCarbs : s.carbs);
    final fiber = mapField((s) => s.fiber);

    // Build per-day target lists from snapshots
    final dailyCalorieTargets = stats
        .map((s) => goalsProvider.targetFor(s.date).calories)
        .toList();
    final dailyProteinTargets = stats
        .map((s) => goalsProvider.targetFor(s.date).protein)
        .toList();
    final dailyFatTargets = stats
        .map((s) => goalsProvider.targetFor(s.date).fat)
        .toList();
    final dailyCarbTargets = stats
        .map((s) => goalsProvider.targetFor(s.date).carbs)
        .toList();
    final dailyFiberTargets = stats
        .map((s) => goalsProvider.targetFor(s.date).fiber)
        .toList();

    // Get Today's values (last in the list)
    final todayStats = stats.last;

    return [
      NutritionTarget(
        color: Colors.blue,
        thisAmount: todayStats.calories,
        targetAmount: goals.calories,
        macroLabel: '🔥',
        unitLabel: '',
        dailyAmounts: calories,
        dailyTargets: dailyCalorieTargets,
      ),
      NutritionTarget(
        color: Colors.red,
        thisAmount: todayStats.protein,
        targetAmount: goals.protein,
        macroLabel: 'P',
        unitLabel: 'g',
        dailyAmounts: protein,
        dailyTargets: dailyProteinTargets,
      ),
      NutritionTarget(
        color: Colors.yellow,
        thisAmount: todayStats.fat,
        targetAmount: goals.fat,
        macroLabel: 'F',
        unitLabel: 'g',
        dailyAmounts: fat,
        dailyTargets: dailyFatTargets,
      ),
      NutritionTarget(
        color: Colors.green,
        thisAmount: useNetCarbs ? todayStats.netCarbs : todayStats.carbs,
        targetAmount: goals.carbs,
        macroLabel: 'C',
        unitLabel: 'g',
        dailyAmounts: carbs,
        dailyTargets: dailyCarbTargets,
      ),
      NutritionTarget(
        color: Colors.brown,
        thisAmount: todayStats.fiber,
        targetAmount: goals.fiber,
        macroLabel: 'Fb',
        unitLabel: 'g',
        dailyAmounts: fiber,
        dailyTargets: dailyFiberTargets,
      ),
    ];
  }

  Widget _buildRangeSelector() {
    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    final ranges = {
      '1 wk': 7,
      '1 mo': 30,
      '3 mo': 90,
      '6 mo': 180,
      '1 yr': 365,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ranges.entries.map((entry) {
        final isSelected = navProvider.weightRangeLabel == entry.key;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: TextButton(
            onPressed: () {
              navProvider.setWeightRange(entry.key, entry.value);
              setState(() {
                _isLoading = true;
              });
              _loadData();
            },
            style: TextButton.styleFrom(
              backgroundColor: isSelected ? Colors.white : Colors.transparent,
              foregroundColor: isSelected ? Colors.black : Colors.white,
              minimumSize: const Size(40, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(entry.key, style: const TextStyle(fontSize: 12)),
          ),
        );
      }).toList(),
    );
  }

  List<NutritionTarget> _buildLiveTodayTargets(
    LogProvider logProvider,
    bool useNetCarbs,
  ) {
    if (_nutritionData.length < 5) return _nutritionData;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lpDate = logProvider.currentDate;
    final lpIsToday = DateTime(lpDate.year, lpDate.month, lpDate.day) == today;
    if (!lpIsToday) return _nutritionData;
    final src = _nutritionData;
    return [
      NutritionTarget(
        color: src[0].color,
        thisAmount: logProvider.loggedCalories,
        targetAmount: src[0].targetAmount,
        macroLabel: src[0].macroLabel,
        unitLabel: src[0].unitLabel,
        dailyAmounts: src[0].dailyAmounts,
        dailyTargets: src[0].dailyTargets,
      ),
      NutritionTarget(
        color: src[1].color,
        thisAmount: logProvider.loggedProtein,
        targetAmount: src[1].targetAmount,
        macroLabel: src[1].macroLabel,
        unitLabel: src[1].unitLabel,
        dailyAmounts: src[1].dailyAmounts,
        dailyTargets: src[1].dailyTargets,
      ),
      NutritionTarget(
        color: src[2].color,
        thisAmount: logProvider.loggedFat,
        targetAmount: src[2].targetAmount,
        macroLabel: src[2].macroLabel,
        unitLabel: src[2].unitLabel,
        dailyAmounts: src[2].dailyAmounts,
        dailyTargets: src[2].dailyTargets,
      ),
      NutritionTarget(
        color: src[3].color,
        thisAmount: useNetCarbs
            ? logProvider.loggedNetCarbs
            : logProvider.loggedCarbs,
        targetAmount: src[3].targetAmount,
        macroLabel: src[3].macroLabel,
        unitLabel: src[3].unitLabel,
        dailyAmounts: src[3].dailyAmounts,
        dailyTargets: src[3].dailyTargets,
      ),
      NutritionTarget(
        color: src[4].color,
        thisAmount: logProvider.loggedFiber,
        targetAmount: src[4].targetAmount,
        macroLabel: src[4].macroLabel,
        unitLabel: src[4].unitLabel,
        dailyAmounts: src[4].dailyAmounts,
        dailyTargets: src[4].dailyTargets,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LogProvider>(
      builder: (context, logProvider, _) {
        final useNetCarbs = Provider.of<GoalsProvider>(
          context,
          listen: false,
        ).useNetCarbs;
        final liveNutritionData = _buildLiveTodayTargets(
          logProvider,
          useNetCarbs,
        );
        return ScreenBackground(
          appBar: AppBar(
            title: const Text('Overview'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          child: Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          _buildGoalsWarning(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 4.0,
                            ),
                            child: NutritionTargetsOverviewChart(
                              nutritionData: liveNutritionData,
                              dates: _nutritionDates,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 4.0,
                            ),
                            child: Column(
                              children: [
                                WeightTrendChart(
                                  weightHistory: _weightHistory,
                                  maintenanceHistory: _maintenanceHistory,
                                  kalmanWeightHistory: _kalmanWeightHistory,
                                  timeframeLabel:
                                      Provider.of<NavigationProvider>(
                                        context,
                                        listen: false,
                                      ).weightRangeLabel,
                                  startDate: _weightRangeStart,
                                  endDate: _weightRangeEnd,
                                  onTodayPlaceholderTapped: () {
                                    Provider.of<NavigationProvider>(
                                      context,
                                      listen: false,
                                    ).changeTab(2);
                                  },
                                ),
                                const SizedBox(height: 8),
                                _buildRangeSelector(),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              const SearchRibbon(),
            ],
          ),
        );
      },
    );
  }
}
