import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database.dart';
import 'models.dart';
import 'package:drift/drift.dart' as drift;

class BankImporter {
  static const bucketSize = 39;
  static const bucketCount = 30;
  static const _questionsHashKey = 'bank.questions.hash';
  static const _notesHashKey = 'bank.notes.hash';

  static Future<void> importIfNeeded(AppDatabase db) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await rootBundle.loadString('assets/data/questions.json');
    final hash = sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
    if (prefs.getString(_questionsHashKey) == hash) return;
    final List decoded = jsonDecode(raw) as List;
    final dtos = decoded.map((e) => QuestionDto.fromJson(e as Map<String, dynamic>)).toList();
    await upsertDtos(dtos, db);
    await prefs.setString(_questionsHashKey, hash);
  }

  static Future<void> importStudyNotesIfNeeded(AppDatabase db) async {
    final prefs = await SharedPreferences.getInstance();
    String raw;
    try {
      raw = await rootBundle.loadString('assets/data/study_notes.json');
    } catch (_) {
      return;
    }
    final hash = sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
    if (prefs.getString(_notesHashKey) == hash) return;
    final List decoded = jsonDecode(raw) as List;
    await upsertNotes(decoded, db);
    await prefs.setString(_notesHashKey, hash);
  }

  static Future<bool> importWithHashCheck({
    required String jsonString,
    required SharedPreferences prefs,
    required AppDatabase db,
    required String hashKey,
    required Future<void> Function(List<dynamic> decoded) importer,
  }) async {
    final hash = sha256.convert(utf8.encode(jsonString)).toString().substring(0, 16);
    if (prefs.getString(hashKey) == hash) return false;
    final decoded = jsonDecode(jsonString) as List;
    await importer(decoded);
    await prefs.setString(hashKey, hash);
    return true;
  }

  static Future<void> upsertDtos(List<QuestionDto> dtos, AppDatabase db) async {
    final existing = await db.select(db.questions).get();
    final byId = {for (final e in existing) e.id: e};
    await db.batch((batch) {
      for (final dto in dtos) {
        if (!['single', 'multiple', 'judge'].contains(dto.type)) continue;
        final normalized = dto.normalizedAnswer;
        final bucket = ((dto.id - 1) ~/ bucketSize).clamp(0, bucketCount - 1);
        final opts = (dto.options ?? []).map((e) => {'key': e.key, 'text': e.text}).toList();
        final existingRow = byId[dto.id];
        if (existingRow != null) {
          batch.update(
            db.questions,
            QuestionsCompanion(
              typeRaw: drift.Value(dto.type),
              stem: drift.Value(dto.stem),
              options: drift.Value(opts),
              answer: drift.Value(normalized),
              explanation: drift.Value(dto.explanation ?? ''),
            ),
            where: (t) => t.id.equals(dto.id),
          );
        } else {
          batch.insert(
            db.questions,
            QuestionsCompanion.insert(
              id: drift.Value(dto.id),
              typeRaw: dto.type,
              stem: dto.stem,
              options: opts,
              answer: normalized,
              explanation: dto.explanation ?? '',
              bucketIndex: bucket,
            ),
          );
        }
      }
    });
  }

  static Future<void> upsertPure(List<QuestionDto> dtos, List<Question> target) async {
    final byId = {for (final q in target) q.id: q};
    for (final dto in dtos) {
      if (!['single', 'multiple', 'judge'].contains(dto.type)) continue;
      final existing = byId[dto.id];
      final normalized = dto.normalizedAnswer;
      if (existing != null) {
        existing.typeRaw = dto.type;
        existing.stem = dto.stem;
        existing.options = dto.options ?? [];
        existing.answer = normalized;
        existing.explanation = dto.explanation ?? '';
      } else {
        final bucket = ((dto.id - 1) ~/ bucketSize).clamp(0, bucketCount - 1);
        final q = Question(
          id: dto.id,
          typeRaw: dto.type,
          stem: dto.stem,
          options: dto.options ?? [],
          answer: normalized,
          explanation: dto.explanation ?? '',
          bucketIndex: bucket,
        );
        target.add(q);
        byId[dto.id] = q;
      }
    }
  }

  static Future<void> upsertNotes(List<dynamic> decoded, AppDatabase db) async {
    final modules = await db.select(db.studyModules).get();
    final cards = await db.select(db.studyCards).get();
    final moduleIds = modules.map((e) => e.id).toSet();
    final cardIds = cards.map((e) => e.cardId).toSet();

    await db.batch((batch) {
      for (final raw in decoded) {
        final map = raw as Map<String, dynamic>;
        final moduleId = map['moduleId'] as int;
        final moduleName = map['moduleName'] as String;
        final order = map['order'] as int;
        final cardsRaw = map['cards'] as List? ?? [];
        if (!moduleIds.contains(moduleId)) {
          batch.insert(db.studyModules, StudyModulesCompanion.insert(id: drift.Value(moduleId), name: moduleName, sortOrder: order));
          moduleIds.add(moduleId);
        } else {
          batch.update(db.studyModules, StudyModulesCompanion(name: drift.Value(moduleName), sortOrder: drift.Value(order)),
              where: (t) => t.id.equals(moduleId));
        }
        for (var i = 0; i < cardsRaw.length; i++) {
          final c = cardsRaw[i] as Map<String, dynamic>;
          final cardId = c['cardId'] as String;
          final title = c['title'] as String;
          final content = c['content'] as String;
          final related = (c['relatedQuestionIds'] as List?)?.map((e) => (e as num).toInt()).toList() ?? <int>[];
          if (!cardIds.contains(cardId)) {
            batch.insert(
                db.studyCards,
                StudyCardsCompanion.insert(
                    cardId: cardId, title: title, content: content, sortOrder: i, relatedQuestionIds: related, moduleId: drift.Value(moduleId)));
            cardIds.add(cardId);
          } else {
            batch.update(
                db.studyCards,
                StudyCardsCompanion(
                    title: drift.Value(title),
                    content: drift.Value(content),
                    sortOrder: drift.Value(i),
                    relatedQuestionIds: drift.Value(related),
                    moduleId: drift.Value(moduleId)),
                where: (t) => t.cardId.equals(cardId));
          }
        }
      }
    });

    for (final raw in decoded) {
      final map = raw as Map<String, dynamic>;
      final moduleId = map['moduleId'] as int;
      final questionIdsRaw = map['questionIds'] as List?;
      final cardsRaw = map['cards'] as List? ?? [];
      final Set<int> ids = {};
      if (questionIdsRaw != null) ids.addAll(questionIdsRaw.map((e) => (e as num).toInt()));
      for (final c in cardsRaw) {
        final rel = (c as Map<String, dynamic>)['relatedQuestionIds'] as List?;
        if (rel != null) ids.addAll(rel.map((e) => (e as num).toInt()));
      }
      if (ids.isEmpty) {
        continue;
      }
      for (final qid in ids) {
        await (db.update(db.questions)..where((t) => t.id.equals(qid))).write(QuestionsCompanion(moduleId: drift.Value(moduleId)));
      }
    }
  }

  static void backfillPure(List<StudyModule> modules, List<Question> questions) {
    final qById = {for (final q in questions) q.id: q};
    for (final m in modules) {
      final ids = <int>{};
      for (final c in m.cards) {
        ids.addAll(c.relatedQuestionIds);
      }
      for (final id in ids) {
        final q = qById[id];
        if (q != null) {
          q.moduleId = m.id;
        }
      }
    }
  }
}

