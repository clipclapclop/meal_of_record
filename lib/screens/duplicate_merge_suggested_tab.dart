import 'package:flutter/material.dart';

import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/screens/duplicate_merge_preview_screen.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';

class DuplicateMergeSuggestedTab extends StatefulWidget {
  final bool canMerge;
  const DuplicateMergeSuggestedTab({super.key, required this.canMerge});

  @override
  State<DuplicateMergeSuggestedTab> createState() =>
      _DuplicateMergeSuggestedTabState();
}

class _DuplicateMergeSuggestedTabState
    extends State<DuplicateMergeSuggestedTab> {
  static const List<double> _thresholds = [1, 2, 5, 10];
  double _threshold = 1;

  Future<_SuggestedData>? _dataFuture;
  Map<int, int> _logCounts = {};
  Map<int, int> _recipeCounts = {};
  Set<int> _withBarcodes = {};

  /// Keeper map keyed by composite group key (`v$index` for version chains,
  /// `m$index` for macro groups) so the two sections don't collide.
  final Map<String, int?> _keeperByGroup = {};

  /// Per-group set of food IDs the user has explicitly skipped (excluded from
  /// the merge). Skipped rows are neither keeper nor loser.
  final Map<String, Set<int>> _skippedByGroup = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _keeperByGroup.clear();
      _skippedByGroup.clear();
      _dataFuture = _load();
    });
  }

  Future<_SuggestedData> _load() async {
    final macroGroups = await DatabaseService.instance.findDuplicateFoodGroups(
      thresholdPct: _threshold,
    );
    final chainGroups = await DatabaseService.instance.findVersionChainGroups();

    final allIds = {
      for (final g in macroGroups) ...g.map((f) => f.id),
      for (final g in chainGroups) ...g.map((f) => f.id),
    }.toList();

    if (allIds.isNotEmpty) {
      final usage = await DatabaseService.instance.getFoodUsageStats(allIds);
      _logCounts = {for (final e in usage.entries) e.key: e.value.logCount};
      _recipeCounts = await DatabaseService.instance.getRecipeUsageCounts(
        allIds,
      );
      _withBarcodes = await DatabaseService.instance.getFoodIdsWithBarcodes(
        allIds,
      );
    } else {
      _logCounts = {};
      _recipeCounts = {};
      _withBarcodes = {};
    }

    int byNameThenSize(List<Food> a, List<Food> b) {
      final byCount = b.length.compareTo(a.length);
      if (byCount != 0) return byCount;
      return a.first.name.toLowerCase().compareTo(b.first.name.toLowerCase());
    }

    macroGroups.sort(byNameThenSize);
    chainGroups.sort(byNameThenSize);

    return _SuggestedData(macroGroups: macroGroups, chainGroups: chainGroups);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('Macros within:'),
              const SizedBox(width: 12),
              DropdownButton<double>(
                value: _threshold,
                items: _thresholds
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          '${v.toStringAsFixed(0)}%'
                          '${v == 1
                              ? ' (strict)'
                              : v == 10
                              ? ' (loose)'
                              : ''}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null || v == _threshold) return;
                  _threshold = v;
                  _reload();
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Re-scan',
                onPressed: _reload,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<_SuggestedData>(
            future: _dataFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final data = snap.data;
              final macroGroups = data?.macroGroups ?? [];
              final chainGroups = data?.chainGroups ?? [];
              if (macroGroups.isEmpty && chainGroups.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No duplicate groups or version chains found.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                children: [
                  if (chainGroups.isNotEmpty) ...[
                    _sectionHeader(
                      'Version chains (linked by parentId)',
                      '${chainGroups.length} chain${chainGroups.length == 1 ? '' : 's'}',
                    ),
                    for (int i = 0; i < chainGroups.length; i++)
                      _buildGroupCard(
                        'v$i',
                        chainGroups[i],
                        isVersionChain: true,
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (macroGroups.isNotEmpty) ...[
                    _sectionHeader(
                      'Macro matches (within ${_threshold.toStringAsFixed(0)}%)',
                      '${macroGroups.length} group${macroGroups.length == 1 ? '' : 's'}',
                    ),
                    for (int i = 0; i < macroGroups.length; i++)
                      _buildGroupCard(
                        'm$i',
                        macroGroups[i],
                        isVersionChain: false,
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(
    String groupKey,
    List<Food> group, {
    required bool isVersionChain,
  }) {
    final keeperId = _keeperByGroup[groupKey];
    final skipped = _skippedByGroup[groupKey] ?? const <int>{};
    final groupHash = group.map((f) => f.id).fold<int>(0, (a, b) => a ^ b);
    final stableKey = ValueKey('group_${groupKey}_$groupHash');

    final headerLabel = isVersionChain
        ? '${group.length}-row version chain'
        : '${group.length} foods within ${_threshold.toStringAsFixed(0)}%';

    final loserCount = group
        .where((f) => f.id != keeperId && !skipped.contains(f.id))
        .length;
    final canPreview = widget.canMerge && keeperId != null && loserCount >= 1;

    return Card(
      key: stableKey,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          headerLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          group.map((f) => f.name).toSet().join(' / '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        children: [
          RadioGroup<int>(
            groupValue: keeperId,
            onChanged: (v) {
              setState(() {
                _keeperByGroup[groupKey] = v;
                // Picking a row as keeper un-skips it.
                if (v != null) {
                  _skippedByGroup[groupKey]?.remove(v);
                }
              });
            },
            child: Column(
              children: group
                  .map(
                    (food) => _buildFoodRow(
                      food,
                      groupKey: groupKey,
                      isSkipped: skipped.contains(food.id),
                      isKeeper: food.id == keeperId,
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                Text(
                  keeperId == null
                      ? 'Pick a keeper to enable merge'
                      : loserCount == 0
                      ? 'Nothing to merge (all others skipped)'
                      : '$loserCount to merge in',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.merge_type),
                  label: const Text('Preview merge'),
                  onPressed: canPreview
                      ? () => _openPreview(groupKey, group, keeperId)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodRow(
    Food food, {
    required String groupKey,
    required bool isSkipped,
    required bool isKeeper,
  }) {
    final logs = _logCounts[food.id] ?? 0;
    final recipes = _recipeCounts[food.id] ?? 0;
    final hasBarcode = _withBarcodes.contains(food.id);

    void toggleSkip() {
      setState(() {
        final set = _skippedByGroup.putIfAbsent(groupKey, () => <int>{});
        if (set.contains(food.id)) {
          set.remove(food.id);
        } else {
          set.add(food.id);
          // Skipping the current keeper drops the keeper.
          if (_keeperByGroup[groupKey] == food.id) {
            _keeperByGroup[groupKey] = null;
          }
        }
      });
    }

    final row = RadioListTile<int>(
      value: food.id,
      secondary: SizedBox(
        width: 44,
        height: 44,
        child: FoodImageWidget(food: food, size: 44),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              food.name,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                decoration: isSkipped ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (hasBarcode)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.qr_code_2, size: 16, color: Colors.black54),
            ),
          if (food.hidden)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Hidden',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: isSkipped ? 'Include in merge' : 'Skip this row',
            icon: Icon(
              isSkipped ? Icons.block : Icons.block_outlined,
              size: 18,
              color: isSkipped ? Colors.red : Colors.black45,
            ),
            onPressed: toggleSkip,
          ),
        ],
      ),
      subtitle: Text(
        'id ${food.id}  •  ${(food.calories * 100).toStringAsFixed(1)} kcal/100g  •  '
        'P ${(food.protein * 100).toStringAsFixed(1)}  '
        'F ${(food.fat * 100).toStringAsFixed(1)}  '
        'C ${(food.carbs * 100).toStringAsFixed(1)}\n'
        '$logs logs  •  $recipes recipes'
        '${isSkipped
            ? '  •  skipped'
            : isKeeper
            ? '  •  KEEPER'
            : ''}',
      ),
      isThreeLine: true,
      enabled: !isSkipped,
    );

    if (!isSkipped) return row;
    return Opacity(opacity: 0.45, child: row);
  }

  Future<void> _openPreview(
    String groupKey,
    List<Food> group,
    int keeperId,
  ) async {
    final skipped = _skippedByGroup[groupKey] ?? const <int>{};
    final keeper = group.firstWhere((f) => f.id == keeperId);
    final losers = group
        .where((f) => f.id != keeperId && !skipped.contains(f.id))
        .toList();
    if (losers.isEmpty) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            DuplicateMergePreviewScreen(keeper: keeper, losers: losers),
      ),
    );
    if (result == true) {
      _reload();
    }
  }
}

class _SuggestedData {
  final List<List<Food>> macroGroups;
  final List<List<Food>> chainGroups;
  const _SuggestedData({required this.macroGroups, required this.chainGroups});
}
