import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/core/topic_progress.dart';
import 'package:quiz_bank/core/topic_scheduler.dart';

StudyCard makeCard(TopicStatus s,int round){
  final c= StudyCard(cardId:'${s.name}-$round', title:'t', content:'x', order:0, relatedQuestionIds:[1,2,3]);
  c.storedStatusRaw=s.raw; c.consolidationRound=round; return c;
}
void main(){
  final d0= DateTime(2026,9,1);
  DateTime day(int o)=> d0.add(Duration(days:o));
  group('TopicScheduler',(){
    test('learning全对晋升7天',(){
      final c= makeCard(TopicStatus.learning,0);
      final r= TopicScheduler.transit(card:c, sessionCorrect:true, today:d0);
      expect(r.status, TopicStatus.passed);
      expect(r.nextRound,1); expect(r.nextDate, day(7));
    });
    test('new全对同样',(){
      final c= makeCard(TopicStatus.new_,0);
      final r= TopicScheduler.transit(card:c, sessionCorrect:true, today:d0);
      expect(r.status, TopicStatus.passed);
    });
    test('未全对保持learning',(){
      final c= makeCard(TopicStatus.learning,0);
      final r= TopicScheduler.transit(card:c, sessionCorrect:false, today:d0);
      expect(r.status, TopicStatus.learning);
      expect(r.nextRound,0); expect(r.nextDate, isNull);
    });
    test('passed首次巩固进30天',(){
      final c= makeCard(TopicStatus.passed,1);
      final r= TopicScheduler.transit(card:c, sessionCorrect:true, today:d0);
      expect(r.status, TopicStatus.passed); expect(r.nextRound,2); expect(r.nextDate, day(30));
    });
    test('passed二次进90',(){
      final c= makeCard(TopicStatus.passed,2);
      final r= TopicScheduler.transit(card:c, sessionCorrect:true, today:d0);
      expect(r.nextRound,3); expect(r.nextDate, day(90));
    });
    test('三次毕业',(){
      final c= makeCard(TopicStatus.passed,3);
      final r= TopicScheduler.transit(card:c, sessionCorrect:true, today:d0);
      expect(r.status, TopicStatus.graduated); expect(r.nextDate, isNull);
    });
    test('round0迁移去重进30',(){
      final c= makeCard(TopicStatus.passed,0);
      final r= TopicScheduler.transit(card:c, sessionCorrect:true, today:d0);
      expect(r.nextRound,2); expect(r.nextDate, day(30));
    });
    test('巩固失败回退',(){
      for(final round in [0,1,2,3]){
        final c= makeCard(TopicStatus.passed,round);
        final r= TopicScheduler.transit(card:c, sessionCorrect:false, today:d0);
        expect(r.status, TopicStatus.learning);
      }
    });
    test('毕业答对保持答错回退',(){
      final g= makeCard(TopicStatus.graduated,3);
      expect(TopicScheduler.transit(card:g, sessionCorrect:true, today:d0).status, TopicStatus.graduated);
      expect(TopicScheduler.transit(card:g, sessionCorrect:false, today:d0).status, TopicStatus.learning);
    });
  });
}
