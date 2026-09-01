import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/app.dart';

void main() {
  testWidgets('App smoke', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: QuizBankApp()));
    expect(find.text('今日'), findsWidgets);
  });
}
