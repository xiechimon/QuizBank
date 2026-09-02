import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/features/cards/card_content_parser.dart';
import 'package:quiz_bank/features/cards/card_reading_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeTts extends FlutterTts {
  List<String> spoken = [];
  String? lastLang;
  double? lastRate;
  bool awaitCompletion = false;
  int queueMode = 0;
  Function()? completionHandler;
  Function()? cancelHandler;
  ErrorHandler? errorHandler;
  Function()? startHandler;
  @override
  Future<dynamic> setLanguage(String language) async { lastLang = language; return 1; }
  @override
  Future<dynamic> isLanguageAvailable(String language) async => true;
  @override
  Future<dynamic> get getLanguages async => ['zh-CN', 'zh', 'en-US'];
  @override
  Future<dynamic> get getEngines async => ['com.google.android.tts'];
  @override
  Future<dynamic> setQueueMode(int mode) async { queueMode = mode; return 1; }
  @override
  Future<dynamic> setSpeechRate(double rate) async { lastRate = rate; return 1; }
  @override
  Future<dynamic> setVolume(double v) async => 1;
  @override
  Future<dynamic> setPitch(double p) async => 1;
  @override
  Future<dynamic> awaitSpeakCompletion(bool b) async { awaitCompletion = b; return 1; }
  @override
  void setCompletionHandler(Function() h) { completionHandler = h; }
  @override
  void setCancelHandler(Function() h) { cancelHandler = h; }
  @override
  void setErrorHandler(ErrorHandler? h) { errorHandler = h; }
  @override
  void setStartHandler(Function() h) { startHandler = h; }
  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    startHandler?.call();
    // simulate async completion after 10ms
    Future.delayed(Duration(milliseconds: 10), () => completionHandler?.call());
    return 1;
  }
  @override
  Future<dynamic> stop() async => 1;
}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('TTS loop: cleanedTexts and speak', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeTts();
    final svc = CardReadingService(tts: fake);
    await Future.delayed(Duration(milliseconds: 50));
    expect(fake.lastLang, 'zh-CN');
    expect(fake.awaitCompletion, true);
    final content = '# 标题\n段落一\n· 列表1\n| a | b |\n| c | d |';
    final texts = CardContentParser.cleanedTexts(content);
    print('[TTS-LOOP] texts: $texts');
    expect(texts.isNotEmpty, true);
    await svc.play(texts);
    await Future.delayed(Duration(milliseconds: 300));
    print('[TTS-LOOP] spoken: ${fake.spoken}');
    expect(fake.spoken.length, texts.length);
    expect(fake.spoken.first, texts.first);
  });
  test('TTS loop: real card from assets', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeTts();
    final svc = CardReadingService(tts: fake);
    await Future.delayed(Duration(milliseconds: 50));
    // simulate first real card
    final content = '# 一张表记住三档门槛（万元）\n|投资额区间|审计组织形式|关键要求|\n|5万以下|各单位【自行决定】|审计部门审核可作结算依据|\n|100万（含）～500万（不含）|【关键节点审计】|至少含招投标环节+竣工验收阶段审计|';
    final texts = CardContentParser.cleanedTexts(content);
    print('[TTS-LOOP] real card texts ${texts.length}: $texts');
    expect(texts.isNotEmpty, true);
    await svc.play(texts);
    await Future.delayed(Duration(milliseconds: 300));
    print('[TTS-LOOP] spoken ${fake.spoken.length}');
    expect(fake.spoken.isNotEmpty, true);
  });
}
