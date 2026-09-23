import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/data/database.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/data/providers.dart';
import 'package:quiz_bank/features/cards/card_content_view.dart';
import 'package:quiz_bank/features/cards/study_home_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验收：卡片详情页键盘缩放（用户反馈 #2）
/// 契约：通过 Ctrl+= 放大 / Ctrl+- 缩小 / Ctrl+0 重置，
/// 作用于卡片内容祖先 MediaQuery 的 textScaler（步长 0.1，范围 [0.5, 3.0]）。
void main() {
  group('卡片键盘缩放', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pumpDetail(WidgetTester t, {required StudyCard card, required List<StudyModule> mods}) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(_FakeDb()),
          allStudyModulesProvider.overrideWith((ref) async => mods),
        ],
        child: MaterialApp(home: StudyCardDetailView(initialCard: card, allModules: mods)),
      ));
      await t.pumpAndSettle();
    }

    (StudyCard, List<StudyModule>) sample({int modules = 1, int cards = 2}) {
      final mods = <StudyModule>[];
      StudyCard? first;
      for (var mi = 0; mi < modules; mi++) {
        final m = StudyModule(id: mi + 1, name: '模块${mi + 1}', order: mi + 1);
        final cs = <StudyCard>[];
        for (var ci = 0; ci < cards; ci++) {
          final c = StudyCard(
            cardId: 'c$mi-$ci',
            title: '卡片$mi-$ci',
            content: '# 标题$mi-$ci\n正文段落内容$mi-$ci，用于缩放观察。',
            order: ci,
            relatedQuestionIds: [],
            module: m,
          );
          cs.add(c);
          first ??= c;
        }
        m.cards = cs;
        mods.add(m);
      }
      return (first!, mods);
    }

    Future<void> ctrl(WidgetTester t, LogicalKeyboardKey key) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(key);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
    }

    double scaleOf(WidgetTester t) {
      final el = t.element(find.byType(CardContentView).first);
      return MediaQuery.of(el).textScaler.scale(10) / 10;
    }

    testWidgets('缩放: Ctrl+= 放大卡片字体', (t) async {
      final (card, mods) = sample();
      await pumpDetail(t, card: card, mods: mods);
      expect(scaleOf(t), closeTo(1.0, 0.001));
      await ctrl(t, LogicalKeyboardKey.equal);
      expect(scaleOf(t), closeTo(1.1, 0.01), reason: 'Ctrl+= 应放大一档');
    });

    testWidgets('缩放: Ctrl+- 缩小，Ctrl+0 重置', (t) async {
      final (card, mods) = sample();
      await pumpDetail(t, card: card, mods: mods);
      await ctrl(t, LogicalKeyboardKey.equal);
      await ctrl(t, LogicalKeyboardKey.equal);
      expect(scaleOf(t), closeTo(1.2, 0.01));
      await ctrl(t, LogicalKeyboardKey.minus);
      expect(scaleOf(t), closeTo(1.1, 0.01));
      await ctrl(t, LogicalKeyboardKey.digit0);
      expect(scaleOf(t), closeTo(1.0, 0.001), reason: 'Ctrl+0 应重置为 1.0');
    });

    testWidgets('缩放: 倍数有上下限保护', (t) async {
      final (card, mods) = sample();
      await pumpDetail(t, card: card, mods: mods);
      for (var i = 0; i < 30; i++) {
        await ctrl(t, LogicalKeyboardKey.equal);
      }
      expect(scaleOf(t), closeTo(3.0, 0.001), reason: '放大应封顶 3.0');
      await ctrl(t, LogicalKeyboardKey.digit0);
      for (var i = 0; i < 30; i++) {
        await ctrl(t, LogicalKeyboardKey.minus);
      }
      expect(scaleOf(t), closeTo(0.5, 0.001), reason: '缩小应保底 0.5');
    });

    testWidgets('缩放: 翻页后缩放保持', (t) async {
      final (card, mods) = sample();
      await pumpDetail(t, card: card, mods: mods);
      await ctrl(t, LogicalKeyboardKey.equal);
      expect(scaleOf(t), closeTo(1.1, 0.01));
      await t.tap(find.text('下一张'));
      await t.pumpAndSettle();
      expect(scaleOf(t), closeTo(1.1, 0.01), reason: '翻到下一张应保持缩放倍数');
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
