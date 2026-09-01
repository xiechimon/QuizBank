import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/core/quiz_session_controller.dart';

List<Question> makeQs(){
  final q1= Question(id:1, typeRaw:'single', stem:'单选', options:[QuizOption(key:'A',text:'对'),QuizOption(key:'B',text:'错')], answer:'A', explanation:'', bucketIndex:0);
  final q2= Question(id:2, typeRaw:'multiple', stem:'多选', options:[QuizOption(key:'A',text:'1'),QuizOption(key:'B',text:'2'),QuizOption(key:'C',text:'3')], answer:'AB', explanation:'', bucketIndex:0);
  final q3= Question(id:3, typeRaw:'judge', stem:'判断', options:[], answer:'T', explanation:'', bucketIndex:0);
  return [q1,q2,q3];
}
void main(){
  group('QuizSessionController',(){
    test('单选答对落库phase1',(){
      final qs= makeQs();
      final c= QuizSessionController(questions:[qs[0]], source:AnswerSource.browse);
      c.submitSingle('A');
      expect(c.submitted,true); expect(c.lastCorrect,true);
      expect(qs[0].timesCorrect,1); expect(qs[0].phase,1);
      c.next(); expect(c.isFinished,true);
    });
    test('多选漏选判错重置',(){
      final qs= makeQs();
      final c= QuizSessionController(questions:[qs[1]], source:AnswerSource.browse);
      c.toggleMulti('A'); c.toggleMulti('B');
      c.submitMulti(); expect(c.lastCorrect,true);
      expect(qs[1].phase,1);
      final c2= QuizSessionController(questions:[qs[1]], source:AnswerSource.review);
      c2.toggleMulti('A'); c2.submitMulti();
      expect(c2.lastCorrect,false); expect(qs[1].phase,0);
    });
    test('判断答错',(){
      final qs= makeQs();
      final c= QuizSessionController(questions:[qs[2]], source:AnswerSource.todayNew);
      c.submitJudge(false);
      expect(c.lastCorrect,false); expect(c.lastChosen,'F');
    });
    test('完成态统计',(){
      final qs= makeQs();
      final c= QuizSessionController(questions:[qs[0]], source:AnswerSource.browse);
      c.submitSingle('A'); c.next();
      expect(c.correctCount,1); expect(c.wrongCount,0);
    });
  });
}
