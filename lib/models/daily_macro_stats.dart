class LoggedMacroDTO {
  final DateTime logTimestamp;
  final double grams;
  final double caloriesPerGram;
  final double proteinPerGram;
  final double fatPerGram;
  final double carbsPerGram;
  final double fiberPerGram;

  LoggedMacroDTO({
    required this.logTimestamp,
    required this.grams,
    required this.caloriesPerGram,
    required this.proteinPerGram,
    required this.fatPerGram,
    required this.carbsPerGram,
    required this.fiberPerGram,
  });
}

class DailyMacroStats {
  final DateTime date;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double fiber;
  final int logCount;

  DailyMacroStats({
    required this.date,
    this.calories = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
    this.fiber = 0,
    this.logCount = 0,
  });

  static List<DailyMacroStats> fromDTOS(
    List<LoggedMacroDTO> dtos,
    DateTime start,
    DateTime end,
  ) {
    // 1. Initialize map with all dates in range to ensure empty days are represented
    final Map<int, DailyMacroStats> statsByDay = {};
    // Use UTC to compute day count — avoids DST causing inDays to be one short
    final startUtc = DateTime.utc(start.year, start.month, start.day);
    final endUtc = DateTime.utc(end.year, end.month, end.day);
    final dayCount = endUtc.difference(startUtc).inDays;
    for (int i = 0; i <= dayCount; i++) {
      final date = DateTime(start.year, start.month, start.day + i);
      // Key by start of day milliseconds for easy lookup
      final dateKey = DateTime(
        date.year,
        date.month,
        date.day,
      ).millisecondsSinceEpoch;
      statsByDay[dateKey] = DailyMacroStats(date: date);
    }

    // 2. Aggregate logs
    for (final dto in dtos) {
      final logDate = DateTime.fromMillisecondsSinceEpoch(
        dto.logTimestamp.millisecondsSinceEpoch,
      );
      final keyDate = DateTime(logDate.year, logDate.month, logDate.day);
      final key = keyDate.millisecondsSinceEpoch;

      if (statsByDay.containsKey(key)) {
        final current = statsByDay[key]!;
        statsByDay[key] = DailyMacroStats(
          date: current.date,
          calories: current.calories + (dto.caloriesPerGram * dto.grams),
          protein: current.protein + (dto.proteinPerGram * dto.grams),
          fat: current.fat + (dto.fatPerGram * dto.grams),
          carbs: current.carbs + (dto.carbsPerGram * dto.grams),
          fiber: current.fiber + (dto.fiberPerGram * dto.grams),
          logCount: current.logCount + 1,
        );
      }
    }

    return statsByDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  double get netCarbs => (carbs - fiber).clamp(0.0, double.infinity);
}
