import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/error_reporting.dart';
import 'data/bank_importer.dart';
import 'data/database.dart';
import 'data/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  guardedMain(() async {
    await CrashLogger.init();
    installErrorHandlers();
    await CrashLogger.instance.log('lifecycle', 'app-start');
    final db = AppDatabase();
    try {
      await BankImporter.importIfNeeded(db);
      await BankImporter.importStudyNotesIfNeeded(db);
    } catch (e, st) {
      await CrashLogger.instance.log('import', e, st);
    }
    runApp(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const QuizBankApp(),
    ));
  });
}
