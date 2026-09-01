import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/core/stats_calculator.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/core/topic_overview.dart';
import 'package:quiz_bank/core/topic_progress.dart';

void main(){
  final d0= DateTime(2026,9,1);
  DateTime day(int o)=> d0.add(Duration(days:o));
  group('StatsCalculator',(){
    test('mastery',(){
      final m= StatsCalculator.mastery([0,0,1,3,6,6]);
      expect(m.notStarted,2); expect(m.learning,2); expect(m.mastered,2);
    });
    test('typeStats',(){
      final s= StatsCalculator.typeStats([(type:QuestionType.single, total:10, correct:7)]);
      expect(s.first.accuracy, 0.7);
    });
    test('dailyCounts',(){
      final logs=[(date:day(0), isCorrect:true),(date:day(0), isCorrect:false),(date:day(-1), isCorrect:true)];
      final res= StatsCalculator.dailyCounts(logs:logs, days:2, today:d0);
      expect(res.length,2);
    });
    test('forecast & overdue',(){
      final due=[(next:day(0), phase:1),(next:day(1), phase:1)];
      final f= StatsCalculator.reviewForecast(due:due, days:2, today:d0);
      expect(f[0].count,1); expect(f[1].count,1);
      expect(StatsCalculator.overdue([(next:day(-1), phase:1)], d0),1);
    });
    test('topicStats转发',(){
      final q1= Question(id:1, typeRaw:'single', stem:'s', options:[], answer:'A', explanation:'', bucketIndex:0)..timesCorrect=1;
      final q2= Question(id:2, typeRaw:'single', stem:'s', options:[], answer:'A', explanation:'', bucketIndex:0)..timesCorrect=0;
      final m1= StudyModule(id:1, name:'M1', order:0);
      final c1= StudyCard(cardId:'c1', title:'t', content:'x', order:0, relatedQuestionIds:[1,2])..storedStatusRaw=TopicStatus.learning.raw;
      final c2= StudyCard(cardId:'c2', title:'t', content:'x', order:1, relatedQuestionIds:[2])..storedStatusRaw=TopicStatus.passed.raw..nextReviewDate=day(7)..consolidationRound=1;
      m1.cards=[c1,c2];
      final overview= TopicOverview.compute(modules:[m1], questions:[q1,q2]);
      final stats= StatsCalculator.topicStats(overview:overview);
      expect(stats.total,2); expect(stats.byModule.length,1);
    });
  });
}
