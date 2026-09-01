import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/core/topic_progress.dart';
import 'package:quiz_bank/features/today/today_view.dart';

StudyModule mod(int id,String name,int order)=> StudyModule(id:id,name:name,order:order);
StudyCard card(String cid,String title,int order,List<int> qids,TopicStatus s,DateTime? next,StudyModule m){
  final c= StudyCard(cardId:cid, title:title, content:'x', order:order, relatedQuestionIds:qids, module:m);
  c.storedStatusRaw=s.raw; if(s==TopicStatus.passed) c.consolidationRound=1; c.nextReviewDate=next; return c;
}
List<Question> qs(List<int> ids)=> ids.map((id)=> Question(id:id,typeRaw:'single',stem:'s\$id',options:[QuizOption(key:'A',text:'a')],answer:'A',explanation:'',bucketIndex:0)).toList();

void main(){
  final d0= DateTime(2026,9,1);
  DateTime day(int o)=> d0.add(Duration(days:o));
  group('TodayQueue',(){
    test('due优先逾期排序',(){
      final m= mod(1,'M1',0);
      final c1= card('c1','卡1',0,[1,2],TopicStatus.passed,day(-3),m);
      final c2= card('c2','卡2',1,[3],TopicStatus.passed,day(0),m);
      final c3= card('c3','卡3',2,[4],TopicStatus.passed,day(-1),m);
      m.cards=[c1,c2,c3];
      final d= Derived.compute(allCards:[c1,c2,c3], today:d0);
      expect(d.dueCards.map((e)=>e.cardId).toList(), ['c1','c3','c2']);
    });
    test('新学填充到40',(){
      final m= mod(1,'M1',0);
      final due= card('due1','到期',0,List.generate(10,(i)=>i+1),TopicStatus.passed,day(0),m);
      final n1= card('n1','新1',1,List.generate(10,(i)=>11+i),TopicStatus.new_,null,m);
      final n2= card('n2','新2',2,List.generate(10,(i)=>21+i),TopicStatus.learning,null,m);
      final n3= card('n3','新3',3,List.generate(10,(i)=>31+i),TopicStatus.new_,null,m);
      final n4= card('n4','新4',4,List.generate(10,(i)=>41+i),TopicStatus.new_,null,m);
      m.cards=[due,n1,n2,n3,n4];
      final d= Derived.compute(allCards:[due,n1,n2,n3,n4], today:d0);
      expect(d.dueCards.length,1);
      expect(d.newCards.map((e)=>e.cardId).toList(), ['n1','n2','n3']);
      expect(d.totalQuestionsCount,40);
    });
    test('巩固超40不推新',(){
      final m= mod(1,'M1',0);
      final d1= card('d1','1',0,List.generate(15,(i)=>i+1),TopicStatus.passed,day(0),m);
      final d2= card('d2','2',1,List.generate(15,(i)=>16+i),TopicStatus.passed,day(-1),m);
      final d3= card('d3','3',2,List.generate(15,(i)=>31+i),TopicStatus.passed,day(-2),m);
      final n1= card('n1','新',3,List.generate(15,(i)=>46+i),TopicStatus.new_,null,m);
      m.cards=[d1,d2,d3,n1];
      final d= Derived.compute(allCards:[d1,d2,d3,n1], today:d0);
      expect(d.dueCards.length,3); expect(d.newCards.isEmpty,true); expect(d.totalQuestionsCount,45);
    });
    test('毕业卡排除',(){
      final m= mod(1,'M1',0);
      final grad= card('g1','毕业',0,[1],TopicStatus.graduated,null,m)..consolidationRound=3;
      final passed= card('p1','未到期',1,[2],TopicStatus.passed,day(5),m);
      final n1= card('n1','新',2,[3],TopicStatus.new_,null,m);
      m.cards=[grad,passed,n1];
      final d= Derived.compute(allCards:[grad,passed,n1], today:d0);
      expect(d.dueCards.isEmpty,true);
      expect(d.newCards.map((e)=>e.cardId), ['n1']);
    });
  });
}
