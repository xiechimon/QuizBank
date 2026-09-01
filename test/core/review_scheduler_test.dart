import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/core/review_scheduler.dart';

void main(){
  DateTime d0 = DateTime(2026,9,1);
  DateTime day(int off)=> d0.add(Duration(days: off));
  group('ReviewScheduler',(){
    test('首答对 phase1 明天',(){
      final r = ReviewScheduler.transit(phase:0, correct:true, today:d0);
      expect(r.phase,1);
      expect(r.next, day(1));
    });
    test('首答错重置明天',(){
      final r = ReviewScheduler.transit(phase:0, correct:false, today:d0);
      expect(r.phase,0);
      expect(r.next, day(1));
    });
    test('逐级 1 2 4 7 15',(){
      var phase=0; var today=d0;
      for(final gap in [1,2,4,7,15]){
        final r= ReviewScheduler.transit(phase:phase, correct:true, today:today);
        expect(r.phase, phase+1);
        expect(r.next, today.add(Duration(days:gap)));
        phase=r.phase; today=r.next!;
      }
      expect(phase,5);
    });
    test('第五次答对掌握 nil',(){
      final r= ReviewScheduler.transit(phase:5, correct:true, today:d0);
      expect(r.phase,6); expect(r.next, isNull);
    });
    test('已掌握答错回退',(){
      final r= ReviewScheduler.transit(phase:6, correct:false, today:d0);
      expect(r.phase,0); expect(r.next, day(1));
    });
    test('isDue 本期',(){
      expect(ReviewScheduler.isDue(phase:1, next:d0, today:d0), isTrue);
      expect(ReviewScheduler.isDue(phase:1, next:day(-1), today:d0), isTrue);
      expect(ReviewScheduler.isDue(phase:1, next:day(1), today:d0), isFalse);
      expect(ReviewScheduler.isDue(phase:6, next:d0, today:d0), isFalse);
      expect(ReviewScheduler.isDue(phase:0, next:null, today:d0), isFalse);
    });
  });
}
