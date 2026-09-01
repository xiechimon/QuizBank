import '../data/models.dart';
import 'topic_progress.dart';

class CardStatusMigration {
  static void backfillIfNeeded({
    required List<StudyCard> cards,
    required List<Question> questions,
    required List<AnswerLog> logs,
    required DateTime today,
  }) {
    final todayStart = DateTime(today.year, today.month, today.day);
    final qById = <int, Question>{for (final q in questions) q.id: q};

    for (final card in cards) {
      if (card.passedAt != null) continue;
      if (card.storedStatusRaw == TopicStatus.passed.raw || card.storedStatusRaw == TopicStatus.graduated.raw) continue;
      final qIds = card.relatedQuestionIds;
      if (qIds.isEmpty) continue;

      var counts = <int>[];
      var hasMissing = false;
      DateTime? latest;
      for (final id in qIds) {
        final q = qById[id];
        if (q == null) {
          hasMissing = true;
          break;
        }
        counts.add(q.timesCorrect);
        if (q.lastAnsweredAt != null) {
          if (latest == null || q.lastAnsweredAt!.isAfter(latest)) latest = q.lastAnsweredAt;
        }
      }
      if (hasMissing) continue;
      final oldStatus = TopicProgress.statusFromCounts(counts);
      if (oldStatus != TopicStatus.passed) continue;

      card.storedStatusRaw = TopicStatus.passed.raw;
      card.passedAt = latest ?? todayStart;
      card.nextReviewDate = todayStart.add(const Duration(days: 7));
      card.consolidationRound = 0;
    }
  }
}
