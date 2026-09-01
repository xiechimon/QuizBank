import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/core/daily_plan.dart';

void main(){
  group('DailyPlan',(){
    test('分桶边界',(){
      expect(DailyPlan.bucketOf(1),0);
      expect(DailyPlan.bucketOf(39),0);
      expect(DailyPlan.bucketOf(40),1);
      expect(DailyPlan.bucketOf(78),1);
      expect(DailyPlan.bucketOf(79),2);
      expect(DailyPlan.bucketOf(1170),29);
      expect(DailyPlan.bucketOf(9999),29);
    });
    test('每桶39题',(){
      for(var b=0;b<30;b++) {
        expect(DailyPlan.idsOf(b).length,39);
      }
      expect(DailyPlan.idsOf(0).first,1);
      expect(DailyPlan.idsOf(29).last,1170);
    });
    test('步进制当天序号',(){
      expect(DailyPlan.currentDay({}),1);
      final bucket0 = Set<int>.from(DailyPlan.idsOf(0));
      expect(DailyPlan.currentDay(bucket0),2);
      final half = Set<int>.from(DailyPlan.idsOf(0).take(20));
      expect(DailyPlan.currentDay(half),1);
      expect(DailyPlan.currentDay(Set.from(List.generate(1170,(i)=>i+1))),30);
    });
    test('复习队列排序截断',(){
      final now= DateTime(2026,9,1);
      final due=[
        DueItem(id:101, next:now.subtract(Duration(days:3)), wrongs:1),
        DueItem(id:102, next:now.subtract(Duration(days:5)), wrongs:0),
        DueItem(id:103, next:now, wrongs:9),
        DueItem(id:104, next:now.add(Duration(days:1)), wrongs:0),
      ];
      expect(DailyPlan.reviewQueue(due,80),[102,101,103,104]);
      expect(DailyPlan.reviewQueue(due,2),[102,101]);
    });
    test('稳定乱序确定性',(){
      final ids= List.generate(39,(i)=>i+1);
      final a= DailyPlan.stableShuffle(ids,5);
      final b= DailyPlan.stableShuffle(ids,5);
      expect(a,b);
      final c= DailyPlan.stableShuffle(ids,6);
      expect(a, isNot(equals(c)));
      expect(Set.from(a), Set.from(ids));
    });
  });
}
