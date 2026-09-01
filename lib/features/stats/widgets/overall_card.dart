import 'package:flutter/material.dart';
import '../../../data/models.dart';

class OverallCard extends StatelessWidget {
  final List<Question> questions;
  final List<AnswerLog> logs;
  const OverallCard({super.key, required this.questions, required this.logs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = questions.length;
    final answered = questions.where((q) => q.timesCorrect + q.timesWrong > 0).length;
    final totalLogs = logs.length;
    final correctLogs = logs.where((l) => l.isCorrect).length;
    final acc = totalLogs > 0 ? correctLogs / totalLogs : 0.0;
    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.dashboard_rounded, color: cs.onPrimaryContainer), const SizedBox(width: 8), Text('总览', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer))]),
          const SizedBox(height: 12),
          Row(children: [
            _mini(context, label: '题库', value: '$total', icon: Icons.library_books_rounded),
            const SizedBox(width: 12),
            _mini(context, label: '已练', value: '$answered', icon: Icons.check_circle_rounded),
            const SizedBox(width: 12),
            _mini(context, label: '答题', value: '$totalLogs', icon: Icons.edit_note_rounded),
            const SizedBox(width: 12),
            _mini(context, label: '正确率', value: '${(acc * 100).toStringAsFixed(1)}%', icon: Icons.trending_up_rounded),
          ]),
        ]),
      ),
    );
  }

  Widget _mini(BuildContext context, {required String label, required String value, required IconData icon}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
