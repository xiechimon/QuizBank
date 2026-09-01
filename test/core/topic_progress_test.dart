import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/core/topic_progress.dart';

void main(){
  group('TopicProgress',(){
    test('状态推导累计制',(){
      expect(TopicProgress.statusFromCounts([]), TopicStatus.new_);
      expect(TopicProgress.statusFromCounts([0,0,0]), TopicStatus.new_);
      expect(TopicProgress.statusFromCounts([1,0,2]), TopicStatus.learning);
      expect(TopicProgress.statusFromCounts([1,3,2]), TopicStatus.passed);
    });
    test('单轮全对同会话全部对即通过',(){
      const sid='sess-1';
      final logs=[
        AnswerLog(date: DateTime.now(), questionID:1, chosen:'A', isCorrect:true, sourceRaw:'cardJump', sessionId:sid),
        AnswerLog(date: DateTime.now(), questionID:2, chosen:'B', isCorrect:true, sourceRaw:'cardJump', sessionId:sid),
        AnswerLog(date: DateTime.now(), questionID:3, chosen:'A', isCorrect:true, sourceRaw:'cardJump', sessionId:sid),
      ];
      expect(TopicProgress.isSingleRoundPassed(sessionLogs:logs, cardQuestionIds:{1,2,3}), isTrue);
    });
    test('有一错不通过',(){
      const sid='sess-1';
      final logs=[
        AnswerLog(date: DateTime.now(), questionID:1, chosen:'A', isCorrect:true, sourceRaw:'cardJump', sessionId:sid),
        AnswerLog(date: DateTime.now(), questionID:2, chosen:'B', isCorrect:false, sourceRaw:'cardJump', sessionId:sid),
      ];
      expect(TopicProgress.isSingleRoundPassed(sessionLogs:logs, cardQuestionIds:{1,2}), isFalse);
    });
    test('跨会话拼凑不算',(){
      final logs=[
        AnswerLog(date: DateTime.now(), questionID:1, chosen:'A', isCorrect:true, sourceRaw:'cardJump', sessionId:'s1'),
        AnswerLog(date: DateTime.now(), questionID:2, chosen:'B', isCorrect:true, sourceRaw:'cardJump', sessionId:'s2'),
      ];
      expect(TopicProgress.isSingleRoundPassed(sessionLogs:logs, cardQuestionIds:{1,2}), isFalse);
    });
    test('缺题不算',(){
      const sid='sess-1';
      final logs=[AnswerLog(date: DateTime.now(), questionID:1, chosen:'A', isCorrect:true, sourceRaw:'cardJump', sessionId:sid)];
      expect(TopicProgress.isSingleRoundPassed(sessionLogs:logs, cardQuestionIds:{1,2,3}), isFalse);
    });
    test('存储事实源读取',(){
      final card= StudyCard(cardId:'c1', title:'t', content:'x', order:0, relatedQuestionIds:[1,2]);
      expect(TopicProgress.statusOf(card), TopicStatus.new_);
      card.storedStatusRaw='passed';
      expect(TopicProgress.statusOf(card), TopicStatus.passed);
    });
  });
}
