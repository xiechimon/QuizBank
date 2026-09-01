// M3: Card, NavigationBar (app.dart), Derived.compute logic with dueCards/newCards
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../core/topic_progress.dart';
import '../ai/ai_explain_sheet.dart';
import '../cards/card_content_view.dart';
import '../quiz/quiz_session_view.dart';

// ---------------------------------------------------------------------------
// Derived: pure computation for Today plan
// Testable without DB - pass in-memory StudyCard list + today
// ---------------------------------------------------------------------------
class Derived {
  final List<StudyCard> dueCards;
  final List<StudyCard> newCards;

  const Derived({required this.dueCards, required this.newCards});

  /// Total question count for today's plan: dueQuestions + new accumulation
  int get totalQuestionsCount =>
      dueCards.fold(0, (s, c) => s + c.relatedQuestionIds.length) +
      newCards.fold(0, (s, c) => s + c.relatedQuestionIds.length);

  int get dueQuestionsCount =>
      dueCards.fold(0, (s, c) => s + c.relatedQuestionIds.length);

  int get newQuestionsCount =>
      newCards.fold(0, (s, c) => s + c.relatedQuestionIds.length);

  /// Total cards in today's plan
  int get totalCards => dueCards.length + newCards.length;

  bool get isEmpty => dueCards.isEmpty && newCards.isEmpty;

  static const int targetQuestions = 40;

