// M3: Card, FilterChip, FAB (FloatingActionButton), SegmentedButton, NavigationBar via app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../quiz/quiz_session_view.dart';

enum PracticeScope { all, favorite, wrongBook }

extension PracticeScopeX on PracticeScope {
  String get label {
    switch (this) {
      case PracticeScope.all:
        return '全部';
      case PracticeScope.favorite:
        return '收藏';
      case PracticeScope.wrongBook:
        return '错题';
    }
  }

  IconData get icon {
    switch (this) {
      case PracticeScope.all:
        return Icons.grid_view_rounded;
      case PracticeScope.favorite:
        return Icons.star_rounded;
      case PracticeScope.wrongBook:
        return Icons.error_outline_rounded;
    }
  }
}

// ---------------------------------------------------------------------------
// Pure filter helper for testing without DB
// ---------------------------------------------------------------------------
class PracticeFilter {
  static List<Question> apply({
    required List<Question> all,
    required PracticeScope scope,
    required QuestionType? type, // null = all types
  }) {
    var list = all;
    switch (scope) {
      case PracticeScope.favorite:
        list = list.where((q) => q.isFavorite).toList();
        break;
      case PracticeScope.wrongBook:
        list = list.where((q) => q.timesWrong > 0 && q.phase < 6).toList();
        break;
      case PracticeScope.all:
        break;
    }
    if (type != null) {
      list = list.where((q) => q.type == type).toList();
    }
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }
}

class PracticeView extends ConsumerStatefulWidget {
  const PracticeView({super.key});

  @override
  ConsumerState<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends ConsumerState<PracticeView> {
  PracticeScope _scope = PracticeScope.all;
  QuestionType? _type; // null = all

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(allQuestionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('刷题'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _showSearch(context),
          ),
        ],
      ),
      body: questionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (all) {
          final filtered = PracticeFilter.apply(all: all, scope: _scope, type: _type);
          return Column(
            children: [
              _buildScopeFilter(context),
              _buildTypeFilter(context),
              _buildCounts(context, all, filtered),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? _emptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final q = filtered[i];
                          return _questionCard(context, q, i);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final all = await ref.read(allQuestionsProvider.future).catchError((_) => <Question>[]);
          if (!context.mounted) return;
          final filtered = PracticeFilter.apply(all: all, scope: _scope, type: _type);
          if (filtered.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('当前筛选无题目')),
            );
            return;
          }
          // random 20 or all?
          final ids = filtered.map((e) => e.id).toList()..shuffle();
          final take = ids.length > 20 ? ids.sublist(0, 20) : ids;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => QuizSessionView(
              questionIds: take,
              title: '刷题练习',
              sourceRaw: _scope == PracticeScope.wrongBook ? 'wrongBook' : 'browse',
            ),
          ));
        },
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('开始刷题'),
      ),
    );
  }

  Widget _buildScopeFilter(BuildContext context) {
    // Requirement: SegmentedButton or FilterChip - we provide SegmentedButton for scope
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: SegmentedButton<PracticeScope>(
        segments: PracticeScope.values
            .map((s) => ButtonSegment<PracticeScope>(
                  value: s,
                  label: Text(s.label),
                  icon: Icon(s.icon, size: 18),
                ))
            .toList(),
        selected: {_scope},
        onSelectionChanged: (v) => setState(() => _scope = v.first),
        showSelectedIcon: false,
      ),
    );
  }

  Widget _buildTypeFilter(BuildContext context) {
    // Requirement: FilterChip for type filter
    final options = <QuestionType?>[null, QuestionType.single, QuestionType.multiple, QuestionType.judge];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: options.map((t) {
          final label = t == null ? '全部题型' : t.displayName;
          final selected = _type == t;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => setState(() => _type = t),
              showCheckmark: true,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCounts(BuildContext context, List<Question> all, List<Question> filtered) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('共 ${filtered.length} 题',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  )),
          const Spacer(),
          Text('题库 ${all.length}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }

  Widget _questionCard(BuildContext context, Question q, int index) {
    final cs = Theme.of(context).colorScheme;
    final typeLabel = q.type.displayName;
    final fav = q.isFavorite;
    final wrong = q.timesWrong > 0;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => QuizSessionView(
              questionIds: [q.id],
              title: '刷题 #${q.id}',
              sourceRaw: 'browse',
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(typeLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            )),
                  ),
                  const SizedBox(width: 6),
                  Text('#${q.id}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          )),
                  const Spacer(),
                  if (fav) Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade600),
                  if (wrong)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.error_rounded, size: 16, color: cs.error),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                q.stem,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: q.options.take(4).map((o) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${o.key}. ${o.text}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('正确 ${q.timesCorrect}  错误 ${q.timesWrong}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          )),
                  const Spacer(),
                  Text('解析 >',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                          )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String msg;
    switch (_scope) {
      case PracticeScope.favorite:
        msg = '暂无收藏题目，去刷题时点击星标收藏';
        break;
      case PracticeScope.wrongBook:
        msg = '暂无错题，太棒了！';
        break;
      case PracticeScope.all:
        msg = '暂无题目，请检查数据导入';
        break;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(msg, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _QuestionSearchDelegate(
        allProvider: allQuestionsProvider,
        ref: ref,
      ),
    );
  }
}

class _QuestionSearchDelegate extends SearchDelegate<Question?> {
  final FutureProvider<List<Question>> allProvider;
  final WidgetRef ref;
  _QuestionSearchDelegate({required this.allProvider, required this.ref});

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => query = ''),
      ];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );
  @override
  Widget buildResults(BuildContext context) => _buildList(context);
  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final async = ref.watch(allProvider);
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final filtered = all.where((q) => q.stem.toLowerCase().contains(query.toLowerCase())).take(50).toList();
          if (filtered.isEmpty) return const Center(child: Text('无结果'));
          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final q = filtered[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  title: Text(q.stem, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('#${q.id} ${q.type.displayName}'),
                  onTap: () {
                    close(context, q);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => QuizSessionView(questionIds: [q.id], title: '题目 #${q.id}'),
                    ));
                  },
                ),
              );
            },
          );
        },
      );
    });
  }
}
