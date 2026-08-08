import 'package:flutter/material.dart';
import 'package:meal_of_record/config/app_colors.dart';
import 'package:meal_of_record/models/weight.dart';
import 'package:meal_of_record/services/goal_logic_service.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'dart:math';

/// Returns the index into [realData] of the nearest real data point
/// to [tapPosition] within [threshold] pixels, or null if none.
int? findNearestRealPoint({
  required Offset tapPosition,
  required Size chartSize,
  required List<Weight> realData,
  required List<double> trends,
  required DateTime startDate,
  required DateTime endDate,
  double threshold = 24.0,
}) {
  if (realData.isEmpty) return null;

  final weights = realData.map((e) => e.weight).toList();
  final allValues = [...weights, ...trends];
  final minWeight = allValues.reduce((a, b) => a < b ? a : b) - 0.5;
  final maxWeight = allValues.reduce((a, b) => a > b ? a : b) + 0.5;
  final weightRange = maxWeight - minWeight;

  const double leftPadding = 40.0;
  const double rightPadding = 40.0;
  final drawAreaWidth = chartSize.width - leftPadding - rightPadding;
  final totalDuration = endDate.difference(startDate).inSeconds;

  double getX(DateTime date) {
    if (totalDuration == 0) return leftPadding;
    final elapsed = date.difference(startDate).inSeconds;
    return leftPadding + (elapsed / totalDuration) * drawAreaWidth;
  }

  double getYWeight(double weight) {
    final normalized = (weight - minWeight) / weightRange;
    return chartSize.height - (normalized * chartSize.height);
  }

  int? nearestIndex;
  double nearestDist = double.infinity;

  for (var i = 0; i < realData.length; i++) {
    final dx = getX(realData[i].date) - tapPosition.dx;
    final dy = getYWeight(realData[i].weight) - tapPosition.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < nearestDist) {
      nearestDist = dist;
      nearestIndex = i;
    }
  }

  if (nearestDist <= threshold) return nearestIndex;
  return null;
}

/// Returns the pixel position of a point on the chart given its date and weight.
Offset _getPointPosition({
  required DateTime date,
  required double weight,
  required Size chartSize,
  required List<Weight> realData,
  required List<double> trends,
  required DateTime startDate,
  required DateTime endDate,
}) {
  final weights = realData.map((e) => e.weight).toList();
  final allValues = [...weights, ...trends];
  final minWeight = allValues.reduce((a, b) => a < b ? a : b) - 0.5;
  final maxWeight = allValues.reduce((a, b) => a > b ? a : b) + 0.5;
  final weightRange = maxWeight - minWeight;

  const double leftPadding = 40.0;
  const double rightPadding = 40.0;
  final drawAreaWidth = chartSize.width - leftPadding - rightPadding;
  final totalDuration = endDate.difference(startDate).inSeconds;

  final elapsed = date.difference(startDate).inSeconds;
  final x = totalDuration == 0
      ? leftPadding
      : leftPadding + (elapsed / totalDuration) * drawAreaWidth;

  final normalized = (weight - minWeight) / weightRange;
  final y = chartSize.height - (normalized * chartSize.height);

  return Offset(x, y);
}

class WeightTrendChart extends StatefulWidget {
  final List<Weight> weightHistory;
  final List<double> maintenanceHistory;
  final List<double> kalmanWeightHistory;
  final String timeframeLabel;
  final DateTime startDate;
  final DateTime endDate;
  final VoidCallback? onTodayPlaceholderTapped;

  const WeightTrendChart({
    super.key,
    required this.weightHistory,
    required this.maintenanceHistory,
    required this.kalmanWeightHistory,
    required this.timeframeLabel,
    required this.startDate,
    required this.endDate,
    this.onTodayPlaceholderTapped,
  });

  @override
  State<WeightTrendChart> createState() => _WeightTrendChartState();
}

class _WeightTrendChartState extends State<WeightTrendChart> {
  int? _selectedRealIndex;

