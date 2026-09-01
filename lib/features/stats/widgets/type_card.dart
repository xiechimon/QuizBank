import 'package:flutter/material.dart';
import '../../../core/stats_calculator.dart';
import '../../../data/models.dart';

class TypeCard extends StatelessWidget {
  final List<Question> questions;
  final List<AnswerLog> logs;
  const TypeCard({super.key, required this.questions, required this.logs});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qById = {for (final q in questions) q.id: q};
    final logByType = <QuestionType, List<AnswerLog>>{};
    for (final log in logs) {
      final q = qById[log.questionID];
      if (q == null) continue;
      logByType.putIfAbsent(q.type, () => []).add(log);
    }
    final stats = QuestionType.values.map((t) {
      final total = logByType[t]?.length ?? 0;
      final correct = logByType[t]?.where((l) => l.isCorrect).length ?? 0;
      return TypeStat(type: t, total: total, correct: correct);
    }).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.category_rounded, color: cs.secondary), const SizedBox(width: 8), Text('题型正确率', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          ...stats.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(width: 48, child: Text(s.type.displayName, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: s.accuracy, minHeight: 10, backgroundColor: cs.surfaceContainerHighest, color: s.accuracy >= 0.8 ? Colors.green : s.accuracy >= 0.6 ? Colors.orange : cs.error))),
                  const SizedBox(width: 8),
                  SizedBox(width: 54, child: Text('${(s.accuracy * 100).toStringAsFixed(1)}%  ${s.correct}/${s.total}', style: Theme.of(context).textTheme.labelSmall)),
                ]),
              )),
          if (stats.every((s) => s.total == 0)) Padding(padding: const EdgeInsets.only(top: 8), child: Text('暂无答题记录', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        ]),
      ),
    );
  }
}
