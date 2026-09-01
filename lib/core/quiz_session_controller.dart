import 'dart:math';
import '../data/models.dart';
import 'grader.dart';
import 'review_scheduler.dart';
import 'topic_progress.dart';
import 'topic_scheduler.dart';

class QuizSessionController {
  final List<Question> questions;
  final AnswerSource source;
  final String sessionId;

  int index = 0;
  final Set<int> answeredIds = {};
  int correctCount = 0;
  int wrongCount = 0;

  bool submitted = false;
  String lastChosen = '';
  bool lastCorrect = false;
  Set<String> pendingMulti = {};

  // For card convergence, we need access to all cards/logs via callbacks
  final List<StudyCard> Function()? allCardsProvider;
  final List<AnswerLog> Function()? allLogsProvider;
  final void Function(AnswerLog log)? logSaver;

  QuizSessionController({
    required this.questions,
    required this.source,
    String? sessionId,
    this.allCardsProvider,
    this.allLogsProvider,
    this.logSaver,
  }) : sessionId = sessionId ?? _uuid();

  static String _uuid() {
    final r = Random();
    return '${r.nextInt(1 << 32).toRadixString(16)}-${r.nextInt(1 << 32).toRadixString(16)}';
  }

  Question? get current => index < questions.length ? questions[index] : null;
  bool get isFinished => index >= questions.length;
  String get progressText => '${index.clamp(0, questions.length) + 1}/${questions.length}';

  void submitSingle(String key, {DateTime? now}) {
    final q = current;
    if (q == null || submitted) return;
    _apply(chosen: [key], question: q, now: now ?? DateTime.now());
  }

  void submitJudge(bool value, {DateTime? now}) {
    final q = current;
    if (q == null || submitted) return;
    _apply(chosen: [Grader.normalizeJudge(value)], question: q, now: now ?? DateTime.now());
  }

  void submitMulti({DateTime? now}) {
    final q = current;
    if (q == null || submitted || pendingMulti.isEmpty) return;
    _apply(chosen: pendingMulti.toList(), question: q, now: now ?? DateTime.now());
  }

  void toggleMulti(String key) {
    if (pendingMulti.contains(key)) {
      pendingMulti.remove(key);
    } else {
      pendingMulti.add(key);
    }
  }

  void next({DateTime? now}) {
    if (!submitted || index >= questions.length) return;
    index++;
    submitted = false;
    lastChosen = '';
    lastCorrect = false;
    pendingMulti = {};
    // Instead of requiring DB, we optionally call converge if providers available
    if (allCardsProvider != null && allLogsProvider != null) {
      _converge(now: now ?? DateTime.now());
      if (isFinished) _converge(now: now ?? DateTime.now());
    }
  }

  void nextWithContext({required List<StudyCard> allCards, required List<AnswerLog> allLogs, DateTime? now}) {
    if (!submitted || index >= questions.length) return;
    index++;
    submitted = false;
    lastChosen = '';
    lastCorrect = false;
    pendingMulti = {};
    _convergeWith(allCards: allCards, allLogs: allLogs, now: now ?? DateTime.now());
    if (isFinished) _convergeWith(allCards: allCards, allLogs: allLogs, now: now ?? DateTime.now());
  }

  void finalizeIfNeeded({required List<StudyCard> allCards, required List<AnswerLog> allLogs, DateTime? now}) {
    _convergeWith(allCards: allCards, allLogs: allLogs, now: now ?? DateTime.now());
  }

  void toggleFavorite() {
    current?.isFavorite = !(current?.isFavorite ?? false);
  }

  void _apply({required List<String> chosen, required Question question, required DateTime now}) {
    final normalized = Grader.normalizeJoined(chosen);
    final bool correct;
    if (question.type == QuestionType.judge) {
      correct = Grader.isCorrectJudge(chosen: normalized == 'T', answer: question.answer);
    } else {
      correct = Grader.isCorrect(chosen: chosen, answer: question.answer);
    }

    final todayStart = DateTime(now.year, now.month, now.day);
    question.lastAnsweredAt = now;
    if (correct) {
      question.timesCorrect += 1;
    } else {
      question.timesWrong += 1;
    }
    final transit = ReviewScheduler.transit(phase: question.phase, correct: correct, today: todayStart);
    question.phase = transit.phase;
    question.nextReviewDate = transit.next;

    final log = AnswerLog(
      date: now,
      questionID: question.id,
      chosen: normalized,
      isCorrect: correct,
      sourceRaw: source.raw,
      sessionId: sessionId,
      question: question,
    );
    logSaver?.call(log);
    // Also if we have allLogsProvider we store in memory? Caller handles.

    submitted = true;
    lastChosen = normalized;
    lastCorrect = correct;
    answeredIds.add(question.id);
    if (correct) {
      correctCount += 1;
    } else {
      wrongCount += 1;
    }
  }

  void _converge({required DateTime now}) {
    if (allCardsProvider == null || allLogsProvider == null) return;
    _convergeWith(allCards: allCardsProvider!(), allLogs: allLogsProvider!(), now: now);
  }

  void _convergeWith({required List<StudyCard> allCards, required List<AnswerLog> allLogs, required DateTime now}) {
    if (allCards.isEmpty) return;
    final sessionLogs = allLogs.where((l) => l.sessionId == sessionId).toList();
    if (sessionLogs.isEmpty) return;
    final sessionQuestionIds = sessionLogs.map((e) => e.questionID).toSet();
    final todayStart = DateTime(now.year, now.month, now.day);

    for (final card in allCards) {
      final cardQIDs = card.relatedQuestionIds.toSet();
      if (cardQIDs.isEmpty) continue;
      if (!cardQIDs.every((id) => sessionQuestionIds.contains(id))) continue;
      final cardSessionLogs = sessionLogs.where((l) => cardQIDs.contains(l.questionID)).toList();
      final sessionCorrect = TopicProgress.isSingleRoundPassed(sessionLogs: cardSessionLogs, cardQuestionIds: cardQIDs);
      if (card.lastSessionId == sessionId) {
        if (sessionCorrect && (card.storedStatusRaw == TopicStatus.passed.raw || card.storedStatusRaw == TopicStatus.graduated.raw)) {
          continue;
        }
        if (!sessionCorrect && card.storedStatusRaw == TopicStatus.learning.raw) continue;
      }
      final previousRaw = card.storedStatusRaw;
      final result = TopicScheduler.transit(card: card, sessionCorrect: sessionCorrect, today: todayStart);
      final statusChanged = result.status.raw != card.storedStatusRaw;
      final roundChanged = result.nextRound != card.consolidationRound;
      final dateChanged = result.nextDate != card.nextReviewDate;
      final needsUpdate = statusChanged || roundChanged || dateChanged || card.lastSessionId != sessionId;
      if (needsUpdate) {
        final prevStatus = TopicStatusX.fromRaw(previousRaw);
        card.storedStatusRaw = result.status.raw;
        card.consolidationRound = result.nextRound;
        card.nextReviewDate = result.nextDate;
        card.lastSessionId = sessionId;
        if (result.status == TopicStatus.passed && prevStatus != TopicStatus.passed && prevStatus != TopicStatus.graduated) {
          card.passedAt = todayStart;
        }
      }
    }
  }
}