  /// Compute Today's study plan.
  ///
  /// * dueCards = passed & nextReviewDate <= today sorted by next earliest
  /// * newCards = new/learning filling to ~40 questions (dueQuestions + new accumulation)
  static Derived compute({
    required List<StudyCard> allCards,
    required DateTime today,
  }) {
    final todayStart = DateTime(today.year, today.month, today.day);

    // DUE: passed cards whose nextReviewDate is due
    final due = allCards.where((c) {
      final status = TopicStatusX.fromRaw(c.storedStatusRaw);
      if (status != TopicStatus.passed) return false;
      final next = c.nextReviewDate;
      if (next == null) return false;
      final nextStart = DateTime(next.year, next.month, next.day);
      return !nextStart.isAfter(todayStart);
    }).toList();

    // sort by next earliest
    due.sort((a, b) {
      final an = a.nextReviewDate!;
      final bn = b.nextReviewDate!;
      final cmp = an.compareTo(bn);
      if (cmp != 0) return cmp;
      // secondary: order within module
      final ao = a.module?.order ?? 999;
      final bo = b.module?.order ?? 999;
      if (ao != bo) return ao.compareTo(bo);
      return a.order.compareTo(b.order);
    });

    final dueQuestions = due.fold(0, (s, c) => s + c.relatedQuestionIds.length);

    // NEW: new_ or learning candidates filling to ~40 questions
    final candidates = allCards.where((c) {
      final s = TopicStatusX.fromRaw(c.storedStatusRaw);
      return s == TopicStatus.new_ || s == TopicStatus.learning;
    }).toList();

    // preserve ordered by module/card order (insertion order already sorted)
    // No status prioritization; due already prioritized, new fills in given order
    candidates.sort((a, b) {
      final ao = a.module?.order ?? 999;
      final bo = b.module?.order ?? 999;
      if (ao != bo) return ao.compareTo(bo);
      return a.order.compareTo(b.order);
    });

    final newCards = <StudyCard>[];
    var acc = dueQuestions;
    // if already >= target, no new cards
    for (final c in candidates) {
      if (acc >= targetQuestions) break;
      newCards.add(c);
      acc += c.relatedQuestionIds.length;
    }

    return Derived(dueCards: due, newCards: newCards);
  }
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------
class TodayView extends ConsumerWidget {
  const TodayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(allStudyCardsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('今日')),
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (cards) {
          final today = DateTime.now();
          final derived = Derived.compute(allCards: cards, today: today);
          if (derived.isEmpty) {
            return _buildEmpty(context);
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allStudyCardsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _summaryCard(context, derived),
                const SizedBox(height: 16),
                if (derived.dueCards.isNotEmpty) ...[
                  _dueSection(context, derived),
                  const SizedBox(height: 16),
                ],
                if (derived.newCards.isNotEmpty) ...[
                  _newSection(context, derived),
                  const SizedBox(height: 16),
                ],
                _hintFooter(context, derived),
                const SizedBox(height: 16),
                _startButton(context, derived),
              ],
            ),
          );
        },
      ),
    );
  }

  // Summary card: M3 Card with due + new + total
  Widget _summaryCard(BuildContext context, Derived d) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny_rounded, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Text('今日学习',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        )),
                const Spacer(),
                FilledButton(
                  onPressed: d.isEmpty
                      ? null
                      : () => _startTodayQuiz(context, d),
                  child: const Text('开始学习'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _statChip(context,
                    label: '复习卡片',
                    value: '${d.dueCards.length}',
                    icon: Icons.replay_rounded),
                const SizedBox(width: 12),
                _statChip(context,
                    label: '新学卡片',
                    value: '${d.newCards.length}',
                    icon: Icons.auto_stories_rounded),
                const SizedBox(width: 12),
                _statChip(context,
                    label: '题目',
                    value: '${d.totalQuestionsCount}',
                    icon: Icons.quiz_rounded),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: d.totalQuestionsCount > 0 ? (d.dueQuestionsCount / d.totalQuestionsCount).clamp(0.0, 1.0) : 0,
              backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.15),
              color: cs.primary,
            ),
            const SizedBox(height: 8),
            Text(
              '已按复习优先排序，优先巩固已学内容，再学习新卡片至约40题',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.85),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(BuildContext context,
      {required String label, required String value, required IconData icon}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    )),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    )),
          ],
        ),
      ),
    );
  }

  Widget _dueSection(BuildContext context, Derived d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.replay_circle_filled_rounded,
                size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('待复习',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(width: 8),
            Chip(
              label: Text('${d.dueCards.length} 卡 · ${d.dueQuestionsCount} 题'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...d.dueCards.map((c) => _cardTile(context, card: c, isDue: true)),
      ],
    );
  }

  Widget _newSection(BuildContext context, Derived d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_stories_rounded,
                size: 20, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 8),
            Text('新学',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(width: 8),
            Chip(
              label: Text('${d.newCards.length} 卡 · ${d.newQuestionsCount} 题'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...d.newCards.map((c) => _cardTile(context, card: c, isDue: false)),
      ],
    );
  }

  Widget _cardTile(BuildContext context,
      {required StudyCard card, required bool isDue}) {
    final status = TopicStatusX.fromRaw(card.storedStatusRaw);
    final cs = Theme.of(context).colorScheme;
    final related = card.relatedQuestionIds.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHighest,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // jump to card detail
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _TodayCardBridge(card: card)));
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDue ? cs.primary.withValues(alpha: 0.15) : cs.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isDue ? Icons.replay_rounded : Icons.lightbulb_rounded,
                    color: isDue ? cs.primary : cs.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        '${card.module?.name ?? '通用'} · $related 题 · ${status.displayName}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (card.nextReviewDate != null && isDue)
                        Text(
                          '到期 ${_fmtDate(card.nextReviewDate!)}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: cs.error,
                              ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hintFooter(BuildContext context, Derived d) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.secondaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.tips_and_updates_rounded, size: 20, color: cs.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                d.dueCards.isEmpty
                    ? '今日暂无到期复习卡片，系统已为你挑选 ${d.newCards.length} 张新卡片进行学习。完成学习后次日将进入 7→30→90 天巩固周期。'
                    : '建议先完成 ${d.dueCards.length} 张复习卡片，再学习新卡片。复习正确率越高，记忆越巩固；答错将回退至学习状态，次日再次巩固。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSecondaryContainer,
                      height: 1.4,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _startButton(BuildContext context, Derived d) {
    final allIds = [
      for (final c in d.dueCards) ...c.relatedQuestionIds,
      for (final c in d.newCards) ...c.relatedQuestionIds,
    ];
    if (allIds.isEmpty) return const SizedBox.shrink();
    return FilledButton.icon(
      onPressed: () => _startTodayQuiz(context, d),
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text('开始今日学习 (${d.totalQuestionsCount} 题)'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }

  void _startTodayQuiz(BuildContext context, Derived d) {
    final questionIds = [
      for (final c in d.dueCards) ...c.relatedQuestionIds,
      for (final c in d.newCards) ...c.relatedQuestionIds,
    ];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuizSessionView(
        questionIds: questionIds,
        title: '今日学习',
        sourceRaw: 'todayNew',
      ),
    ));
  }

  Widget _buildEmpty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration_rounded, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text('今日已完成',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 8),
            Text('所有卡片已巩固，明天再来吧！',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.month}/${d.day}';
}

// Minimal bridge to study card detail without circular import
class _TodayCardBridge extends StatelessWidget {
  final StudyCard card;
  const _TodayCardBridge({required this.card});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(card.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CardContentView(
                content: card.content,
                onExplain: (sel) => AIExplainSheet.show(context, selection: sel, cardTitle: card.title, cardContent: card.content),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => QuizSessionView(
                  questionIds: card.relatedQuestionIds,
                  title: card.title,
                  sourceRaw: 'cardJump',
                ),
              ));
            },
            icon: const Icon(Icons.quiz_rounded),
            label: Text('练习关联题目 (${card.relatedQuestionIds.length})'),
          ),
        ],
      ),
    );
  }
}

// Backward alias for tests that may import TodayDerived
typedef TodayDerived = Derived;
