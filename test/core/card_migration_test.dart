import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/core/card_status_migration.dart';

Question q(int id,int corr,DateTime? last){
  final qq= Question(id:id,typeRaw:'single',stem:'s\$id',options:[QuizOption(key:'A',text:'a')],answer:'A',explanation:'',bucketIndex:0);
  qq.timesCorrect=corr; qq.lastAnsweredAt=last; return qq;
}
void main(){
  final d0= DateTime(2026,9,1);
  DateTime day(int o)=> d0.add(Duration(days:o));
  group('CardMigration',(){
    test('累计制已通过回填passed',(){
      final q1=q(1,1,day(-5)), q2=q(2,2,day(-1)), q3=q(3,1,day(-3));
      final m= StudyModule(id:1,name:'m',order:0);
      final c= StudyCard(cardId:'c1',title:'t',content:'x',order:0,relatedQuestionIds:[1,2,3],module:m);
      CardStatusMigration.backfillIfNeeded(cards:[c],questions:[q1,q2,q3],logs:[],today:d0);
      expect(c.storedStatusRaw,'passed'); expect(c.nextReviewDate, day(7));
    });
    test('幂等已回填不重复',(){
      final qq=q(1,1,day(-2));
      final m= StudyModule(id:1,name:'m',order:0);
      final c= StudyCard(cardId:'c3',title:'t',content:'x',order:0,relatedQuestionIds:[1],module:m);
      CardStatusMigration.backfillIfNeeded(cards:[c],questions:[qq],logs:[],today:d0);
      final first= c.passedAt; final firstNext= c.nextReviewDate;
      CardStatusMigration.backfillIfNeeded(cards:[c],questions:[qq],logs:[],today:day(10));
      expect(c.passedAt,first); expect(c.nextReviewDate,firstNext);
    });
    test('学习中不回填',(){
      final q1=q(1,1,day(-1)), q2=q(2,0,null);
      final m= StudyModule(id:1,name:'m',order:0);
      final c= StudyCard(cardId:'c4',title:'t',content:'x',order:0,relatedQuestionIds:[1,2],module:m);
      CardStatusMigration.backfillIfNeeded(cards:[c],questions:[q1,q2],logs:[],today:d0);
      expect(c.storedStatusRaw,'new');
    });
  });
}
