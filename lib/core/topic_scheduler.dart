import '../data/models.dart';
import 'topic_progress.dart';

class TopicScheduler {
  static ({TopicStatus status, int nextRound, DateTime? nextDate}) transit({
    required StudyCard card,
    required bool sessionCorrect,
    required DateTime today,
  }) {
    final todayStart = DateTime(today.year, today.month, today.day);
    final current = TopicStatusX.fromRaw(card.storedStatusRaw);

    switch (current) {
      case TopicStatus.new_:
      case TopicStatus.learning:
        if (sessionCorrect) {
          return (
            status: TopicStatus.passed,
            nextRound: 1,
            nextDate: todayStart.add(const Duration(days: 7))
          );
        } else {
          return (status: TopicStatus.learning, nextRound: 0, nextDate: null);
        }
      case TopicStatus.passed:
        if (sessionCorrect) {
          final currentRound = card.consolidationRound;
          final effective = currentRound < 1 ? 1 : currentRound;
          final newRound = effective + 1;
          switch (newRound) {
            case 2:
              return (
                status: TopicStatus.passed,
                nextRound: 2,
                nextDate: todayStart.add(const Duration(days: 30))
              );
            case 3:
              return (
                status: TopicStatus.passed,
                nextRound: 3,
                nextDate: todayStart.add(const Duration(days: 90))
              );
            default:
              if (effective >= 3) {
                return (status: TopicStatus.graduated, nextRound: 3, nextDate: null);
              }
              return (status: TopicStatus.graduated, nextRound: 3, nextDate: null);
          }
        } else {
          return (status: TopicStatus.learning, nextRound: 0, nextDate: null);
        }
      case TopicStatus.graduated:
        if (sessionCorrect) {
          return (status: TopicStatus.graduated, nextRound: card.consolidationRound, nextDate: null);
        } else {
          return (status: TopicStatus.learning, nextRound: 0, nextDate: null);
        }
    }
  }
}
