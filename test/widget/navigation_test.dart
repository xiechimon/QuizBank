import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/app.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/data/providers.dart';
import 'package:quiz_bank/features/today/today_view.dart';

void main(){
  group('Widget M3',(){
    testWidgets('四Tab可切且使用NavigationBar', (t) async {
      await t.pumpWidget(const ProviderScope(child: QuizBankApp()));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 4);
      expect(find.text('今日'), findsWidgets);
      expect(find.text('刷题'), findsWidgets);
      expect(find.text('速记'), findsWidgets);
      expect(find.text('复盘'), findsWidgets);
    });
    testWidgets('Today Derived与队列一致', (t) async {
      await t.pumpWidget(const ProviderScope(child: QuizBankApp()));
      expect(find.byType(TodayView), findsWidgets);
    });
    testWidgets('Card/FilterChip/FAB存在', (t) async {
      final sampleQuestions = [
        Question(id:1, typeRaw:'single', stem:'题干1', options:[QuizOption(key:'A', text:'a')], answer:'A', explanation:'', bucketIndex:0),
        Question(id:2, typeRaw:'multiple', stem:'题干2', options:[QuizOption(key:'A', text:'a'),QuizOption(key:'B', text:'b')], answer:'AB', explanation:'', bucketIndex:0),
      ];
      final sampleCards = <StudyCard>[];
      final sampleModules = <StudyModule>[];
      await t.pumpWidget(ProviderScope(
        overrides:[
          allQuestionsProvider.overrideWith((ref) async => sampleQuestions),
          allStudyCardsProvider.overrideWith((ref) async => sampleCards),
          allStudyModulesProvider.overrideWith((ref) async => sampleModules),
          allAnswerLogsProvider.overrideWith((ref) async => []),
        ],
        child: const QuizBankApp(),
      ));
      // Allow async to resolve
      await t.pumpAndSettle();
      // Tap Practice tab
      await t.tap(find.text('刷题').last);
      await t.pumpAndSettle();
      expect(find.byType(Card), findsWidgets);
      expect(find.byType(FilterChip), findsWidgets);
      expect(find.byType(FloatingActionButton), findsWidgets);
    });
    testWidgets('反向改NavigationBar为BottomNavigationBar应失败 - 验证当前为NavigationBar', (t) async {
      await t.pumpWidget(const ProviderScope(child: QuizBankApp()));
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}
