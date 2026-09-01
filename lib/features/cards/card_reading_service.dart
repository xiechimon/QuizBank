import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TTS 朗读引擎 — 移植 CardReadingService.swift
/// 固定 zh-CN、默认语速，连续播 texts 数组，驱动 isPlaying/currentIndex
class CardReadingService extends ChangeNotifier {
  final FlutterTts _tts;
  List<String> _texts = [];
  int _currentIndex = 0;
  bool _isPlaying = false;

  CardReadingService({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _init();
  }

  bool get isPlaying => _isPlaying;
  int get currentIndex => _currentIndex;
  List<String> get texts => List.unmodifiable(_texts);

  void _init() {
    _tts.setLanguage('zh-CN');
    _tts.setSpeechRate(0.5);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);
    // iOS: 允许后台播放? flutter_tts 默认处理
    _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(() {
      // 单条完成，自动进下一条通过 _playNext 驱动
    });
    _tts.setCancelHandler(() {
      _isPlaying = false;
      notifyListeners();
    });
    _tts.setErrorHandler((msg) {
      _isPlaying = false;
      notifyListeners();
    });
  }

  /// 开始播放 texts 数组，每条对应一个 utterance
  /// 支持 startIndex 断点续播（0-based）
  Future<void> play(List<String> texts, {int startIndex = 0}) async {
    await stop();
    if (texts.isEmpty) {
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
      _isPlaying = false;
      notifyListeners();
      return;
    }
    final text = _texts[_currentIndex];
    if (text.trim().isEmpty) {
      _currentIndex++;
      notifyListeners();
      await _playCurrent();
      return;
    }
    // progress 驱动在 utterance 开始前已更新 index
    try {
      await _tts.speak(text);
      // awaitSpeakCompletion(true) 会阻塞至完成，完成后进下一条
      if (!_isPlaying) return;
      _currentIndex++;
      notifyListeners();
      if (_currentIndex < _texts.length && _isPlaying) {
        await _playCurrent();
      } else {
        _isPlaying = false;
        notifyListeners();
      }
    } catch (_) {
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (_isPlaying) {
      try { await _tts.stop(); } catch (_) {}
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> stop() async {
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

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
