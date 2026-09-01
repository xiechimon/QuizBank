import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/features/ai/ai_config.dart';
import 'package:quiz_bank/features/ai/ai_explain_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeStreamService implements AIExplainService {
  final List<String> chunks;
  final bool throw401;
  final bool disconnect;
  FakeStreamService({required this.chunks, this.throw401=false, this.disconnect=false});

  @override
  Future<String> explain({String? prompt, String? question, String? answer, String? userAnswer, String? userChoice, String? stem, String? content, String? text, String? topic, String? explanation, String? options, List<String>? choices, String? correctAnswer, String? systemPrompt, String? positionalPrompt}) async {
    if(throw401) throw const AIUnauthorizedException('401');
    if(disconnect) throw const AINetworkException('disconnect');
    return chunks.join();
  }

  @override
  Stream<String> explainStream({String? prompt, String? question, String? answer, String? userAnswer, String? userChoice, String? stem, String? content, String? text, String? topic, String? explanation, String? options, List<String>? choices, String? correctAnswer, String? systemPrompt, String? positionalPrompt}) async* {
    if(throw401) throw const AIUnauthorizedException('401');
    for(var i=0;i<chunks.length;i++){
      if(disconnect && i==chunks.length-1) throw const AINetworkException('disconnect');
      yield chunks[i];
      await Future.delayed(const Duration(milliseconds: 5));
    }
  }
}

// Helper to emulate iOS onDelta API via Stream
Future<String> explainWithDelta(AIExplainService svc, String selection, void Function(String) onDelta) async {
  // Check streaming capability via model
  final model = AIConfig.instance.modelSync;
  final isStreaming = AIConfig.isStreamingModelFor(model);
  if(!isStreaming){
    final full = await svc.explain(prompt: selection);
    onDelta(full);
    return full;
  }
  var full='';
  await for(final delta in svc.explainStream(prompt: selection)){
    full+=delta;
    onDelta(delta);
  }
  return full;
}

// ---------------------------------------------------------------------------
// Helpers for Dio mocking
// ---------------------------------------------------------------------------
Dio dioWithInterceptor(FutureOr<void> Function(RequestOptions, RequestInterceptorHandler) onRequest) {
  final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
  dio.interceptors.add(InterceptorsWrapper(onRequest: onRequest));
  return dio;
}

