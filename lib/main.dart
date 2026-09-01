import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/bank_importer.dart';
import 'data/database.dart';
import 'data/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  try {
    await BankImporter.importIfNeeded(db);
    await BankImporter.importStudyNotesIfNeeded(db);
  } catch (e, st) {
    debugPrint('BankImporter failed: $e\n$st');
  }
  runApp(ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const QuizBankApp(),
  ));
}