class QuestionDto {
  final int id;
  final String type;
  final String stem;
  final List<QuizOption>? options;
  final FlexibleAnswer answer;
  final String? explanation;
  QuestionDto({required this.id, required this.type, required this.stem, required this.options, required this.answer, this.explanation});
  factory QuestionDto.fromJson(Map<String, dynamic> j) {
    final rawAns = j['answer'];
    FlexibleAnswer fa;
    if (rawAns is bool) {
      fa = FlexibleAnswer.boolVal(rawAns);
    } else if (rawAns is List) {
      fa = FlexibleAnswer.letters(rawAns.map((e) => e.toString()).toList());
    } else if (rawAns is String) {
      fa = FlexibleAnswer.letters([rawAns]);
    } else {
      fa = FlexibleAnswer.letters([]);
    }
    final optsRaw = j['options'] as List?;
    List<QuizOption>? opts;
    if (optsRaw != null) opts = optsRaw.map((e) => QuizOption.fromJson(e as Map<String, dynamic>)).toList();
    return QuestionDto(
        id: (j['id'] as num).toInt(),
        type: j['type'] as String,
        stem: j['stem'] as String? ?? '',
        options: opts,
        answer: fa,
        explanation: j['explanation'] as String?);
  }
  String get normalizedAnswer {
    if (answer.boolValInner != null) return answer.boolValInner! ? 'T' : 'F';
    final list = (answer.letters ?? []).map((e) => e.toUpperCase()).toList()..sort();
    return list.join();
  }
}

class FlexibleAnswer {
  final List<String>? letters;
  final bool? boolValInner;
  FlexibleAnswer.letters(this.letters) : boolValInner = null;
  FlexibleAnswer.boolVal(this.boolValInner) : letters = null;
}
