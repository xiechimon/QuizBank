import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/stats_calculator.dart';
import '../../../core/topic_progress.dart';
import '../../../data/models.dart';

class ForecastCard extends StatelessWidget {
  final List<StudyCard> cards;
  const ForecastCard({super.key, required this.cards});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final due = cards.where((c) => c.nextReviewDate != null && TopicStatusX.fromRaw(c.storedStatusRaw) == TopicStatus.passed).map((c) => (next: c.nextReviewDate!, round: c.consolidationRound)).toList();
    final forecast = StatsCalculator.cardReviewForecast(due: due, days: 7, today: today);
    final maxY = (forecast.map((f) => f.count).fold(0, (a, b) => a > b ? a : b) + 2).toDouble().clamp(5, 20).toDouble();
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.event_repeat_rounded, color: cs.tertiary), const SizedBox(width: 8), Text('未来 7 天复习负载', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
        const SizedBox(height: 4),
        Text('基于当前已通过卡片的下次复习日期预测', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        SizedBox(height: 160, child: BarChart(BarChartData(
          maxY: maxY,
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY / 2),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: maxY / 2)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= forecast.length) return const SizedBox.shrink();
              return SideTitleWidget(meta: meta, child: Text('${forecast[idx].day.month}/${forecast[idx].day.day}', style: Theme.of(context).textTheme.labelSmall));
            })),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: [for (var i=0;i<forecast.length;i++) BarChartGroupData(x: i, barRods: [BarChartRodData(toY: forecast[i].count.toDouble(), width: 14, borderRadius: BorderRadius.circular(4), color: cs.tertiary)])],
        ))),
        const SizedBox(height: 8),
        Text('未来 7 天共 ${forecast.fold(0, (s, e) => s + e.count)} 张卡片待复习', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ])),
    );
  }
}
