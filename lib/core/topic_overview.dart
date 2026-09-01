import '../data/models.dart';
import 'topic_progress.dart';

class TopicOverviewRow {
  final StudyCard card;
  final TopicStatus status;
  final int correct;
  final int total;
  TopicOverviewRow({required this.card, required this.status, required this.correct, required this.total});
}

class ModuleSection {
  final StudyModule module;
  final List<TopicOverviewRow> rows;
  ModuleSection({required this.module, required this.rows});
  int get passed => rows.where((r) => r.status == TopicStatus.passed).length;
}

class TopicOverview {
  final List<ModuleSection> sections;
  final int passedCount;
  final int totalCount;
  final int coveredQuestionCount;
  final List<StudyCard> nextTopics;

  TopicOverview({
    required this.sections,
    required this.passedCount,
    required this.totalCount,
    required this.coveredQuestionCount,
    required this.nextTopics,
  });

  static TopicOverview compute({required List<StudyModule> modules, required List<Question> questions}) {
    final correctById = <int, int>{};
    for (final q in questions) {
      correctById[q.id] = q.timesCorrect;
    }

    final sections = <ModuleSection>[];
    var passedCount = 0;
    var totalCount = 0;
    var covered = 0;
    final orderedCards = <StudyCard>[];
    final passedFlags = <bool>[];

    final sortedModules = List<StudyModule>.from(modules)..sort((a, b) => a.order.compareTo(b.order));
    for (final m in sortedModules) {
      final rows = <TopicOverviewRow>[];
      final sortedCards = List<StudyCard>.from(m.cards)..sort((a, b) => a.order.compareTo(b.order));
      for (final card in sortedCards) {
        final status = TopicProgress.statusOf(card);
        final counts = card.relatedQuestionIds.map((id) => correctById[id]).whereType<int>().toList();
        final correct = counts.where((c) => c >= 1).length;
        rows.add(TopicOverviewRow(card: card, status: status, correct: correct, total: card.relatedQuestionIds.length));
        final isPassedOrGraduated = status == TopicStatus.passed || status == TopicStatus.graduated;
        if (isPassedOrGraduated) {
          passedCount += 1;
          covered += card.relatedQuestionIds.length;
        }
        orderedCards.add(card);
        passedFlags.add(isPassedOrGraduated);
      }
      sections.add(ModuleSection(module: m, rows: rows));
      totalCount += rows.length;
    }

    final next = <StudyCard>[];
    for (var i = 0; i < orderedCards.length; i++) {
      if (!passedFlags[i]) {
        next.add(orderedCards[i]);
        if (next.length >= 3) {
          break;
        }
      }
    }

    return TopicOverview(
      sections: sections,
      passedCount: passedCount,
      totalCount: totalCount,
      coveredQuestionCount: covered,
      nextTopics: next,
    );
  }
}
