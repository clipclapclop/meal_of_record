import 'dart:async';

import 'package:flutter/material.dart';

import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/screens/duplicate_merge_preview_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';

class DuplicateMergeManualTab extends StatefulWidget {
  final bool canMerge;
  const DuplicateMergeManualTab({super.key, required this.canMerge});

  @override
  State<DuplicateMergeManualTab> createState() =>
      _DuplicateMergeManualTabState();
}

class _DuplicateMergeManualTabState extends State<DuplicateMergeManualTab> {
  Food? _keeper;
  Food? _loser;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Keeper (the food to keep)',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        _FoodPicker(
          selected: _keeper,
          onPicked: (f) => setState(() => _keeper = f),
          exclude: _loser?.id,
        ),
        const SizedBox(height: 16),
        const Text(
          'Loser (the food to merge in and delete)',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        _FoodPicker(
          selected: _loser,
          onPicked: (f) => setState(() => _loser = f),
          exclude: _keeper?.id,
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.merge_type),
            label: const Text('Preview merge'),
            onPressed:
                widget.canMerge &&
                    _keeper != null &&
                    _loser != null &&
                    _keeper!.id != _loser!.id
                ? _openPreview
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> _openPreview() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            DuplicateMergePreviewScreen(keeper: _keeper!, losers: [_loser!]),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        _loser = null;
      });
    }
  }
}

class _FoodPicker extends StatefulWidget {
  final Food? selected;
  final ValueChanged<Food?> onPicked;
  final int? exclude;
  const _FoodPicker({
    required this.selected,
    required this.onPicked,
    this.exclude,
  });

  @override
  State<_FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<_FoodPicker> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Food> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final results = await DatabaseService.instance.searchLiveFoodsByName(
      q.trim(),
    );
    if (!mounted) return;
    setState(() {
      _results = results.where((f) => f.id != widget.exclude).toList();
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    if (selected != null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: SizedBox(
            width: 44,
            height: 44,
            child: FoodImageWidget(food: selected, size: 44),
          ),
          title: Text(selected.name),
          subtitle: Text(
            'id ${selected.id}  •  ${(selected.calories * 100).toStringAsFixed(1)} kcal/100g  •  '
            'P ${(selected.protein * 100).toStringAsFixed(1)}  '
            'F ${(selected.fat * 100).toStringAsFixed(1)}  '
            'C ${(selected.carbs * 100).toStringAsFixed(1)}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Change',
            onPressed: () {
              widget.onPicked(null);
              _controller.clear();
              setState(() => _results = []);
            },
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search live foods…',
            border: OutlineInputBorder(),
          ),
          onChanged: _onChanged,
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        if (_results.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: Column(
              children: _results
                  .take(20)
                  .map(
                    (f) => ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 36,
                        height: 36,
                        child: FoodImageWidget(food: f, size: 36),
                      ),
                      title: Text(f.name),
                      subtitle: Text(
                        'id ${f.id}  •  ${(f.calories * 100).toStringAsFixed(1)} kcal/100g',
                      ),
                      onTap: () => widget.onPicked(f),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
