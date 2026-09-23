import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 崩溃留痕：把 Dart 侧异常与生命周期事件追加写入 crash.log。
/// release 下无控制台输出，「看一会儿无声退出」需要事后验尸依据。
/// 日志位置：getApplicationSupportDirectory()/crash.log
/// （Windows: %APPDATA%\<org>\<app>\crash.log）
class CrashLogger {
  CrashLogger._(this._file);

  final File? _file;
  static CrashLogger? _instance;
  static CrashLogger get instance => _instance ??= CrashLogger._(null);

  /// 生产初始化；失败不阻断启动（_file 为 null 时仅 debugPrint）
  static Future<void> init() async {
    File? f;
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      f = File('${dir.path}${Platform.pathSeparator}crash.log');
    } catch (_) {}
    _instance = CrashLogger._(f);
  }

  /// 测试注入
  static void useFile(File f) => _instance = CrashLogger._(f);

  Future<void> log(String tag, Object error, [StackTrace? stack]) async {
    debugPrint('[crashlog][$tag] $error');
    final buf = StringBuffer()
      ..writeln('${DateTime.now().toIso8601String()} [$tag] $error');
    if (stack != null) buf.writeln(stack);
    buf.writeln('---');
    try {
      await _file?.writeAsString(buf.toString(), mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}

/// 全局错误捕获。关键点：PlatformDispatcher.onError 返回 true，
/// 未捕获异步错误不再终止 UI isolate（无声退出的候选根因之一），痕迹落盘。
void installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashLogger.instance.log('flutter-error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLogger.instance.log('platform-error', error, stack);
    return true;
  };
}

/// runZonedGuarded 入口包装：任何漏网错误留痕，进程不退。
/// 注意：body 异步抛错时 runZonedGuarded 返回的 Future 永不完成（错误被交给
/// zone handler），故用 Completer 显式收口，保证 guardedMain 的 Future 可等待。
Future<void> guardedMain(FutureOr<void> Function() body) {
  final completer = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }, (e, st) {
    CrashLogger.instance.log('zone-error', e, st);
    if (!completer.isCompleted) completer.complete();
  });
  return completer.future;
}
