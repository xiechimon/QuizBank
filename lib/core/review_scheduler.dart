class ReviewScheduler {
  static const intervals = [1, 2, 4, 7, 15];
  static const masteredPhase = 6;

  static bool isDue({required int phase, DateTime? next, required DateTime today}) {
    if (phase >= masteredPhase) return false;
    if (next == null) return false;
    return !next.isAfter(_startOfDay(today));
  }

  static ({int phase, DateTime? next}) transit({
    required int phase,
    required bool correct,
    required DateTime today,
  }) {
    final todayStart = _startOfDay(today);
    if (correct) {
      final newPhase = (phase + 1).clamp(0, masteredPhase);
      if (newPhase >= masteredPhase) return (phase: masteredPhase, next: null);
      final gap = intervals[newPhase - 1];
      return (phase: newPhase, next: todayStart.add(Duration(days: gap)));
    } else {
      return (phase: 0, next: todayStart.add(const Duration(days: 1)));
    }
  }

  static int? nextGapDays(int phase) {
    if (phase >= masteredPhase) return null;
    return intervals[(phase.clamp(1, intervals.length) - 1)];
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
}

extension CalX on DateTime {
  DateTime get startOfDay => DateTime(year, month, day);
}
