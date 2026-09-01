import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/core/grader.dart';

void main(){
  group('Grader',(){
    test('单选判分大小写',(){
      expect(Grader.isCorrect(chosen:['A'], answer:'A'), isTrue);
      expect(Grader.isCorrect(chosen:['B'], answer:'A'), isFalse);
      expect(Grader.isCorrect(chosen:['a'], answer:'A'), isTrue);
    });
    test('多选集合精确相等',(){
      expect(Grader.isCorrect(chosen:['A','B','D'], answer:'ABD'), isTrue);
      expect(Grader.isCorrect(chosen:['D','B','A'], answer:'ABD'), isTrue);
      expect(Grader.isCorrect(chosen:['A','B'], answer:'ABD'), isFalse);
      expect(Grader.isCorrect(chosen:['A','B','C','D'], answer:'ABD'), isFalse);
      expect(Grader.isCorrect(chosen:['A'], answer:'ABD'), isFalse);
    });
    test('判断判分',(){
      expect(Grader.isCorrectJudge(chosen:true, answer:'T'), isTrue);
      expect(Grader.isCorrectJudge(chosen:false, answer:'F'), isTrue);
      expect(Grader.isCorrectJudge(chosen:true, answer:'F'), isFalse);
    });
    test('归一化排序',(){
      expect(Grader.normalize(['C','A']), 'AC');
      expect(Grader.normalize(['e','b']), 'BE');
      expect(Grader.normalizeJudge(true), 'T');
    });
    test('多选包含即对应判错 - 反向用',(){
      // 正确实现要求集合精确相等，包含即对应变红
      // 模拟错误实现：chosen包含answer即对 会在多选部分判错
      // 这里验证正确逻辑：AB 包含于 ABD 不应算对
      expect(Grader.isCorrect(chosen:['A','B'], answer:'ABD'), isFalse);
    });
  });
}
