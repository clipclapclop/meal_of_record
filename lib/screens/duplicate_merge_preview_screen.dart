import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:meal_of_record/models/food.dart';
import 'package:meal_of_record/models/merge_result.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:meal_of_record/widgets/screen_background.dart';

class DuplicateMergePreviewScreen extends StatefulWidget {
  final Food keeper;
  final List<Food> losers;
  const DuplicateMergePreviewScreen({
    super.key,
    required this.keeper,
    required this.losers,
  });

  @override
  State<DuplicateMergePreviewScreen> createState() =>
      _DuplicateMergePreviewScreenState();
}

class _DuplicateMergePreviewScreenState
    extends State<DuplicateMergePreviewScreen> {
  Future<List<_LoserPreview>>? _previewFuture;

  bool _merging = false;
  List<_LoserOutcome>? _outcomes;
  Object? _fatalError;

  @override
  void initState() {
    super.initState();
    _previewFuture = _loadPreviews();
  }

  Future<List<_LoserPreview>> _loadPreviews() async {
    final List<_LoserPreview> out = [];
    for (final loser in widget.losers) {
      final predicted = await DatabaseService.instance.getMergePredictedCounts(
        loserId: loser.id,
      );
      final barcodes = await DatabaseService.instance.getBarcodesByFoodId(
        loser.id,
      );
      out.add(
        _LoserPreview(
          loser: loser,
          predicted: predicted,
          droppedBarcodes: barcodes,
        ),
      );
    }
    return out;
  }

  Future<void> _confirm(List<_LoserPreview> previews) async {
    setState(() => _merging = true);
    final List<_LoserOutcome> outcomes = [];
    for (final preview in previews) {
      try {
        final result = await DatabaseService.instance.mergeFoods(
          keeperId: widget.keeper.id,
          loserId: preview.loser.id,
        );
        outcomes.add(_LoserOutcome(preview: preview, result: result));
      } on MergeIntegrityException catch (e) {
        outcomes.add(_LoserOutcome(preview: preview, error: e));
      } catch (e) {
        outcomes.add(_LoserOutcome(preview: preview, error: e));
      }
    }
    if (!mounted) return;
    setState(() {
      _outcomes = outcomes;
      _merging = false;
      _fatalError = outcomes.any((o) => o.error != null)
          ? Exception('one or more merges failed')
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      appBar: AppBar(
        title: Text(_outcomes == null ? 'Merge preview' : 'Merge result'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      child: _outcomes != null ? _buildResultBody() : _buildPreviewBody(),
    );
  }

  Widget _buildPreviewBody() {
    return FutureBuilder<List<_LoserPreview>>(
      future: _previewFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final previews = snap.data ?? [];
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  _keeperCard(),
                  const SizedBox(height: 8),
                  ...previews.map(_buildPreviewCard),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _merging
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                        ),
                        onPressed: _merging ? null : () => _confirm(previews),
                        child: _merging
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Confirm merge'
                                '${previews.length > 1 ? ' (${previews.length})' : ''}',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _keeperCard() {
    return Card(
      color: Colors.green.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: FoodImageWidget(food: widget.keeper, size: 56),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'KEEPER',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.keeper.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'id ${widget.keeper.id}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(_LoserPreview p) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: FoodImageWidget(food: p.loser, size: 56),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LOSER',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.loser.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'id ${p.loser.id}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _macroComparison(p.loser),
            const Divider(height: 24),
            const Text(
              'Will be repointed to keeper',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            _countRow('Logged portions', p.predicted.loggedToRepoint),
            _countRow('Recipe items', p.predicted.recipeToRepoint),
            _countRow('Parent chain links', p.predicted.parentChainsToRepoint),
            const SizedBox(height: 12),
            const Text(
              'Will be discarded',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            _countRow('Portion definitions', p.predicted.portionsToDrop),
            if (p.loser.servings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: p.loser.servings
                      .map(
                        (s) => Text(
                          '• ${s.unit}: ${s.grams.toStringAsFixed(1)} g',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            _countRow('Barcodes', p.predicted.barcodesToDrop),
            if (p.droppedBarcodes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: p.droppedBarcodes
                      .map(
                        (b) => Text(
                          '• $b',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _macroComparison(Food loser) {
    final keeper = widget.keeper;
    Widget row(String label, double k, double l) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(label)),
            Expanded(
              child: Text(
                (k * 100).toStringAsFixed(2),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            const Text('vs', style: TextStyle(color: Colors.black45)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                (l * 100).toStringAsFixed(2),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: const [
            SizedBox(width: 80),
            Expanded(
              child: Text(
                'keeper /100g',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
            SizedBox(width: 32),
            Expanded(
              child: Text(
                'loser /100g',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ],
        ),
        row('kcal', keeper.calories, loser.calories),
        row('protein', keeper.protein, loser.protein),
        row('fat', keeper.fat, loser.fat),
        row('carbs', keeper.carbs, loser.carbs),
        row('fiber', keeper.fiber, loser.fiber),
      ],
    );
  }

  Widget _countRow(String label, int n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$n', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildResultBody() {
    final outcomes = _outcomes!;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Column(
      children: [
        if (_fatalError != null)
          Container(
            width: double.infinity,
            color: Colors.red.withValues(alpha: 0.15),
            padding: const EdgeInsets.all(12),
            child: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'One or more merges failed. The transaction rolled back. '
                    'If anything looks wrong, restore the session backup zip '
                    'via Data Management.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: outcomes.map((o) {
              if (o.error != null) {
                return Card(
                  color: Colors.red.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FAILED: ${o.preview.loser.name} (id ${o.preview.loser.id})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${o.error}'),
                      ],
                    ),
                  ),
                );
              }
              final r = o.result!;
              final p = o.preview.predicted;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Merged: ${o.preview.loser.name} (id ${o.preview.loser.id}) → keeper id ${r.keeperId}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _resultRow(
                        'Logs repointed',
                        p.loggedToRepoint,
                        r.loggedRepointed,
                      ),
                      _resultRow(
                        'Recipe items repointed',
                        p.recipeToRepoint,
                        r.recipeRepointed,
                      ),
                      _resultRow(
                        'Parent chains repointed',
                        p.parentChainsToRepoint,
                        r.parentChainsRepointed,
                      ),
                      _resultRow(
                        'Portions dropped',
                        p.portionsToDrop,
                        r.portionsDropped,
                      ),
                      _resultRow(
                        'Barcodes dropped',
                        p.barcodesToDrop,
                        r.barcodesDropped,
                      ),
                      if (r.sampleLoggedTimestamps.isNotEmpty) ...[
                        const Divider(height: 24),
                        const Text(
                          'Sample of repointed log entries',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        ...r.sampleLoggedTimestamps.map(
                          (ts) => Text(
                            '• ${fmt.format(DateTime.fromMillisecondsSinceEpoch(ts))}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultRow(String label, int predicted, int actual) {
    final ok = predicted == actual;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error,
            size: 16,
            color: ok ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            'predicted $predicted / actual $actual',
            style: TextStyle(
              color: ok ? Colors.black87 : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoserPreview {
  final Food loser;
  final MergePredictedCounts predicted;
  final List<String> droppedBarcodes;
  _LoserPreview({
    required this.loser,
    required this.predicted,
    required this.droppedBarcodes,
  });
}

class _LoserOutcome {
  final _LoserPreview preview;
  final MergeResult? result;
  final Object? error;
  _LoserOutcome({required this.preview, this.result, this.error});
}
