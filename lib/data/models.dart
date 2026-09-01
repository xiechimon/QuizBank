class QuizOption {
  final String key;
  final String text;
  const QuizOption({required this.key, required this.text});

  factory QuizOption.fromJson(Map<String, dynamic> j) =>
      QuizOption(key: j['key'] as String, text: j['text'] as String);

  Map<String, dynamic> toJson() => {'key': key, 'text': text};

  @override
  bool operator ==(Object other) => other is QuizOption && other.key == key && other.text == text;
  @override
  int get hashCode => Object.hash(key, text);
}

enum QuestionType { single, multiple, judge }

extension QuestionTypeX on QuestionType {
  String get raw => name;
  String get displayName {
    switch (this) {
      case QuestionType.single:
        return '单选';
      case QuestionType.multiple:
        return '多选';
      case QuestionType.judge:
        return '判断';
    }
  }

  static QuestionType fromRaw(String r) {
    switch (r) {
      case 'single':
        return QuestionType.single;
      case 'multiple':
        return QuestionType.multiple;
      case 'judge':
        return QuestionType.judge;
      default:
        return QuestionType.single;
    }
  }
}

enum AnswerSource { todayNew, review, browse, wrongBook, cardJump }

extension AnswerSourceX on AnswerSource {
  String get raw => name;
  String get displayName {
    switch (this) {
      case AnswerSource.todayNew:
        return '今日新题';
      case AnswerSource.review:
        return '复习';
      case AnswerSource.browse:
        return '刷题';
      case AnswerSource.wrongBook:
        return '错题本';
      case AnswerSource.cardJump:
        return '速记跳题';
    }
  }

  static AnswerSource fromRaw(String r) {
    for (final v in AnswerSource.values) {
      if (v.name == r) return v;
    }
    return AnswerSource.browse;
  }
}

class Question {
  final int id;
  String typeRaw;
  String stem;
  List<QuizOption> options;
  String answer;
  String explanation;
  int? moduleId;
  int bucketIndex;

  int phase;
  DateTime? nextReviewDate;
  DateTime? lastAnsweredAt;
  int timesCorrect;
  int timesWrong;
  bool isFavorite;

  Question({
    required this.id,
    required this.typeRaw,
    required this.stem,
    required this.options,
    required this.answer,
    required this.explanation,
    this.moduleId,
    required this.bucketIndex,
    this.phase = 0,
    this.nextReviewDate,
    this.lastAnsweredAt,
    this.timesCorrect = 0,
    this.timesWrong = 0,
    this.isFavorite = false,
  });

  QuestionType get type => QuestionTypeX.fromRaw(typeRaw);
  bool get isMastered => phase >= 6;
  List<String> get answerLetters => answer.split('');

  Question copyWith({
    String? typeRaw,
    String? stem,
    List<QuizOption>? options,
    String? answer,
    String? explanation,
    int? moduleId,
  }) {
    return Question(
      id: id,
      typeRaw: typeRaw ?? this.typeRaw,
      stem: stem ?? this.stem,
      options: options ?? this.options,
      answer: answer ?? this.answer,
      explanation: explanation ?? this.explanation,
      moduleId: moduleId ?? this.moduleId,
      bucketIndex: bucketIndex,
      phase: phase,
      nextReviewDate: nextReviewDate,
      lastAnsweredAt: lastAnsweredAt,
      timesCorrect: timesCorrect,
      timesWrong: timesWrong,
      isFavorite: isFavorite,
    );
  }
}

class StudyModule {
  final int id;
  String name;
  int order;
  List<StudyCard> cards;

  StudyModule({
    required this.id,
    required this.name,
    required this.order,
    List<StudyCard>? cards,
  }) : cards = cards ?? [];
}

class StudyCard {
  final String cardId;
  String title;
  String content;
  int order;
  List<int> relatedQuestionIds;
  bool isRead;
  bool isFavorite;
  StudyModule? module;

  String storedStatusRaw;
  DateTime? passedAt;
  DateTime? nextReviewDate;
  int consolidationRound;
  String? lastSessionId;

  StudyCard({
    required this.cardId,
    required this.title,
    required this.content,
    required this.order,
    required this.relatedQuestionIds,
    this.isRead = false,
    this.isFavorite = false,
    this.module,
    this.storedStatusRaw = 'new',
    this.passedAt,
    this.nextReviewDate,
    this.consolidationRound = 0,
    this.lastSessionId,
  });

  String get storedStatus => storedStatusRaw;
}

class AnswerLog {
  final DateTime date;
  final int questionID;
  final String chosen;
  final bool isCorrect;
  final String sourceRaw;
  final String sessionId;
  final Question? question;

  AnswerLog({
    required this.date,
    required this.questionID,
    required this.chosen,
    required this.isCorrect,
    required this.sourceRaw,
    required this.sessionId,
    this.question,
  });

  AnswerSource get source => AnswerSourceX.fromRaw(sourceRaw);
}
