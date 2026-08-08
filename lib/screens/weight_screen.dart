import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:meal_of_record/providers/weight_provider.dart';
import 'package:meal_of_record/providers/goals_provider.dart';
import 'package:meal_of_record/providers/navigation_provider.dart';
import 'package:meal_of_record/widgets/screen_background.dart';
import 'package:meal_of_record/config/app_colors.dart';
import 'package:meal_of_record/utils/ui_utils.dart';

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  final _weightController = TextEditingController();
  final _focusNode = FocusNode();
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
    // Request focus for the text field after the first frame is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  void _loadData() {
    // WeightProvider loads its own data, but we can ensure it's up to date
    // for the current view. Since WeightProvider usually loads wide ranges,
    // we'll just ensure it's initialized.
    final weightProvider = Provider.of<WeightProvider>(context, listen: false);
    // Load last 30 days to start with
    final now = DateTime.now();
    weightProvider.loadWeights(
      now.subtract(const Duration(days: 30)),
      now.add(const Duration(days: 1)),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleDateChanged(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
      final weightRef = Provider.of<WeightProvider>(
        context,
        listen: false,
      ).getWeightForDate(newDate);
      if (weightRef != null) {
        _weightController.text = weightRef.weight.toString();
      } else {
        _weightController.clear();
      }
    });
  }

  void _submitWeight() {
    final weightValue = double.tryParse(_weightController.text);
    if (weightValue != null) {
      Provider.of<WeightProvider>(
        context,
        listen: false,
      ).saveWeight(weightValue, _selectedDate);
      UiUtils.showAutoDismissDialog(context, 'Weight saved');

      // Navigate back to Home
      Provider.of<NavigationProvider>(context, listen: false).changeTab(0);
    }
    // Don't clear if updating, or maybe do. User spec says "Overwrites".
    // I'll keep it there for visual confirmation but maybe clear on next day.
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) {
      return 'Today';
    } else if (checkDate == yesterday) {
      return 'Yesterday';
    } else if (checkDate == tomorrow) {
      return 'Tomorrow';
    } else {
      return DateFormat('MMMM d, yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Consumer2<WeightProvider, GoalsProvider>(
                builder: (context, weightProvider, goalsProvider, child) {
                  final weightEntry = weightProvider.getWeightForDate(
                    _selectedDate,
                  );
                  // Update controller if user navigated and we have data
                  if (weightEntry != null &&
                      _weightController.text.isEmpty &&
                      !_focusNode.hasFocus) {
                    _weightController.text = weightEntry.weight.toString();
                  }

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 150.0,
                          child: TextField(
                            controller: _weightController,
                            focusNode: _focusNode,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Weight',
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              border: const UnderlineInputBorder(),
                              suffixText: 'lbs',
                            ),
                            onSubmitted: (_) => _submitWeight(),
                            onTap: () {
                              _weightController.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: _weightController.text.length,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: ElevatedButton(
                          onPressed: _submitWeight,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                            textStyle: const TextStyle(fontSize: 18),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      color: AppColors.largeWidgetBackground,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () => _handleDateChanged(
              DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day - 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) _handleDateChanged(picked);
            },
            child: Text(
              _formatDate(_selectedDate),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: () => _handleDateChanged(
              DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day + 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
