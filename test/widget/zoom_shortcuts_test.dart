// 验证 v1.3.0+7 修复核心：MaterialApp.builder 注入 MediaQuery.textScaler 后，
// zoomScaleProvider 变化会真实传到 widget tree 的 MediaQuery（而非仅靠
// Transform.scale 改 painting）。修复前是 Transform.scale，MediaQuery 不会
// 变；修复后用 MediaQuery.copyWith(textScaler)，textScaler 必须跟随。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/app.dart';
import 'package:quiz_bank/features/settings/zoom_controller.dart';

void main() {
  testWidgets('zoomScaleProvider 变化时 widget tree 内 MediaQuery.textScaler 跟随',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: QuizBankApp()));
    await tester.pump();

    final element = tester.element(find.byType(Scaffold).first);

    // 初始 scale=1.0
    expect(_scaleAt(element), 1.0, reason: '初始 textScaler 必须是 1.0');

    // Provider state 变化（模拟快捷键触发的最终 effect）
    final container = ProviderScope.containerOf(element);
    container.read(zoomScaleProvider.notifier).zoomIn();
    await tester.pump();
    expect(_scaleAt(element), 1.1,
        reason: 'zoomIn 后 widget tree 内 textScaler.scale 应为 1.1');

    container.read(zoomScaleProvider.notifier).zoomIn();
    await tester.pump();
    expect(_scaleAt(element), 1.2);

    container.read(zoomScaleProvider.notifier).reset();
    await tester.pump();
    expect(_scaleAt(element), 1.0,
        reason: 'reset 后 widget tree 内 textScaler.scale 应为 1.0');

    container.read(zoomScaleProvider.notifier).zoomOut();
    await tester.pump();
    expect(_scaleAt(element), 0.9);
  });
}

double _scaleAt(Element element) {
  return MediaQuery.of(element).textScaler.scale(10) / 10;
}