  @override
  void didUpdateWidget(WeightTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate ||
        oldWidget.endDate != widget.endDate) {
      _selectedRealIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.weightHistory.isEmpty) {
      return Container(
        height: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.largeWidgetBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'No weight data for the last 30 days',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    // 1. Calculate min weight for placeholders
    final realWeights = widget.weightHistory.map((e) => e.weight).toList();
    final minRealWeight = realWeights.reduce((a, b) => a < b ? a : b);

    // 2. Map existing weights by date (date only)
    final weightMap = <DateTime, double>{};
    for (final w in widget.weightHistory) {
      final dateOnly = DateTime(w.date.year, w.date.month, w.date.day);
      weightMap[dateOnly] = w.weight;
    }

    // 3. Generate points for every day in the range
    final points = <_ChartPoint>[];
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    var current = DateTime(
      widget.startDate.year,
      widget.startDate.month,
      widget.startDate.day,
    );
    final end = DateTime(
      widget.endDate.year,
      widget.endDate.month,
      widget.endDate.day,
    );

    while (!current.isAfter(end)) {
      final realWeight = weightMap[current];
      final isPlaceholder = realWeight == null;

      points.add(
        _ChartPoint(
          date: current,
          weight: realWeight ?? minRealWeight,
          isPlaceholder: isPlaceholder,
          isToday: current.isAtSameMomentAs(todayDate),
        ),
      );
      current = DateTime(current.year, current.month, current.day + 1);
    }

    // Sort real data for display
    final sortedReal = List<Weight>.from(widget.weightHistory)
      ..sort((a, b) => a.date.compareTo(b.date));

    // Use Kalman weight history for trend line (falls back to EMA if empty)
    final List<double> trends;
    if (widget.kalmanWeightHistory.isNotEmpty) {
      // kalmanWeightHistory maps 1:1 to daily points between startDate and endDate.
      // Build a date->weight map, then look up each real data point's date.
      final kalmanByDate = <DateTime, double>{};
      var kDate = DateTime(
        widget.startDate.year,
        widget.startDate.month,
        widget.startDate.day,
      );
      for (var i = 0; i < widget.kalmanWeightHistory.length; i++) {
        if (widget.kalmanWeightHistory[i] != 0.0) {
          kalmanByDate[kDate] = widget.kalmanWeightHistory[i];
        }
        kDate = DateTime(kDate.year, kDate.month, kDate.day + 1);
      }
      // For each real weight point, find the nearest Kalman estimate
      trends = sortedReal.map((w) {
        final dateOnly = DateTime(w.date.year, w.date.month, w.date.day);
        return kalmanByDate[dateOnly] ?? w.weight;
      }).toList();
    } else {
      trends = GoalLogicService.calculateTrendHistory(sortedReal);
    }

    return Container(
      height: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.largeWidgetBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weight Trend (${widget.timeframeLabel})',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chartSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                // Find today's placeholder point (if any) for tap detection
                final todayPlaceholder = points.cast<_ChartPoint?>().firstWhere(
                  (p) => p!.isToday && p.isPlaceholder,
                  orElse: () => null,
                );

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    // Check if tap is on today's placeholder red dot
                    if (todayPlaceholder != null &&
                        widget.onTodayPlaceholderTapped != null) {
                      final tapPos = details.localPosition;
                      final placeholderPos = _getPointPosition(
                        date: todayPlaceholder.date,
                        weight: todayPlaceholder.weight,
                        chartSize: chartSize,
                        realData: sortedReal,
                        trends: trends,
                        startDate: widget.startDate,
                        endDate: widget.endDate,
                      );
                      final dx = tapPos.dx - placeholderPos.dx;
                      final dy = tapPos.dy - placeholderPos.dy;
                      if (sqrt(dx * dx + dy * dy) <= 24.0) {
                        widget.onTodayPlaceholderTapped!();
                        return;
                      }
                    }

                    final tapped = findNearestRealPoint(
                      tapPosition: details.localPosition,
                      chartSize: chartSize,
                      realData: sortedReal,
                      trends: trends,
                      startDate: widget.startDate,
                      endDate: widget.endDate,
                    );
                    setState(() {
                      _selectedRealIndex = (tapped == _selectedRealIndex)
                          ? null
                          : tapped;
                    });
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _WeightLinePainter(
                      points: points,
                      realData: sortedReal,
                      trends: trends,
                      maintenanceHistory: widget.maintenanceHistory,
                      startDate: widget.startDate,
                      endDate: widget.endDate,
                      selectedRealIndex: _selectedRealIndex,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMM d').format(widget.startDate),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              Text(
                DateFormat('MMM d').format(widget.endDate),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartPoint {
  final DateTime date;
  final double weight;
  final bool isPlaceholder;
  final bool isToday;

  _ChartPoint({
    required this.date,
    required this.weight,
    required this.isPlaceholder,
    this.isToday = false,
  });
}

class _WeightLinePainter extends CustomPainter {
  final List<_ChartPoint> points;
  final List<Weight> realData;
  final List<double> trends;
  final List<double> maintenanceHistory;
  final DateTime startDate;
  final DateTime endDate;
  final int? selectedRealIndex;

  _WeightLinePainter({
    required this.points,
    required this.realData,
    required this.trends,
    required this.maintenanceHistory,
    required this.startDate,
    required this.endDate,
    this.selectedRealIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || realData.isEmpty) return;

    final weights = realData.map((e) => e.weight).toList();
    final allValues = [...weights, ...trends];
    final minWeight = allValues.reduce((a, b) => a < b ? a : b) - 0.5;
    final maxWeight = allValues.reduce((a, b) => a > b ? a : b) + 0.5;
    final weightRange = maxWeight - minWeight;

    // Calorie range (for left axis)
    final double minMain = maintenanceHistory.isNotEmpty
        ? maintenanceHistory.reduce((a, b) => a < b ? a : b)
        : 1500;
    final double maxMain = maintenanceHistory.isNotEmpty
        ? maintenanceHistory.reduce((a, b) => a > b ? a : b)
        : 2500;
    final double mainRange = (maxMain - minMain).clamp(100, double.infinity);
    final double mainAxisMin = minMain - (mainRange * 0.1);
    final double mainAxisMax = maxMain + (mainRange * 0.1);
    final double mainAxisRange = mainAxisMax - mainAxisMin;

    // Drawing area padding for labels
    const double rightPadding = 40.0;
    const double leftPadding = 40.0;
    final drawAreaWidth = size.width - rightPadding - leftPadding;

    final totalDuration = endDate.difference(startDate).inSeconds;

    double getX(DateTime date) {
      if (totalDuration == 0) return leftPadding;
      final elapsed = date.difference(startDate).inSeconds;
      return leftPadding + (elapsed / totalDuration) * drawAreaWidth;
    }

    double getYWeight(double weight) {
      final normalized = (weight - minWeight) / weightRange;
      return size.height - (normalized * size.height);
    }

    double getYMain(double cal) {
      final normalized = (cal - mainAxisMin) / mainAxisRange;
      return size.height - (normalized * size.height);
    }

    // 1. Paint Y-Axis Labels & Grid Lines
    final labelPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    void drawYLabelRight(double weight) {
      final y = getYWeight(weight);
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(leftPadding + drawAreaWidth, y),
        gridPaint,
      );

      labelPainter.text = TextSpan(
        text: weight.toStringAsFixed(1),
        style: const TextStyle(color: Colors.white38, fontSize: 9),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(leftPadding + drawAreaWidth + 5, y - 6),
      );
    }

    void drawYLabelLeft(double cal) {
      final y = getYMain(cal);
      // No extra grid line for left side to avoid clutter

      labelPainter.text = TextSpan(
        text: cal.toInt().toString(),
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 9),
      );
      labelPainter.layout();
      labelPainter.paint(canvas, Offset(5, y - 6));
    }

    // Weight Labels (Right)
    drawYLabelRight(minWeight + 0.5);
    drawYLabelRight(maxWeight - 0.5);
    drawYLabelRight((minWeight + maxWeight) / 2);

    // Calorie Labels (Left)
    if (maintenanceHistory.isNotEmpty) {
      drawYLabelLeft(mainAxisMin + (mainAxisRange * 0.1));
      drawYLabelLeft(mainAxisMax - (mainAxisRange * 0.1));
      drawYLabelLeft((mainAxisMin + mainAxisMax) / 2);
    }

    // 2. Paint trend line (EMA)
    final trendPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final trendPath = Path();
    trendPath.moveTo(getX(realData[0].date), getYWeight(trends[0]));

    for (var i = 1; i < trends.length; i++) {
      trendPath.lineTo(getX(realData[i].date), getYWeight(trends[i]));
    }
    canvas.drawPath(trendPath, trendPaint);

    // 2.5 Paint Maintenance Calories (Kalman)
    if (maintenanceHistory.isNotEmpty) {
      final mainPaint = Paint()
        ..color = Colors.orangeAccent.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final mainPath = Path();
      // maintenanceHistory maps 1:1 to daily points between startDate and endDate
      var current = DateTime(startDate.year, startDate.month, startDate.day);
      bool firstValid = true;

      for (var i = 0; i < maintenanceHistory.length; i++) {
        if (i > 0) {
          current = DateTime(current.year, current.month, current.day + 1);
        }
        if (maintenanceHistory[i] == 0.0) continue;
        if (firstValid) {
          mainPath.moveTo(getX(current), getYMain(maintenanceHistory[i]));
          firstValid = false;
        } else {
          mainPath.lineTo(getX(current), getYMain(maintenanceHistory[i]));
        }
      }

      // Draw dashed line
      _drawDashedPath(canvas, mainPath, mainPaint);
    }

    // 3. Paint Connected Weight Line Segments (Real Data Only)
    final linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final weightPath = Path();
    bool firstPoint = true;

    for (var i = 0; i < points.length; i++) {
      if (!points[i].isPlaceholder) {
        if (firstPoint) {
          weightPath.moveTo(getX(points[i].date), getYWeight(points[i].weight));
          firstPoint = false;
        } else {
          weightPath.lineTo(getX(points[i].date), getYWeight(points[i].weight));
        }
      }
    }
    canvas.drawPath(weightPath, linePaint);

    // 4. Paint Raw Weight Points (Dots)
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (point.isPlaceholder) {
        // Muted color for old placeholders, red for today
        dotPaint.color = point.isToday
            ? Colors.red.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.2);
        canvas.drawCircle(
          Offset(getX(point.date), getYWeight(point.weight)),
          point.isToday ? 4 : 2,
          dotPaint,
        );
      } else {
        // Real data point
        dotPaint.color = Colors.white;
        canvas.drawCircle(
          Offset(getX(point.date), getYWeight(point.weight)),
          3,
          dotPaint,
        );
      }
    }

    // 5. Paint selected weight label
    if (selectedRealIndex != null && selectedRealIndex! < realData.length) {
      final selected = realData[selectedRealIndex!];
      final x = getX(selected.date);
      final y = getYWeight(selected.weight);

      // Highlight selected dot
      dotPaint.color = Colors.white;
      canvas.drawCircle(Offset(x, y), 5, dotPaint);

      final labelText =
          '${DateFormat('MMM d').format(selected.date)}: ${selected.weight.toStringAsFixed(1)}';

      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();

      const verticalOffset = 16.0;
      const padding = 4.0;

      // Position above dot; flip below if near top
      double labelY = y - verticalOffset - tp.height;
      if (labelY < 0) {
        labelY = y + verticalOffset;
      }

      // Center horizontally, clamped to chart bounds
      double labelX = (x - tp.width / 2).clamp(
        leftPadding,
        leftPadding + drawAreaWidth - tp.width,
      );

      // Background pill
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            labelX - padding,
            labelY - padding,
            tp.width + padding * 2,
            tp.height + padding * 2,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.7),
      );

      tp.paint(canvas, Offset(labelX, labelY));
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const double dashWidth = 5.0;
    const double dashSpace = 3.0;

    final ui.PathMetrics pathMetrics = path.computeMetrics();
    for (ui.PathMetric pathMetric in pathMetrics) {
      double distance = 0.0;
      while (distance < pathMetric.length) {
        final ui.Path extractPath = pathMetric.extractPath(
          distance,
          distance + dashWidth,
        );
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
