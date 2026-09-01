import '../data/models.dart';
import 'topic_overview.dart';

class TypeStat {
  final QuestionType type;
  final int total;
  final int correct;
  TypeStat({required this.type, required this.total, required this.correct});
  double get accuracy => total > 0 ? correct / total : 0;
}

class MasteryBucket {
  final int notStarted;
  final int learning;
  final int mastered;
  MasteryBucket({required this.notStarted, required this.learning, required this.mastered});
}

class StatsCalculator {
  static List<TypeStat> typeStats(List<({QuestionType type, int total, int correct})> counts) {
    return counts.map((e) => TypeStat(type: e.type, total: e.total, correct: e.correct)).toList();
  }

  static MasteryBucket mastery(List<int> phases) {
    return MasteryBucket(
      notStarted: phases.where((p) => p == 0).length,
      learning: phases.where((p) => p >= 1 && p <= 5).length,
      mastered: phases.where((p) => p >= 6).length,
    );
  }

  static List<({DateTime day, int count, int correct})> dailyCounts({
    required List<({DateTime date, bool isCorrect})> logs,
    required int days,
    required DateTime today,
  }) {
    final start = DateTime(today.year, today.month, today.day);
    final res2 = <({DateTime day, int count, int correct})>[];
    for (var i = days - 1; i >= 0; i--) {
      final day = start.subtract(Duration(days: i));
      final inDay = logs.where((l) => _isSameDay(l.date, day)).toList();
      res2.add((day: day, count: inDay.length, correct: inDay.where((e) => e.isCorrect).length));
    }
    return res2;
  }

  static List<({DateTime day, int count})> reviewForecast({
    required List<({DateTime next, int phase})> due,
    required int days,
    required DateTime today,
  }) {
    final start = DateTime(today.year, today.month, today.day);
    return [
      for (var offset = 0; offset < days; offset++)
        (
          day: start.add(Duration(days: offset)),
          count: due.where((e) => _isSameDay(e.next, start.add(Duration(days: offset)))).length
        )
    ];
  }

  static List<({DateTime day, int count})> cardReviewForecast({
    required List<({DateTime next, int round})> due,
    required int days,
    required DateTime today,
  }) {
    final start = DateTime(today.year, today.month, today.day);
    return [
      for (var offset = 0; offset < days; offset++)
        (
          day: start.add(Duration(days: offset)),
          count: due.where((e) => _isSameDay(e.next, start.add(Duration(days: offset)))).length
        )
    ];
  }

  static int overdue(List<({DateTime next, int phase})> due, DateTime today) {
    final start = DateTime(today.year, today.month, today.day);
    return due.where((e) => e.next.isBefore(start)).length;
  }

  static int cardOverdue(List<({DateTime next, int round})> due, DateTime today) {
    final start = DateTime(today.year, today.month, today.day);
    return due.where((e) => e.next.isBefore(start)).length;
  }

  static ({int passed, int total, int covered, List<({String name, int passed, int total})> byModule}) topicStats(
      {required TopicOverview overview}) {
    final byModule = overview.sections
        .map((s) => (name: s.module.name, passed: s.passed, total: s.rows.length))
        .toList();
    return (
      passed: overview.passedCount,
      total: overview.totalCount,
      covered: overview.coveredQuestionCount,
      byModule: byModule
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
