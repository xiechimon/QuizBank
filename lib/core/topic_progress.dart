import '../data/models.dart';

enum TopicStatus { new_, learning, passed, graduated }

extension TopicStatusX on TopicStatus {
  String get raw {
    switch (this) {
      case TopicStatus.new_:
        return 'new';
      case TopicStatus.learning:
        return 'learning';
      case TopicStatus.passed:
        return 'passed';
      case TopicStatus.graduated:
        return 'graduated';
    }
  }

  String get displayName {
    switch (this) {
      case TopicStatus.new_:
        return '未学';
      case TopicStatus.learning:
        return '学习中';
      case TopicStatus.passed:
        return '已通过';
      case TopicStatus.graduated:
        return '已毕业';
    }
  }

  static TopicStatus fromRaw(String r) {
    switch (r) {
      case 'new':
        return TopicStatus.new_;
      case 'learning':
        return TopicStatus.learning;
      case 'passed':
        return TopicStatus.passed;
      case 'graduated':
        return TopicStatus.graduated;
      default:
        return TopicStatus.new_;
    }
  }
}

class TopicProgress {
  static bool isSingleRoundPassed({
    required List<AnswerLog> sessionLogs,
    required Set<int> cardQuestionIds,
  }) {
    if (sessionLogs.isEmpty || cardQuestionIds.isEmpty) return false;
    final firstId = sessionLogs.first.sessionId;
    if (!sessionLogs.every((e) => e.sessionId == firstId)) return false;
    final loggedIds = sessionLogs.map((e) => e.questionID).toSet();
    if (loggedIds.length != cardQuestionIds.length) return false;
    if (!loggedIds.containsAll(cardQuestionIds)) return false;
    return sessionLogs.every((e) => e.isCorrect);
  }

  static TopicStatus statusOf(StudyCard card) {
    return TopicStatusX.fromRaw(card.storedStatusRaw);
  }

  static TopicStatus statusFromCounts(List<int> correctCounts) {
    if (correctCounts.isEmpty || !correctCounts.any((c) => c >= 1)) return TopicStatus.new_;
    return correctCounts.every((c) => c >= 1) ? TopicStatus.passed : TopicStatus.learning;
  }

  static List<T> nextTopics<T>(Iterable<T> ordered, bool Function(T) isPassed, int count) {
    final result = <T>[];
    for (final t in ordered) {
      if (!isPassed(t)) {
        result.add(t);
        if (result.length >= count) break;
      }
    }
    return result;
  }
}
