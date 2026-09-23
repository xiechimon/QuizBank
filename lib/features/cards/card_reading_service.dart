import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/error_reporting.dart';

/// TTS 朗读引擎 — 移植 CardReadingService.swift
/// 固定 zh-CN、默认语速，连续播 texts 数组，驱动 isPlaying/currentIndex
class CardReadingService extends ChangeNotifier {
  final FlutterTts _tts;
  List<String> _texts = [];
  int _currentIndex = 0;
  bool _isPlaying = false;

  Future<void>? _initFuture;
  Completer<void>? _speakCompleter;
  CardReadingService({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _initFuture = _init();
  }

  bool get isPlaying => _isPlaying;
  int get currentIndex => _currentIndex;
  List<String> get texts => List.unmodifiable(_texts);

  Future<void> _init() async {
    // flutter_tts 4.2.5 Windows 原生实现缺陷：awaitSpeakCompletion=true 时把
    // FlutterResult 存入 speakResult，stop()（play 前必调）与 MediaEnded 回调
    // 会对其空函数解引用/双重完成 → C++ 未捕获异常 → 进程无声终止。
    // Windows 上跳过该开关（speak 立即返回，Dart 侧 30s 超时兜底）；
    // setQueueMode/getEngines 为 Android-only，Windows 走 NotImplemented，同样跳过。
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    try {
      final langRes = await _tts.setLanguage('zh-CN');
      if (langRes == 0 || langRes == false) {
        await _tts.setLanguage('zh');
      }
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      if (!isWindows) {
        await _tts.awaitSpeakCompletion(true);
        try {
          await _tts.setQueueMode(1);
        } catch (_) {}
        await _tts.getLanguages;
        await _tts.getEngines;
      }
    } catch (e) {
      await CrashLogger.instance.log('tts-init', e);
    }
    _tts.setCompletionHandler(() {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) _speakCompleter!.complete();
    });
    _tts.setCancelHandler(() {
      // play() 初始的 stop() 会触发一次 cancel，此时新一轮的 _speakCompleter 尚未创建（null），
      // 若此时把 _isPlaying 冲回 false，会导致紧接着的新 speak 被 abort
      if (_speakCompleter == null) {
        return;
      }
      if (!_speakCompleter!.isCompleted) _speakCompleter!.complete();
      _isPlaying = false;
      notifyListeners();
    });
    _tts.setErrorHandler((msg) {
      CrashLogger.instance.log('tts-error', msg);
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) _speakCompleter!.completeError(msg);
      _isPlaying = false;
      notifyListeners();
    });
    _tts.setStartHandler(() {});
  }

  /// 开始播放 texts 数组，每条对应一个 utterance
  /// 支持 startIndex 断点续播（0-based）
  Future<void> play(List<String> texts, {int startIndex = 0}) async {
    print('[DEBUG-tts-7f3a] play called texts=${texts.length} start=$startIndex first=${texts.isNotEmpty ? texts.first.substring(0, texts.first.length.clamp(0,30)) : "empty"}');
    if (_initFuture != null) await _initFuture;
    await stop();
    if (texts.isEmpty) {
      debugPrint('[DEBUG-tts-7f3a] play empty texts, abort');
      _isPlaying = false;
      _currentIndex = 0;
      notifyListeners();
      return;
    }
    _texts = List.from(texts);
    _currentIndex = startIndex.clamp(0, _texts.length);
    _isPlaying = true;
    notifyListeners();
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    if (!_isPlaying || _currentIndex >= _texts.length) {
      print('[DEBUG-tts-7f3a] _playCurrent stop: isPlaying=$_isPlaying index=$_currentIndex len=${_texts.length}');
      _isPlaying = false;
      notifyListeners();
      return;
    }
    final text = _texts[_currentIndex];
    print('[DEBUG-tts-7f3a] _playCurrent try speak index=$_currentIndex text=${text.substring(0, text.length.clamp(0,40))}');
    if (text.trim().isEmpty) {
      print('[DEBUG-tts-7f3a] empty text skip');
      _currentIndex++;
      notifyListeners();
      await _playCurrent();
      return;
    }
    try {
      _speakCompleter = Completer<void>();
      final res = await _tts.speak(text);
      print('[DEBUG-tts-7f3a] speak result: $res for index=$_currentIndex');
      if (res == 0 || res == false) {
        print('[DEBUG-tts-7f3a] speak returned failure 0/false');
        _speakCompleter = null;
        _isPlaying = false;
        notifyListeners();
        return;
      }
      // 等待 completion handler 真正完成，而非仅靠 awaitSpeakCompletion
      try {
        await _speakCompleter!.future.timeout(const Duration(seconds: 30));
        print('[DEBUG-tts-7f3a] completer done for index=$_currentIndex');
      } on TimeoutException {
        print('[DEBUG-tts-7f3a] speak completer timeout for index=$_currentIndex');
      }
      _speakCompleter = null;
      if (!_isPlaying) {
        print('[DEBUG-tts-7f3a] after speak but _isPlaying false, abort');
        return;
      }
      _currentIndex++;
      notifyListeners();
      if (_currentIndex < _texts.length && _isPlaying) {
        await _playCurrent();
      } else {
        print('[DEBUG-tts-7f3a] playback finished at index=$_currentIndex');
        _isPlaying = false;
        notifyListeners();
      }
    } catch (e) {
      print('[DEBUG-tts-7f3a] _playCurrent catch: $e');
      _speakCompleter = null;
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    print('[DEBUG-tts-7f3a] pause called _isPlaying=$_isPlaying stack=${StackTrace.current.toString().split("\n").take(5).join(" | ")}');
    if (_isPlaying) {
      try { await _tts.stop(); } catch (_) {}
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> stop() async {
    print('[DEBUG-tts-7f3a] stop called _isPlaying=$_isPlaying _currentIndex=$_currentIndex stack=${StackTrace.current.toString().split("\n").take(5).join(" | ")}');
    _isPlaying = false;
    _currentIndex = 0;
    _texts = [];
    try {
      await _tts.stop();
    } catch (_) {}
    notifyListeners();
  }

  // ——— 断点续播持久化（UserDefaults 等价）———
  static const String resumeKey = 'cardReading.resume';

  static Future<void> saveResume({required String cardId, required int index}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(resumeKey, '$cardId::$index');
  }

  static Future<({String cardId, int index})?> loadResume() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(resumeKey);
    if (raw == null || !raw.contains('::')) return null;
    final parts = raw.split('::');
    if (parts.length != 2) return null;
    final idx = int.tryParse(parts[1]);
    if (idx == null) return null;
    return (cardId: parts[0], index: idx);
  }

  static Future<void> clearResume() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(resumeKey);
  }

  bool _disposed = false;
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _isPlaying = false;
    _texts = [];
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }
    _speakCompleter = null;
    try { _tts.stop(); } catch (_) {}
    super.dispose();
  }
}
