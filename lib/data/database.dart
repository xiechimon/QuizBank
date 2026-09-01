import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class QuizOptionsConverter extends TypeConverter<List<Map<String, String>>, String> {
  const QuizOptionsConverter();
  @override
  List<Map<String, String>> fromSql(String fromDb) {
    if (fromDb.isEmpty) return [];
    final list = jsonDecode(fromDb) as List;
    return list.map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))).toList();
  }

  @override
  String toSql(List<Map<String, String>> value) => jsonEncode(value);
}

class IntListConverter extends TypeConverter<List<int>, String> {
  const IntListConverter();
  @override
  List<int> fromSql(String fromDb) {
    if (fromDb.isEmpty) return [];
    final list = jsonDecode(fromDb) as List;
    return list.map((e) => (e as num).toInt()).toList();
  }

  @override
  String toSql(List<int> value) => jsonEncode(value);
}

@DataClassName('DbQuestion')
class Questions extends Table {
  IntColumn get id => integer()();
  TextColumn get typeRaw => text()();
  TextColumn get stem => text()();
  TextColumn get options => text().map(const QuizOptionsConverter())();
  TextColumn get answer => text()();
  TextColumn get explanation => text()();
  IntColumn get moduleId => integer().nullable()();
  IntColumn get bucketIndex => integer()();
  IntColumn get phase => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextReviewDate => dateTime().nullable()();
  DateTimeColumn get lastAnsweredAt => dateTime().nullable()();
  IntColumn get timesCorrect => integer().withDefault(const Constant(0))();
  IntColumn get timesWrong => integer().withDefault(const Constant(0))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DbStudyModule')
class StudyModules extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  @JsonKey('order')
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DbStudyCard')
class StudyCards extends Table {
  TextColumn get cardId => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  @JsonKey('order')
  IntColumn get sortOrder => integer()();
  TextColumn get relatedQuestionIds => text().map(const IntListConverter())();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get moduleId => integer().nullable().customConstraint('REFERENCES study_modules(id) ON DELETE CASCADE')();
  TextColumn get storedStatusRaw => text().withDefault(const Constant('new'))();
  DateTimeColumn get passedAt => dateTime().nullable()();
  DateTimeColumn get nextReviewDate => dateTime().nullable()();
  IntColumn get consolidationRound => integer().withDefault(const Constant(0))();
  TextColumn get lastSessionId => text().nullable()();

  @override
  Set<Column> get primaryKey => {cardId};
}

@DataClassName('DbAnswerLog')
class AnswerLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  IntColumn get questionId => integer()();
  TextColumn get chosen => text()();
  BoolColumn get isCorrect => boolean()();
  TextColumn get sourceRaw => text()();
  TextColumn get sessionId => text()();
}

@DriftDatabase(tables: [Questions, StudyModules, StudyCards, AnswerLogs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'quizbank.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }

  static AppDatabase inMemory() {
    return AppDatabase.forTesting(NativeDatabase.memory());
  }

  Future<List<DbQuestion>> get allQuestions => select(questions).get();
  Future<List<DbStudyModule>> get allModules => select(studyModules).get();
  Future<List<DbStudyCard>> get allCards => select(studyCards).get();
  Future<List<DbAnswerLog>> get allLogs => select(answerLogs).get();
}
