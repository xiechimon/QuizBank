// M3 quiz UI with grader, explanation view, Card
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../core/quiz_session_controller.dart';
import 'question_body_view.dart';

/// Simple quiz session UI with grader + explanation.
/// Covers single / multiple / judge via QuestionBodyView.
class QuizSessionView extends ConsumerStatefulWidget {
  final List<int> questionIds;
  final String title;
  final String sourceRaw;
  final List<Question>? injectedQuestions; // for testing without DB

  const QuizSessionView({
    super.key,
    required this.questionIds,
    this.title = '练习',
    this.sourceRaw = 'browse',
    this.injectedQuestions,
  });

  @override
  ConsumerState<QuizSessionView> createState() => _QuizSessionViewState();
}

class _QuizSessionViewState extends ConsumerState<QuizSessionView> {
  QuizSessionController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.injectedQuestions != null) {
      _initWithQuestions(widget.injectedQuestions!);
    } else {
      _loadFromDb();
    }
  }

  Future<void> _loadFromDb() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final rows = await db.allQuestions;
      final byId = {for (final r in rows) r.id: r};
      final questions = <Question>[];
      for (final id in widget.questionIds) {
        final row = byId[id];
        if (row == null) continue;
        questions.add(Question(
          id: row.id,
          typeRaw: row.typeRaw,
          stem: row.stem,
          options: row.options.map((m) => QuizOption(key: m['key']!, text: m['text']!)).toList(),
          answer: row.answer,
          explanation: row.explanation,
          moduleId: row.moduleId,
          bucketIndex: row.bucketIndex,
          phase: row.phase,
          nextReviewDate: row.nextReviewDate,
          lastAnsweredAt: row.lastAnsweredAt,
          timesCorrect: row.timesCorrect,
          timesWrong: row.timesWrong,
          isFavorite: row.isFavorite,
        ));
      }
      _initWithQuestions(questions);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _initWithQuestions(List<Question> qs) {
    final source = AnswerSourceX.fromRaw(widget.sourceRaw);
    _controller = QuizSessionController(
      questions: qs,
      source: source,
      logSaver: (log) async {
        // persist log to DB if possible
        try {
          final db = ref.read(appDatabaseProvider);
          await db.into(db.answerLogs).insert(
                AnswerLogsCompanion.insert(
                  date: log.date,
                  questionId: log.questionID,
                  chosen: log.chosen,
                  isCorrect: log.isCorrect,
                  sourceRaw: log.sourceRaw,
                  sessionId: log.sessionId,
                ),
              );
          // also update question phase in DB
          final q = log.question;
          if (q != null) {
            await (db.update(db.questions)..where((t) => t.id.equals(q.id))).write(
              QuestionsCompanion(
                phase: drift.Value(q.phase),
                nextReviewDate: drift.Value(q.nextReviewDate),
                lastAnsweredAt: drift.Value(q.lastAnsweredAt),
                timesCorrect: drift.Value(q.timesCorrect),
                timesWrong: drift.Value(q.timesWrong),
              ),
            );
          }
        } catch (_) {}
      },
    );
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(child: Text('加载失败: $_error')),
      );
    }
    final c = _controller!;
    if (c.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('暂无题目')),
      );
    }
    if (c.isFinished) {
      return _buildResult(context, c);
    }
    final q = c.current!;
    final submitted = c.submitted;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (c.index + (submitted ? 1 : 0)) / c.questions.length,
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('${c.index + 1}/${c.questions.length}',
                  style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
          IconButton(
            icon: Icon(q.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: q.isFavorite ? Colors.amber : null),
            onPressed: () {
              setState(() => c.toggleFavorite());
              // persist favorite?
              _persistFavorite(q);
            },
          ),
        ],
      ),
      body: QuestionBodyView(
        question: q,
        selected: q.type == QuestionType.multiple ? c.pendingMulti : (submitted ? {c.lastChosen} : {}),
        submitted: submitted,
        lastChosen: c.lastChosen.isEmpty ? null : c.lastChosen,
        lastCorrect: submitted ? c.lastCorrect : null,
        onSingleTap: (key) {
          setState(() => c.submitSingle(key));
        },
        onMultiToggle: (key) {
          setState(() => c.toggleMulti(key));
        },
        onMultiSubmit: () {
          setState(() => c.submitMulti());
        },
        onJudgeTap: (value) {
          setState(() => c.submitJudge(value));
        },
      ),
      bottomNavigationBar: submitted
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: FilledButton.icon(
                onPressed: () => setState(() => c.next()),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(c.index + 1 >= c.questions.length ? '查看结果' : '下一题'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            )
          : null,
    );
  }

  Widget _buildResult(BuildContext context, QuizSessionController c) {
    final cs = Theme.of(context).colorScheme;
    final total = c.questions.length;
    final correct = c.correctCount;
    final acc = total > 0 ? correct / total : 0.0;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} - 结果')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.emoji_events_rounded, size: 48, color: cs.onPrimaryContainer),
                  const SizedBox(height: 12),
                  Text('$correct / $total',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          )),
                  Text('正确率 ${(acc * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: cs.onPrimaryContainer,
                          )),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: acc, backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text(
                    acc >= 0.9
                        ? '太棒了！'
                        : acc >= 0.6
                            ? '继续加油'
                            : '再接再厉，错题将进入错题本',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onPrimaryContainer,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              setState(() {
                c.index = 0;
                c.correctCount = 0;
                c.wrongCount = 0;
                c.submitted = false;
              });
            },
            child: const Text('再练一次'),
          ),
          const SizedBox(height: 16),
          Text('答题明细', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...c.questions.asMap().entries.map((e) {
            final idx = e.key;
            final q = e.value;
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${idx + 1}')),
                title: Text(q.stem, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('答案: ${q.answer}'),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _persistFavorite(Question q) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.questions)..where((t) => t.id.equals(q.id))).write(
        QuestionsCompanion(isFavorite: drift.Value(q.isFavorite)),
      );
    } catch (_) {}
  }
}