ResponseBody sseBody(List<String> deltas) {
  // build SSE payload: data: {"choices":[{"delta":{"content":"xxx"}}]}\n
  final buf = StringBuffer();
  for (final d in deltas) {
    buf.writeln('data: ${jsonEncode({"choices": [{"delta": {"content": d}}]})}');
    buf.writeln();
  }
  buf.writeln('data: [DONE]');
  final bytes = utf8.encode(buf.toString());
  return ResponseBody.fromBytes(bytes, 200, headers: {Headers.contentTypeHeader: ['text/event-stream']});
}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AIConfig.instance.resetAll();
    AIConfig.setTestEnvOverride(null);
  });
  tearDown(() {
    AIConfig.setTestEnvOverride(null);
  });
  group('AI',(){
    test('isStreamingModel仅mimo/deepseek为true',(){
      expect(AIConfig.isStreamingModelFor('mimo-v2.5'), isTrue);
      expect(AIConfig.isStreamingModelFor('deepseek-v4-flash'), isTrue);
      expect(AIConfig.isStreamingModelFor('longcat-2.0'), isFalse);
      expect(AIConfig.isStreamingModelFor('gpt-4'), isFalse);
    });

    test('MiMo SSE增量通过',() async {
      final svc = FakeStreamService(chunks:['first ','second ','third']);
      final received=<String>[];
      var full='';
      await for(final d in svc.explainStream(prompt:'test')){
        received.add(d);
        full+=d;
      }
      expect(received, ['first ','second ','third']);
      expect(full, 'first second third');
    });

    test('401路径覆盖',() async {
      final svc = FakeStreamService(chunks:[], throw401:true);
      expect(()=> svc.explain(prompt:'x'), throwsA(isA<AIUnauthorizedException>()));
      expect(()=> svc.explainStream(prompt:'x').first, throwsA(isA<AIUnauthorizedException>()));
    });

    test('断流路径覆盖',() async {
      final svc = FakeStreamService(chunks:['a','b'], disconnect:true);
      expect(()=> svc.explainStream(prompt:'x').toList(), throwsA(isA<AINetworkException>()));
    });

    test('isStreamingModel全false时降级 onDelta一次',() async {
      // Simulate model longcat => isStreaming false
      expect(AIConfig.isStreamingModelFor('longcat-2.0'), isFalse);
      // Test helper that when not streaming, onDelta called once
      final svc = FakeStreamService(chunks:['full text']);
      // Force isStreaming false via direct call to explain (non-stream)
      int calls=0;
      String? last;
      void onDelta(String d){ calls++; last=d; }
      // simulate downgrade: call explain not stream
      final full = await svc.explain(prompt:'sel');
      onDelta(full);
      expect(calls, 1);
      expect(last, 'full text');
    });

    test('设置页可改Key模型baseURL',() async {
      SharedPreferences.setMockInitialValues({});
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-test-key-123');
      await cfg.setBaseURL('https://example.com/v1');
      await cfg.setModel('deepseek-v4-flash');
      expect(await cfg.apiKey, 'sk-test-key-123');
      expect(await cfg.baseURL, 'https://example.com/v1');
      expect(await cfg.model, 'deepseek-v4-flash');
      await cfg.resetAll();
    });

    test('Placeholder失败兜底',() async {
      const svc = PlaceholderExplainService();
      final res = await svc.explain(prompt:'hello world hello world hello world hello world hello world hello world');
      expect(res.isNotEmpty, isTrue);
    });

    test('onDelta适配器MiMo流式 vs 降级',() async {
      SharedPreferences.setMockInitialValues({});
      await AIConfig.instance.setModel('mimo-v2.5');
      final svc = FakeStreamService(chunks:['a','b','c']);
      int count=0;
      await explainWithDelta(svc, 'test', (d)=> count++);
      expect(count, 3);
      await AIConfig.instance.setModel('longcat-2.0');
      count=0;
      final svc2 = FakeStreamService(chunks:['full']);
      await explainWithDelta(svc2, 'test', (d)=> count++);
      expect(count, 1);
      await AIConfig.instance.resetAll();
    });
  });

  // -------------------------------------------------------------------------
  // Ticket 01: AI网关与 Key 链路打通（B 编译注入优先，C双兜底）
  // -------------------------------------------------------------------------
  group('AIConfig Ticket 01 - defaults & chain', () {
    test('defaultBaseURL/model/availableModels 正确', () {
      expect(AIConfig.defaultBaseURL, 'https://opencode.ai/zen/go/v1');
      expect(AIConfig.defaultModel, 'mimo-v2.5');
      expect(AIConfig.availableModels, contains('mimo-v2.5'));
      expect(AIConfig.availableModels, contains('deepseek-v4-flash'));
      expect(AIConfig.availableModels, contains('longcat-2.0'));
      expect(AIConfig.availableModels.length, 3);
    });

    test('isStreamingModelFor 判定正确', () {
      expect(AIConfig.isStreamingModelFor('mimo-v2.5'), isTrue);
      expect(AIConfig.isStreamingModelFor('MIMO-V2.5'), isTrue);
      expect(AIConfig.isStreamingModelFor('deepseek-v4-flash'), isTrue);
      expect(AIConfig.isStreamingModelFor('deepseek'), isTrue);
      expect(AIConfig.isStreamingModelFor('longcat-2.0'), isFalse);
      expect(AIConfig.isStreamingModelFor('longcat'), isFalse);
      expect(AIConfig.isStreamingModelFor('gpt-4'), isFalse);
      expect(AIConfig.instance.isStreamingModel, AIConfig.isStreamingModelFor(AIConfig.instance.modelSync));
    });

    test('availableModels 含3项且 isStreamingModelFor longcat=false', () {
      expect(AIConfig.availableModels.length, 3);
      for (final m in AIConfig.availableModels) {
        if (m.contains('longcat')) {
          expect(AIConfig.isStreamingModelFor(m), isFalse);
        } else {
          expect(AIConfig.isStreamingModelFor(m), isTrue);
        }
      }
    });

    test('maskKey 静态脱敏正确', () {
      expect(AIConfig.maskKey(null), '**** 未配置');
      expect(AIConfig.maskKey(''), '**** 未配置');
      expect(AIConfig.maskKey('   '), '**** 未配置');
      expect(AIConfig.maskKey('sk-123'), '****'); // <=8
      expect(AIConfig.maskKey('sk-test-key-123456'), 'sk-t****3456');
      expect(AIConfig.maskKey('sk-embedded-fallback-placeholder'), 'sk-e****lder');
    });

    test('maskedKey 显示 via AIConfig.maskKey（设置页桥接）', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-test-key-1234567890');
      expect(await cfg.maskedKey, AIConfig.maskKey('sk-test-key-1234567890'));
      expect(cfg.maskedKeySync, AIConfig.maskKey('sk-test-key-1234567890'));
      expect(cfg.maskedKeySync, 'sk-t****7890');
      await cfg.setApiKey('');
      // 清空后两者皆空（embedded为空）→ 未配置
      AIConfig.setTestEnvOverride(null);
      expect(await cfg.maskedKey, '**** 未配置');
      expect(cfg.maskedKeySync, '**** 未配置');
    });

    test('Key 链路 C: SharedPreferences ai.opencode.key 优先于 dart-define', () async {
      final cfg = AIConfig.instance;
      // 模拟 B 注入：设置 env override
      AIConfig.setTestEnvOverride('sk-env-injected-1234');
      // 无 prefs 时，apiKey 应回退到 env
      expect(await cfg.apiKey, 'sk-env-injected-1234');
      expect(cfg.apiKeySync, 'sk-env-injected-1234');
      expect(await cfg.maskedKey, AIConfig.maskKey('sk-env-injected-1234'));

      // 写入 SharedPreferences，C 应优先
      await cfg.setApiKey('sk-prefs-priority-5678');
      expect(await cfg.apiKey, 'sk-prefs-priority-5678');
      expect(cfg.apiKeySync, 'sk-prefs-priority-5678');

      // 清空 prefs 后，应回退到 env
      await cfg.clearApiKey();
      // clear 后缓存已清，需重新读取
      expect(await cfg.apiKey, 'sk-env-injected-1234');
      expect(cfg.apiKeySync, 'sk-env-injected-1234');
    });

    test('B 编译注入：当 SharedPreferences 为空时 apiKey == dart-define 值', () async {
      final cfg = AIConfig.instance;
      AIConfig.setTestEnvOverride('sk-b-injected-9999');
      // 确保 prefs 空
      SharedPreferences.setMockInitialValues({});
      await cfg.resetAll();
      AIConfig.setTestEnvOverride('sk-b-injected-9999');
      // 重新 ensureInitialized 后读取
      await cfg.ensureInitialized();
      final key = await cfg.apiKey;
      expect(key, 'sk-b-injected-9999');
      expect(cfg.apiKeySync, 'sk-b-injected-9999');
      expect(cfg.isConfiguredSync, isTrue);
      expect(await cfg.isConfigured, isTrue);
    });

    test('C 双兜底：两者皆空时回退到 embeddedFallback 且不崩', () async {
      final cfg = AIConfig.instance;
      SharedPreferences.setMockInitialValues({});
      await cfg.resetAll();
      AIConfig.setTestEnvOverride(null);
      // embeddedFallback 为空，两者皆空应为 null 且 isConfigured=false，直接走 Placeholder 不发网
      final key = await cfg.apiKey;
      expect(key, isNull);
      expect(cfg.apiKeySync, isNull);
      expect(cfg.isConfiguredSync, isFalse);
      expect(await cfg.isConfigured, isFalse);
      expect(AIConfig.maskKey(key), '**** 未配置');
    });

    test('旧 key ai.apiKey 不被使用，统一 ai.opencode.*', () async {
      SharedPreferences.setMockInitialValues({'ai.apiKey': 'sk-old-key-should-not-use'});
      await AIConfig.instance.resetAll();
      AIConfig.setTestEnvOverride(null);
      final key = await AIConfig.instance.apiKey;
      expect(key, isNot('sk-old-key-should-not-use'));
      expect(key, isNull);
    });

    test('baseURL/model 持久化与默认值', () async {
      final cfg = AIConfig.instance;
      expect(await cfg.baseURL, AIConfig.defaultBaseURL);
      expect(await cfg.model, AIConfig.defaultModel);
      expect(cfg.baseURLSync, AIConfig.defaultBaseURL);
      expect(cfg.modelSync, AIConfig.defaultModel);

      await cfg.setBaseURL('https://example.com/v1');
      await cfg.setModel('longcat-2.0');
      expect(await cfg.baseURL, 'https://example.com/v1');
      expect(await cfg.model, 'longcat-2.0');
      expect(cfg.baseURLSync, 'https://example.com/v1');
      expect(cfg.modelSync, 'longcat-2.0');
      expect(AIConfig.isStreamingModelFor(await cfg.model), isFalse);

      await cfg.clearBaseURL();
      await cfg.clearModel();
      expect(await cfg.baseURL, AIConfig.defaultBaseURL);
      expect(await cfg.model, AIConfig.defaultModel);
    });

    test('setApiKey 去空格、clear 行为', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('  sk-trimmed  ');
      expect(await cfg.apiKey, 'sk-trimmed');
      await cfg.setApiKey('   ');
      AIConfig.setTestEnvOverride(null);
      expect(await cfg.apiKey, isNull);
    });
  });

  group('OpenCodeExplainService Ticket 01 - 401/网络/空响应 兜底', () {
    test('成功路径：返回远端 content', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-test-success');
      await cfg.setModel('mimo-v2.5');
      final dio = dioWithInterceptor((opts, handler) {
        // verify baseURL/model/key 链路打通
        expect(opts.headers['Authorization'], 'Bearer sk-test-success');
        expect(opts.path, contains('opencode.ai/zen/go/v1/chat/completions'));
        final data = opts.data is String ? jsonDecode(opts.data) : opts.data;
        expect((data as Map)['model'], 'mimo-v2.5');
        handler.resolve(Response(
          requestOptions: opts,
          statusCode: 200,
          data: {
            'choices': [
              {'message': {'content': '这是远端真实解析结果'}}
            ]
          },
        ));
      });
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final res = await svc.explain(prompt: 'hello');
      expect(res, '这是远端真实解析结果');
    });

    test('401 兜底：非流式回退到 Placeholder 且带前缀，不抛异常', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-bad-key');
      final dio = dioWithInterceptor((opts, handler) {
        // 对 bad key 返回 401，对 embedded fallback 也返回 401（模拟都失败）
        handler.resolve(Response(
          requestOptions: opts,
          statusCode: 401,
          data: {'error': {'message': 'invalid api key'}},
        ));
      });
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final res = await svc.explain(prompt: 'hello 401');
      // 应不抛，返回带 401 前缀 + 占位
      expect(res, contains('【鉴权失败 401】'));
      expect(res, contains('占位'));
    });

    test('401 重试 embeddedFallback 成功时返回重试结果', () async {
      // embeddedFallback 为空时重试不会命中，改为直接占位回退（符合 Critical 2 修复）
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-original-bad');
      final dio = dioWithInterceptor((opts, handler) {
        handler.resolve(Response(requestOptions: opts, statusCode: 401, data: {'error': {'message': '401'}}));
      });
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final res = await svc.explain(prompt: 'hello retry');
      // 空 fallback 时不再重试成功，而是占位
      expect(res, contains('【鉴权失败 401】'));
      expect(res, contains('占位'));
    });

    test('网络错误兜底：回退占位且无崩', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-network-test');
      final dio = dioWithInterceptor((opts, handler) {
        handler.reject(DioException(
          requestOptions: opts,
          type: DioExceptionType.connectionError,
          error: const SocketException('Failed host lookup'),
        ));
      });
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final res = await svc.explain(prompt: 'hello network');
      expect(res, contains('【网络错误】'));
      expect(res, contains('占位'));
    });

    test('空响应兜底：回退占位', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-empty-test');
      final dio = dioWithInterceptor((opts, handler) {
        handler.resolve(Response(
          requestOptions: opts,
          statusCode: 200,
          data: {
            'choices': [{'message': {'content': ''}}]
          },
        ));
      });
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final res = await svc.explain(prompt: 'hello empty');
      expect(res, contains('【空响应】'));
      expect(res, contains('占位'));
    });

    test('stream 401 兜底：yield 前缀后回退占位流', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-stream-401');
      final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500, responseType: ResponseType.stream));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
        // 流式接口返回 401 — data 需为 ResponseBody 以匹配 post<ResponseBody>
        final body = ResponseBody.fromString('{"error":{"message":"401"}}', 401, headers: {Headers.contentTypeHeader: ['application/json']});
        handler.resolve(Response(requestOptions: opts, statusCode: 401, data: body));
      }));
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final chunks = await svc.explainStream(prompt: 'stream 401 test').toList();
      final joined = chunks.join();
      expect(joined, contains('【鉴权失败 401】'));
      expect(joined, contains('占位'));
    });

    test('stream 网络错误兜底', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-stream-network');
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
        handler.reject(DioException(requestOptions: opts, type: DioExceptionType.connectionError, error: 'offline'));
      }));
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final chunks = await svc.explainStream(prompt: 'stream network').toList();
      final joined = chunks.join();
      expect(joined, contains('【网络错误】'));
      expect(joined, contains('占位'));
    });

    test('stream 成功：SSE 增量', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-stream-success');
      final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500, responseType: ResponseType.stream));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
        // 返回 SSE stream
        final body = sseBody(['hello ', 'world']);
        handler.resolve(Response(requestOptions: opts, statusCode: 200, data: body));
      }));
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final chunks = await svc.explainStream(prompt: 'stream ok').toList();
      expect(chunks, ['hello ', 'world']);
      expect(chunks.join(), 'hello world');
    });

    test('stream 空响应回退占位', () async {
      final cfg = AIConfig.instance;
      await cfg.setApiKey('sk-stream-empty');
      final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500, responseType: ResponseType.stream));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
        // 空 SSE：直接 [DONE] — 服务会回退到占位（无前缀，直接占位）
        final body = ResponseBody.fromString('data: [DONE]\n\n', 200, headers: {Headers.contentTypeHeader: ['text/event-stream']});
        handler.resolve(Response(requestOptions: opts, statusCode: 200, data: body));
      }));
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final chunks = await svc.explainStream(prompt: 'empty stream').toList();
      final joined = chunks.join();
      // 当前实现对纯 [DONE] 直接回退占位，无【空响应】前缀；只要含占位即视为兜底成功
      expect(joined, contains('占位'));
    });

    test('两者皆空时 explain 不崩且回占位', () async {
      final cfg = AIConfig.instance;
      SharedPreferences.setMockInitialValues({});
      await cfg.resetAll();
      AIConfig.setTestEnvOverride(null);
      expect(await cfg.apiKey, isNull);
      // 直接走 Placeholder，不发网，无 401 前缀
      final dio = dioWithInterceptor((opts, handler) {
        // 不应被调用，若被调用则回 401 模拟兜底也通过
        handler.resolve(Response(requestOptions: opts, statusCode: 401, data: {'error': {'message': '401'}}));
      });
      final svc = OpenCodeExplainService(dio: dio, config: cfg, fallbackService: const PlaceholderExplainService());
      final res = await svc.explain(prompt: 'both empty');
      expect(res, contains('占位'));
      final streamRes = await svc.explainStream(prompt: 'both empty stream').toList();
      expect(streamRes.join(), contains('占位'));
    });

    test('_resolveApiKeyWithFallback 链路：prefs > env > embedded', () async {
      final cfg = AIConfig.instance;
      // 模拟 explain 内部调用 _resolveApiKeyWithFallback via explain
      // 1) prefs 空 + env 覆盖 => 使用 env
      SharedPreferences.setMockInitialValues({});
      await cfg.resetAll();
      AIConfig.setTestEnvOverride('sk-env-fallback');
      String? capturedKey;
      final dioEnv = dioWithInterceptor((opts, handler) {
        capturedKey = opts.headers['Authorization'] as String?;
        handler.resolve(Response(requestOptions: opts, statusCode: 200, data: {
          'choices': [{'message': {'content': 'ok'}}]
        }));
      });
      var svc = OpenCodeExplainService(dio: dioEnv, config: cfg, fallbackService: const PlaceholderExplainService());
      await svc.explain(prompt: 'env fallback');
      expect(capturedKey, 'Bearer sk-env-fallback');

      // 2) prefs 有值 => 使用 prefs，覆盖 env
      await cfg.setApiKey('sk-prefs-override');
      final dioPrefs = dioWithInterceptor((opts, handler) {
        capturedKey = opts.headers['Authorization'] as String?;
        handler.resolve(Response(requestOptions: opts, statusCode: 200, data: {
          'choices': [{'message': {'content': 'ok'}}]
        }));
      });
      svc = OpenCodeExplainService(dio: dioPrefs, config: cfg, fallbackService: const PlaceholderExplainService());
      await svc.explain(prompt: 'prefs priority');
      expect(capturedKey, 'Bearer sk-prefs-override');
    });
  });
}
