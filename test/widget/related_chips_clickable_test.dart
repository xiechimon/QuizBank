import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/data/database.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/data/providers.dart';
import 'package:quiz_bank/features/cards/study_home_view.dart';
import 'package:quiz_bank/features/quiz/quiz_session_view.dart';

/// 回归锁：关联题目芯片必须可点击且为 suffix 连续练习
/// 对应 bug：Chip 不可点击 → ActionChip suffix（grill 决策：逐题 已提交→下一题，全部答完才 会话已结束）
/// iOS 真源 FlowChips: Array(questions[i...]) 正向对齐
void main() {
  group('关联题目可点击回归', () {
    Future<void> pumpDetail(WidgetTester t, StudyCard card, List<StudyModule> mods) async {
      final dbQs = [
        Question(id: 1, typeRaw: 'single', stem: '题干1', options: [QuizOption(key: 'A', text: 'a')], answer: 'A', explanation: '解析1', bucketIndex: 0),
        Question(id: 2, typeRaw: 'single', stem: '题干2', options: [QuizOption(key: 'A', text: 'a')], answer: 'A', explanation: '解析2', bucketIndex: 0),
      ];
      await t.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(_FakeDb(dbQs)),
          allStudyModulesProvider.overrideWith((ref) async => mods),
          allQuestionsProvider.overrideWith((ref) async => dbQs),
          allStudyCardsProvider.overrideWith((ref) async => [card]),
          allAnswerLogsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(home: StudyCardDetailView(initialCard: card, allModules: mods)),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('芯片为 ActionChip 且可点击', (t) async {
      final mod = StudyModule(id: 1, name: '模块1', order: 1, cards: []);
      final card = StudyCard(cardId: 'c1', title: '标题', content: '# 标题\n内容', order: 0, relatedQuestionIds: [1, 2], module: mod);
      mod.cards = [card];
      await pumpDetail(t, card, [mod]);
      expect(find.widgetWithText(ActionChip, '#1'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '#2'), findsOneWidget);
      expect(find.widgetWithText(Chip, '#1'), findsNothing);
    });

    testWidgets('点击芯片导航到 suffix QuizSessionView', (t) async {
      final mod = StudyModule(id: 1, name: '模块1', order: 1, cards: []);
      final card = StudyCard(cardId: 'c1', title: '标题', content: '# 标题\n内容', order: 0, relatedQuestionIds: [1, 2], module: mod);
      mod.cards = [card];
      await pumpDetail(t, card, [mod]);
      await t.tap(find.widgetWithText(ActionChip, '#1'));
      await t.pumpAndSettle();
      final vs = t.widget<QuizSessionView>(find.byType(QuizSessionView));
      expect(vs.questionIds, [1, 2], reason: '#1 应 suffix [1,2]，提交后显示 下一题 而非 查看结果');
      expect(find.byType(QuizSessionView), findsOneWidget);
    });

    testWidgets('点击末题芯片 suffix 为单题', (t) async {
      final mod = StudyModule(id: 1, name: '模块1', order: 1, cards: []);
      final card = StudyCard(cardId: 'c1', title: '标题', content: '# 标题\n内容', order: 0, relatedQuestionIds: [1, 2], module: mod);
      mod.cards = [card];
      await pumpDetail(t, card, [mod]);
      await t.tap(find.widgetWithText(ActionChip, '#2'));
      await t.pumpAndSettle();
      final vs = t.widget<QuizSessionView>(find.byType(QuizSessionView));
      expect(vs.questionIds, [2]);
    });

    testWidgets('逐题 已提交→下一题，末题才 会话已结束', (t) async {
      final mod = StudyModule(id: 1, name: '模块1', order: 1, cards: []);
      final card = StudyCard(cardId: 'c1', title: '标题', content: '# 标题\n内容', order: 0, relatedQuestionIds: [1, 2], module: mod);
      mod.cards = [card];
      final qs = [
        Question(id: 1, typeRaw: 'single', stem: '题干1', options: [QuizOption(key: 'A', text: 'a'), QuizOption(key: 'B', text: 'b')], answer: 'A', explanation: '解析1', bucketIndex: 0),
        Question(id: 2, typeRaw: 'single', stem: '题干2', options: [QuizOption(key: 'A', text: 'a'), QuizOption(key: 'B', text: 'b')], answer: 'A', explanation: '解析2', bucketIndex: 0),
      ];
      await t.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(_FakeDb(qs)),
          allStudyModulesProvider.overrideWith((ref) async => [mod]),
          allQuestionsProvider.overrideWith((ref) async => qs),
          allStudyCardsProvider.overrideWith((ref) async => [card]),
          allAnswerLogsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(home: StudyCardDetailView(initialCard: card, allModules: [mod])),
      ));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ActionChip, '#1'));
      await t.pumpAndSettle();
      // 第1题提交
      await t.tap(find.text('a').first);
      await t.pumpAndSettle();
      expect(find.text('下一题'), findsOneWidget, reason: '2题会话第1题提交后应为 下一题');
      expect(find.text('查看结果'), findsNothing);
      await t.tap(find.text('下一题'));
      await t.pumpAndSettle();
      expect(find.text('题干2'), findsOneWidget);
      // 第2题提交
      await t.tap(find.text('a').first);
      await t.pumpAndSettle();
      expect(find.text('查看结果'), findsOneWidget, reason: '末题提交后才 查看结果');
    });

    testWidgets('cardJump 结果页为 完成/下一张卡片 而非 再练一次', (t) async {
      final qs = [
        Question(id: 1, typeRaw: 'single', stem: '题干1', options: [QuizOption(key: 'A', text: 'a')], answer: 'A', explanation: '解析', bucketIndex: 0),
      ];
      await t.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(_FakeDb(qs))],
        child: MaterialApp(home: QuizSessionView(questionIds: [1], title: '标题', sourceRaw: 'cardJump', injectedQuestions: qs)),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('a'));
      await t.pumpAndSettle();
      await t.tap(find.text('查看结果'));
      await t.pumpAndSettle();
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('下一张卡片'), findsOneWidget);
      expect(find.text('再练一次'), findsNothing);
    });

    testWidgets('非 cardJump 结果页仍为 再练一次', (t) async {
      final qs = [
        Question(id: 1, typeRaw: 'single', stem: '题干1', options: [QuizOption(key: 'A', text: 'a')], answer: 'A', explanation: '解析', bucketIndex: 0),
      ];
      await t.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(_FakeDb(qs))],
        child: MaterialApp(home: QuizSessionView(questionIds: [1], title: '标题', sourceRaw: 'browse', injectedQuestions: qs)),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('a'));
      await t.pumpAndSettle();
      await t.tap(find.text('查看结果'));
      await t.pumpAndSettle();
      expect(find.text('再练一次'), findsOneWidget);
      expect(find.text('下一张卡片'), findsNothing);
    });
  });
}

class _FakeDb extends AppDatabase {
  final List<Question> fakeQuestions;
  _FakeDb(this.fakeQuestions) : super.forTesting(NativeDatabase.memory());
  @override
  Future<List<DbQuestion>> get allQuestions async => fakeQuestions
      .map((q) => DbQuestion(
            id: q.id,
            typeRaw: q.typeRaw,
            stem: q.stem,
            options: q.options.map((o) => {'key': o.key, 'text': o.text}).toList(),
            answer: q.answer,
            explanation: q.explanation,
            moduleId: q.moduleId,
            bucketIndex: q.bucketIndex,
            phase: q.phase,
            nextReviewDate: q.nextReviewDate,
            lastAnsweredAt: q.lastAnsweredAt,
            timesCorrect: q.timesCorrect,
            timesWrong: q.timesWrong,
            isFavorite: q.isFavorite,
          ))
      .toList();
  @override
  Future<List<DbStudyCard>> get allCards async => [];
  @override
  Future<List<DbStudyModule>> get allModules async => [];
}
