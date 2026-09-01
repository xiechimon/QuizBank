import 'package:flutter/material.dart';
import '../../../core/stats_calculator.dart';
import '../../../data/models.dart';

class MasteryCard extends StatelessWidget {
  final List<Question> questions;
  const MasteryCard({super.key, required this.questions});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phases = questions.map((q) => q.phase).toList();
    final mastery = StatsCalculator.mastery(phases);
    final total = questions.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.workspace_premium_rounded, color: cs.primary), const SizedBox(width: 8), Text('掌握度', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          Row(children: [
            _chip(context, label: '未开始', count: mastery.notStarted, total: total, color: cs.outline),
            const SizedBox(width: 8),
            _chip(context, label: '学习中', count: mastery.learning, total: total, color: Colors.orange),
            const SizedBox(width: 8),
            _chip(context, label: '已掌握', count: mastery.mastered, total: total, color: Colors.green),
          ]),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: total > 0 ? mastery.mastered / total : 0, minHeight: 8, backgroundColor: cs.surfaceContainerHighest)),
          const SizedBox(height: 6),
          Text('${mastery.mastered}/$total 已掌握 · ${mastery.learning} 学习中 · ${mastery.notStarted} 未开始', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _chip(BuildContext context, {required String label, required int count, required int total, required Color color}) {
    final pct = total > 0 ? count / total * 100 : 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text('$count', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
          Text('${pct.toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }
}
