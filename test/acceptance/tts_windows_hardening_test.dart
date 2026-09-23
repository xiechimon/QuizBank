import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:quiz_bank/features/cards/card_reading_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验收：TTS Windows 链路加固（用户反馈 #3 — 无声自动退用的头号嫌疑）
/// 根因：flutter_tts 4.2.5 Windows 原生实现在 awaitSpeakCompletion=true 时
/// 存储 FlutterResult，stop()/MediaEnded 存在空函数解引用与双重完成
/// （std::bad_function_call / use-after-free → 进程无声终止）。
/// 契约：Windows 平台不得调用 awaitSpeakCompletion(true) / setQueueMode / getEngines；
/// 其他平台行为保持不变（awaitSpeakCompletion(true) 照旧）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TTS Windows 加固', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Windows: 不触碰 awaitSpeakCompletion/setQueueMode/getEngines', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final fake = _RecordingTts();
      CardReadingService(tts: fake);
      await Future.delayed(const Duration(milliseconds: 80));
      expect(fake.awaitSpeakCompletionCalled, isFalse,
          reason: 'Windows 原生实现有 FlutterResult 双重完成缺陷，必须规避');
      expect(fake.queueModeCalled, isFalse, reason: 'setQueueMode 为 Android-only，Windows 走 NotImplemented');
      expect(fake.enginesCalled, isFalse, reason: 'getEngines 为 Android-only');
      expect(fake.lastLang, 'zh-CN', reason: '语言设置应照常执行');
    });

    test('Android: awaitSpeakCompletion(true) 行为保持（回归锁）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final fake = _RecordingTts();
      CardReadingService(tts: fake);
      await Future.delayed(const Duration(milliseconds: 80));
      expect(fake.awaitSpeakCompletionCalled, isTrue);
      expect(fake.awaitCompletion, isTrue);
    });
  });
}

class _RecordingTts extends FlutterTts {
  bool awaitSpeakCompletionCalled = false;
  bool queueModeCalled = false;
  bool enginesCalled = false;
  bool awaitCompletion = false;
  String? lastLang;

  @override
  Future<dynamic> setLanguage(String language) async {
    lastLang = language;
    return 1;
  }

  @override
  Future<dynamic> isLanguageAvailable(String language) async => true;

  @override
  Future<dynamic> get getLanguages async => ['zh-CN'];

  @override
  Future<dynamic> get getEngines async {
    enginesCalled = true;
    return ['com.google.android.tts'];
  }

  @override
  Future<dynamic> setQueueMode(int mode) async {
    queueModeCalled = true;
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double v) async => 1;

  @override
  Future<dynamic> setPitch(double p) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool b) async {
    awaitSpeakCompletionCalled = true;
    awaitCompletion = b;
    return 1;
  }

  @override
  void setCompletionHandler(Function() h) {}

  @override
  void setCancelHandler(Function() h) {}

  @override
  void setErrorHandler(ErrorHandler? h) {}

  @override
  void setStartHandler(Function() h) {}

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async => 1;

  @override
  Future<dynamic> stop() async => 1;
}
