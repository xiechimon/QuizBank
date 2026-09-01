import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/stats_calculator.dart';
import '../../../data/models.dart';

class DailyChartCard extends StatelessWidget {
  final List<AnswerLog> logs;
  const DailyChartCard({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final daily = StatsCalculator.dailyCounts(logs: logs.map((l) => (date: l.date, isCorrect: l.isCorrect)).toList(), days: 7, today: today);
    final maxY = (daily.map((d) => d.count).fold(0, (a, b) => a > b ? a : b) + 2).toDouble().clamp(5, 50).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.bar_chart_rounded, color: cs.primary), const SizedBox(width: 8), Text('近 7 天练习', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: BarChart(BarChartData(
              maxY: maxY,
              barTouchData: BarTouchData(enabled: true),
              gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY / 4),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: maxY / 4)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= daily.length) return const SizedBox.shrink();
                  final d = daily[idx].day;
                  return SideTitleWidget(meta: meta, child: Text('${d.month}/${d.day}', style: Theme.of(context).textTheme.labelSmall));
                })),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: [
                for (var i = 0; i < daily.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(toY: daily[i].count.toDouble(), width: 14, borderRadius: BorderRadius.circular(4), color: cs.primary, rodStackItems: [
                      BarChartRodStackItem(0, daily[i].correct.toDouble(), Colors.green.withValues(alpha: 0.9)),
                      BarChartRodStackItem(daily[i].correct.toDouble(), daily[i].count.toDouble(), cs.error.withValues(alpha: 0.7)),
                    ])
                  ])
              ],
            )),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('正确', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 12),
            Container(width: 12, height: 12, decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('错误', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text('共 ${daily.fold(0, (s, e) => s + e.count)} 题', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ]),
      ),
    );
  }
}
