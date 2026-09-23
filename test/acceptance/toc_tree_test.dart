import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/app.dart';
import 'package:quiz_bank/data/database.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/data/providers.dart';
import 'package:quiz_bank/features/cards/study_home_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验收：速记首页目录树（用户反馈 #1）
/// 期望行为：
///  - 17 模块作为一级知识点，默认收起，不再平铺全部卡片
///  - 点一级展开显示其下小知识点（卡片），点卡片直达该卡详情
///  - 展开状态在 tab 切换与应用重启后保留（不再每次从头开始）
void main() {
  group('速记目录树', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    List<StudyModule> sampleModules() {
      final m1 = StudyModule(id: 1, name: '模块一', order: 1);
      final m2 = StudyModule(id: 2, name: '模块二', order: 2);
      final a1 = StudyCard(cardId: 'a1', title: '卡片A1', content: '# 标题\n内容A1', order: 0, relatedQuestionIds: [], module: m1);
      final a2 = StudyCard(cardId: 'a2', title: '卡片A2', content: '# 标题\n内容A2', order: 1, relatedQuestionIds: [], module: m1);
      final b1 = StudyCard(cardId: 'b1', title: '卡片B1', content: '# 标题\n内容B1', order: 0, relatedQuestionIds: [], module: m2);
      final b2 = StudyCard(cardId: 'b2', title: '卡片B2', content: '# 标题\n内容B2', order: 1, relatedQuestionIds: [], module: m2);
      m1.cards = [a1, a2];
      m2.cards = [b1, b2];
      return [m1, m2];
    }

    Widget homeOnly(List<StudyModule> mods) => ProviderScope(
          overrides: [
            allStudyModulesProvider.overrideWith((ref) async => mods),
          ],
          child: const MaterialApp(home: StudyHomeView()),
        );

    testWidgets('TOC: 速记首页默认收起，只见一级知识点', (t) async {
      final mods = sampleModules();
      await t.pumpWidget(homeOnly(mods));
      await t.pumpAndSettle();
      expect(find.text('模块一'), findsOneWidget);
      expect(find.text('模块二'), findsOneWidget);
      expect(find.text('卡片A1'), findsNothing, reason: '收起时不应平铺小知识点');
    });

    testWidgets('TOC: 点一级知识点展开其下小知识点', (t) async {
      final mods = sampleModules();
      await t.pumpWidget(homeOnly(mods));
      await t.pumpAndSettle();
      expect(find.text('卡片A1'), findsNothing);
      await t.tap(find.text('模块一'));
      await t.pumpAndSettle();
      expect(find.text('卡片A1'), findsOneWidget);
      expect(find.text('卡片A2'), findsOneWidget);
      expect(find.text('卡片B1'), findsNothing, reason: '模块二应保持收起');
    });

    testWidgets('TOC: 点小知识点直达该卡详情', (t) async {
      final mods = sampleModules();
      await t.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(_FakeDb()),
          allStudyModulesProvider.overrideWith((ref) async => mods),
        ],
        child: const MaterialApp(home: StudyHomeView()),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('模块一'));
      await t.pumpAndSettle();
      await t.tap(find.text('卡片A2'));
      await t.pumpAndSettle();
      expect(find.byType(StudyCardDetailView), findsOneWidget);
      expect(find.text('2 / 4'), findsOneWidget, reason: '应定位到所点卡片（全序 a1,a2,b1,b2 中第 2 张），而非从第 1 张开始');
    });

    testWidgets('TOC: 切 tab 后展开状态保留', (t) async {
      final mods = sampleModules();
      await t.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(_FakeDb()),
          allStudyModulesProvider.overrideWith((ref) async => mods),
          allQuestionsProvider.overrideWith((ref) async => <Question>[]),
          allStudyCardsProvider.overrideWith((ref) async => mods.expand((m) => m.cards).toList()),
          allAnswerLogsProvider.overrideWith((ref) async => <AnswerLog>[]),
        ],
        child: const QuizBankApp(),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('速记').last);
      await t.pumpAndSettle();
      await t.tap(find.text('模块一'));
      await t.pumpAndSettle();
      expect(find.text('卡片A1'), findsOneWidget);
      expect(find.text('卡片B1'), findsNothing, reason: '模块二应保持收起');
      await t.tap(find.text('今日').last);
      await t.pumpAndSettle();
      await t.tap(find.text('速记').last);
      await t.pumpAndSettle();
      expect(find.text('卡片A1'), findsOneWidget, reason: '切 tab 回来应记住展开状态');
      expect(find.text('卡片B1'), findsNothing, reason: '切 tab 回来模块二仍应收起');
    });

    testWidgets('TOC: 重启应用后展开状态保留', (t) async {
      final mods = sampleModules();
      await t.pumpWidget(homeOnly(mods));
      await t.pumpAndSettle();
      await t.tap(find.text('模块一'));
      await t.pumpAndSettle();
      expect(find.text('卡片A1'), findsOneWidget);
      expect(find.text('卡片B1'), findsNothing, reason: '模块二应保持收起');
      // 模拟重启：全新 ProviderScope + StudyHomeView，共享同一 SharedPreferences mock
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(homeOnly(sampleModules()));
      await t.pumpAndSettle();
      expect(find.text('卡片A1'), findsOneWidget, reason: '重启后应恢复展开状态');
      expect(find.text('卡片B1'), findsNothing, reason: '重启后模块二仍应收起');
    });
  });
}

class _FakeDb extends AppDatabase {
  _FakeDb() : super.forTesting(NativeDatabase.memory());
  @override
  Future<List<DbQuestion>> get allQuestions async => [];
  @override
  Future<List<DbStudyCard>> get allCards async => [];
  @override
  Future<List<DbStudyModule>> get allModules async => [];
}
