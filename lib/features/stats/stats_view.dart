// M3: Card, BarChart (fl_chart) — 拆分子件后仅做组装
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers.dart';
import 'widgets/overall_card.dart';
import 'widgets/mastery_card.dart';
import 'widgets/type_card.dart';
import 'widgets/daily_chart_card.dart';
import 'widgets/forecast_card.dart';
import 'widgets/topic_progress_card.dart';
import '../settings/settings_view.dart';

class StatsView extends ConsumerWidget {
  const StatsView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(allQuestionsProvider);
    final logsAsync = ref.watch(allAnswerLogsProvider);
    final cardsAsync = ref.watch(allStudyCardsProvider);
    final modulesAsync = ref.watch(allStudyModulesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('复盘'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsView()),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        if (questionsAsync.isLoading || logsAsync.isLoading || cardsAsync.isLoading || modulesAsync.isLoading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (questionsAsync.hasError || logsAsync.hasError)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('加载失败')))
        else ...[
          OverallCard(questions: questionsAsync.value ?? [], logs: logsAsync.value ?? []),
          const SizedBox(height: 12),
          MasteryCard(questions: questionsAsync.value ?? []),
          const SizedBox(height: 12),
          TypeCard(questions: questionsAsync.value ?? [], logs: logsAsync.value ?? []),
          const SizedBox(height: 12),
          DailyChartCard(logs: logsAsync.value ?? []),
          const SizedBox(height: 12),
          ForecastCard(cards: cardsAsync.value ?? []),
          const SizedBox(height: 12),
          TopicProgressCard(modules: modulesAsync.value ?? [], questions: questionsAsync.value ?? []),
        ],
      ]),
    );
  }
}
