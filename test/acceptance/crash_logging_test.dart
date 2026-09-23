import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/core/error_reporting.dart';

/// 验收：崩溃留痕（用户反馈 #3 — 界面看一会儿无声自动退出）
/// 契约：
///  - FlutterError / 未捕获异步错误 / zone 错误全部落盘 crash.log
///  - PlatformDispatcher.onError 必须返回 true（吞掉错误保 UI isolate 存活，
///    release 下未捕获异步错误终止 isolate 是无声退出的候选根因之一）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('崩溃留痕', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('qb_crash');
      CrashLogger.useFile(File('${tmp.path}${Platform.pathSeparator}crash.log'));
      installErrorHandlers();
    });

    tearDown(() async {
      FlutterError.onError = FlutterError.dumpErrorToConsole;
      PlatformDispatcher.instance.onError = null;
      await tmp.delete(recursive: true);
    });

    Future<String> readLog() async {
      await Future.delayed(const Duration(milliseconds: 50)); // 等待异步落盘
      return File('${tmp.path}${Platform.pathSeparator}crash.log').readAsString();
    }

    test('FlutterError 写入 crash.log', () async {
      FlutterError.reportError(FlutterErrorDetails(
        exception: Exception('boom-render'),
        stack: StackTrace.current,
      ));
      final content = await readLog();
      expect(content, contains('boom-render'));
      expect(content, contains('[flutter-error]'));
    });

    test('PlatformDispatcher.onError 吞错并留痕（防无声退出）', () async {
      final handler = PlatformDispatcher.instance.onError;
      expect(handler, isNotNull, reason: 'installErrorHandlers 应已挂上 onError');
      final handled = handler!(Exception('boom-async'), StackTrace.current);
      expect(handled, isTrue, reason: '必须返回 true，否则引擎可能终止 UI isolate → 窗口无声消失');
      final content = await readLog();
      expect(content, contains('boom-async'));
      expect(content, contains('[platform-error]'));
    });

    test('zone 兜底错误留痕', () async {
      await guardedMain(() async {
        throw Exception('boom-zone');
      });
      final content = await readLog();
      expect(content, contains('boom-zone'));
      expect(content, contains('[zone-error]'));
    });
  });
}
