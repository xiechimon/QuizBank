import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Database provider
// ---------------------------------------------------------------------------
final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

// ---------------------------------------------------------------------------
// 速记目录树展开状态：模块 id 集合，跨 tab / 跨重启记忆（SharedPreferences 持久化）
// ---------------------------------------------------------------------------
class TocExpansionNotifier extends Notifier<Set<int>> {
  static const _prefsKey = 'cardToc.expandedModuleIds';

  @override
  Set<int> build() {
    _load();
    return <int>{};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        state = raw.map(int.tryParse).whereType<int>().toSet();
      }
    } catch (_) {}
  }

  void toggle(int moduleId) {
    final next = {...state};
    if (!next.remove(moduleId)) next.add(moduleId);
    state = next;
    _persist(next);
  }

  Future<void> _persist(Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, ids.map((e) => '$e').toList());
    } catch (_) {}
  }
}

final tocExpansionProvider = NotifierProvider<TocExpansionNotifier, Set<int>>(TocExpansionNotifier.new);

// Mappers Db -> Model
Question _mapQuestion(DbQuestion e) => Question(
      id: e.id,
      typeRaw: e.typeRaw,
      stem: e.stem,
      options: e.options.map((m) => QuizOption(key: m['key']!, text: m['text']!)).toList(),
      answer: e.answer,
      explanation: e.explanation,
      moduleId: e.moduleId,
      bucketIndex: e.bucketIndex,
      phase: e.phase,
      nextReviewDate: e.nextReviewDate,
      lastAnsweredAt: e.lastAnsweredAt,
      timesCorrect: e.timesCorrect,
      timesWrong: e.timesWrong,
      isFavorite: e.isFavorite,
    );

StudyCard _mapCard(DbStudyCard e, StudyModule? module) => StudyCard(
      cardId: e.cardId,
      title: e.title,
      content: e.content,
      order: e.sortOrder,
      relatedQuestionIds: e.relatedQuestionIds,
      isRead: e.isRead,
      isFavorite: e.isFavorite,
      module: module,
      storedStatusRaw: e.storedStatusRaw,
      passedAt: e.passedAt,
      nextReviewDate: e.nextReviewDate,
      consolidationRound: e.consolidationRound,
      lastSessionId: e.lastSessionId,
    );

StudyModule _mapModule(DbStudyModule m) => StudyModule(id: m.id, name: m.name, order: m.sortOrder);

// Providers
final allQuestionsProvider = FutureProvider<List<Question>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.allQuestions;
  return rows.map(_mapQuestion).toList();
});

final allStudyCardsProvider = FutureProvider<List<StudyCard>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final cards = await db.allCards;
  final modules = await db.allModules;
  final modMap = {for (final m in modules) m.id: _mapModule(m)};
  // attach cards to modules for ordering
  for (final c in cards) {
    final mid = c.moduleId;
    if (mid != null && modMap.containsKey(mid)) {
      final card = _mapCard(c, modMap[mid]);
      modMap[mid]!.cards.add(card);
    }
  }
  final list = cards.map((e) {
    final mod = e.moduleId != null ? modMap[e.moduleId] : null;
    return _mapCard(e, mod);
  }).toList();
  // sort for deterministic
  list.sort((a, b) {
    final ao = a.module?.order ?? 999;
    final bo = b.module?.order ?? 999;
    if (ao != bo) return ao.compareTo(bo);
    return a.order.compareTo(b.order);
  });
  return list;
});

final allStudyModulesProvider = FutureProvider<List<StudyModule>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final mods = await db.allModules;
  final cards = await db.allCards;
  final modules = mods.map(_mapModule).toList();
  final byId = {for (final m in modules) m.id: m};
  for (final c in cards) {
    final card = _mapCard(c, c.moduleId != null ? byId[c.moduleId] : null);
    final mid = c.moduleId;
    if (mid != null && byId.containsKey(mid)) {
      byId[mid]!.cards.add(card);
    }
  }
  modules.sort((a, b) => a.order.compareTo(b.order));
  for (final m in modules) {
    m.cards.sort((a, b) => a.order.compareTo(b.order));
  }
  return modules;
});

final allAnswerLogsProvider = FutureProvider<List<AnswerLog>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final logs = await db.allLogs;
  return logs
      .map((e) => AnswerLog(
            date: e.date,
            questionID: e.questionId,
            chosen: e.chosen,
            isCorrect: e.isCorrect,
            sourceRaw: e.sourceRaw,
            sessionId: e.sessionId,
          ))
      .toList();
});
