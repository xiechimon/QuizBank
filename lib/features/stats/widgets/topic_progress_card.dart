import 'package:flutter/material.dart';
import '../../../core/stats_calculator.dart';
import '../../../core/topic_overview.dart';
import '../../../data/models.dart';

class TopicProgressCard extends StatelessWidget {
  final List<StudyModule> modules;
  final List<Question> questions;
  const TopicProgressCard({super.key, required this.modules, required this.questions});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overview = TopicOverview.compute(modules: modules, questions: questions);
    final stats = StatsCalculator.topicStats(overview: overview);
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.auto_stories_rounded, color: cs.secondary), const SizedBox(width: 8), Text('速记进度', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: _mini(context, label: '已通过', value: '${stats.passed}/${stats.total}', color: Colors.green)), const SizedBox(width: 8), Expanded(child: _mini(context, label: '覆盖题目', value: '${stats.covered}', color: cs.primary))]),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: stats.total > 0 ? stats.passed / stats.total : 0, minHeight: 8, backgroundColor: cs.surfaceContainerHighest)),
        const SizedBox(height: 12),
        ...stats.byModule.map((m) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
          Expanded(flex: 3, child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall)),
          Expanded(flex: 4, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: m.total > 0 ? m.passed / m.total : 0, minHeight: 6, backgroundColor: cs.surfaceContainerHighest))),
          const SizedBox(width: 8),
          SizedBox(width: 48, child: Text('${m.passed}/${m.total}', style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.end)),
        ]))),
        if (overview.nextTopics.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('接下来推荐', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...overview.nextTopics.map((c) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
            Icon(Icons.lightbulb_rounded, size: 14, color: cs.primary), const SizedBox(width: 6),
            Expanded(child: Text(c.title, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('${c.relatedQuestionIds.length} 题', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]))),
        ],
      ])),
    );
  }

  Widget _mini(BuildContext context, {required String label, required String value, required Color color}) => Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: color)), Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color))]));
}
