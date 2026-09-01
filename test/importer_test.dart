import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/data/bank_importer.dart';
import 'package:quiz_bank/data/models.dart';
import 'package:quiz_bank/data/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Importer', () {
    test('导入1170题与答案归一', () async {
      final file = File('assets/data/questions.json');
      expect(file.existsSync(), isTrue, reason: 'questions.json should exist');
      final raw = file.readAsStringSync();
      final List decoded = jsonDecode(raw) as List;
      expect(decoded.length, 1170);
      final dtos = decoded.map((e) => QuestionDto.fromJson(e as Map<String, dynamic>)).toList();
      final multi = dtos.where((d) => d.type == 'multiple').firstWhere((_) => true, orElse: () => dtos.first);
      expect(multi.normalizedAnswer, equals(multi.normalizedAnswer.toUpperCase()));
    });

    test('分桶边界 39题一桶', () async {
      final list = <Question>[];
      final dtos = List.generate(80, (i) => QuestionDto(id: i + 1, type: 'single', stem: 's${i + 1}', options: [QuizOption(key: 'A', text: 'a')], answer: FlexibleAnswer.letters(['A']), explanation: ''));
      await BankImporter.upsertPure(dtos, list);
      Question by(int id) => list.firstWhere((q) => q.id == id);
      expect(by(1).bucketIndex, 0);
      expect(by(39).bucketIndex, 0);
      expect(by(40).bucketIndex, 1);
      expect(by(78).bucketIndex, 1);
      expect(by(79).bucketIndex, 2);
    });

    test('重导入保留学习进度', () async {
      final list = <Question>[];
      final dto1 = QuestionDto(id: 1, type: 'single', stem: '原题干', options: [QuizOption(key: 'A', text: 'a')], answer: FlexibleAnswer.letters(['A']), explanation: '');
      await BankImporter.upsertPure([dto1], list);
      final q = list.first;
      q.phase = 3;
      q.timesCorrect = 2;
      q.timesWrong = 1;
      q.isFavorite = true;

      final upgraded = QuestionDto(id: 1, type: 'single', stem: '新题干', options: [QuizOption(key: 'A', text: '新')], answer: FlexibleAnswer.letters(['B']), explanation: '新解析');
      await BankImporter.upsertPure([upgraded], list);
      expect(list.length, 1);
      expect(list.first.stem, '新题干');
      expect(list.first.answer, 'B');
      expect(list.first.phase, 3);
      expect(list.first.timesCorrect, 2);
      expect(list.first.timesWrong, 1);
      expect(list.first.isFavorite, isTrue);
    });

    test('FlexibleAnswer解码 bool与数组', () {
      final dtoJudgeTrue = QuestionDto.fromJson({'id': 1, 'type': 'judge', 'stem': 's', 'options': [], 'answer': true, 'explanation': ''});
      expect(dtoJudgeTrue.normalizedAnswer, 'T');
      final dtoMulti = QuestionDto.fromJson({'id': 2, 'type': 'multiple', 'stem': 's', 'options': [], 'answer': ['B', 'A'], 'explanation': ''});
      expect(dtoMulti.normalizedAnswer, 'AB');
    });

    test('hash不变跳过', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = '[{"id":1,"type":"single","stem":"s","options":[],"answer":["A"],"explanation":""}]';
      final first = await BankImporter.importWithHashCheck(jsonString: jsonStr, prefs: prefs, hashKey: 'test.hash', db: AppDatabase.inMemory(), importer: (decoded) async {});
      expect(first, isTrue);
      final second = await BankImporter.importWithHashCheck(jsonString: jsonStr, prefs: prefs, hashKey: 'test.hash', db: AppDatabase.inMemory(), importer: (decoded) async {
        fail('should not be called when hash unchanged');
      });
      expect(second, isFalse);
    });

    test('study_notes回填 moduleId', () async {
      final modules = [
        StudyModule(id: 1, name: 'm1', order: 0, cards: [
          StudyCard(cardId: 'c1', title: 't', content: 'x', order: 0, relatedQuestionIds: [1, 2]),
        ]),
      ];
      final questions = [
        Question(id: 1, typeRaw: 'single', stem: 's', options: [], answer: 'A', explanation: '', bucketIndex: 0),
        Question(id: 2, typeRaw: 'single', stem: 's', options: [], answer: 'A', explanation: '', bucketIndex: 0),
        Question(id: 3, typeRaw: 'single', stem: 's', options: [], answer: 'A', explanation: '', bucketIndex: 0),
      ];
      BankImporter.backfillPure(modules, questions);
      expect(questions[0].moduleId, 1);
      expect(questions[1].moduleId, 1);
      expect(questions[2].moduleId, isNull);
    });

    test('drift 1170导入与hash跳过', () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.inMemory();
      final file = File('assets/data/questions.json');
      final raw = file.readAsStringSync();
      final List decoded = jsonDecode(raw) as List;
      final dtos = decoded.map((e) => QuestionDto.fromJson(e as Map<String, dynamic>)).toList();
      await BankImporter.upsertDtos(dtos, db);
      final all = await db.allQuestions;
      expect(all.length, 1170);
      await (db.update(db.questions)..where((t) => t.id.equals(1))).write(QuestionsCompanion(phase: const Value(3), timesCorrect: const Value(2)));
      final dtos2 = [QuestionDto(id: 1, type: 'single', stem: 'new stem', options: [QuizOption(key: 'A', text: 'x')], answer: FlexibleAnswer.letters(['B']), explanation: 'new')];
      await BankImporter.upsertDtos(dtos2, db);
      final after = (await db.allQuestions).firstWhere((e) => e.id == 1);
      expect(after.stem, 'new stem');
      expect(after.answer, 'B');
      expect(after.phase, 3);
      expect(after.timesCorrect, 2);
      await db.close();
    });

    test('改一题题干hash变应更新 改回跳过', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.inMemory();
      const baseJson = '[{"id":1,"type":"single","stem":"s","options":[{"key":"A","text":"a"}],"answer":["A"],"explanation":""}]';
      const modifiedJson = '[{"id":1,"type":"single","stem":"s modified","options":[{"key":"A","text":"a"}],"answer":["A"],"explanation":""}]';
      await BankImporter.importWithHashCheck(jsonString: baseJson, prefs: prefs, hashKey: 'k1', db: db, importer: (d) async {
        final dtos = d.map((e) => QuestionDto.fromJson(e as Map<String, dynamic>)).toList();
        await BankImporter.upsertDtos(dtos, db);
      });
      var q = (await db.allQuestions).firstWhere((e) => e.id == 1);
      expect(q.stem, 's');
      await BankImporter.importWithHashCheck(jsonString: modifiedJson, prefs: prefs, hashKey: 'k1', db: db, importer: (d) async {
        final dtos = d.map((e) => QuestionDto.fromJson(e as Map<String, dynamic>)).toList();
        await BankImporter.upsertDtos(dtos, db);
      });
      q = (await db.allQuestions).firstWhere((e) => e.id == 1);
      expect(q.stem, 's modified');
      final skipped = await BankImporter.importWithHashCheck(jsonString: modifiedJson, prefs: prefs, hashKey: 'k1', db: db, importer: (d) async => fail('skip'));
      expect(skipped, isFalse);
      await db.close();
    });
  });
}
