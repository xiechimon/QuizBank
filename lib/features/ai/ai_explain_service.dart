import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'ai_config.dart';
import 'dns_bootstrap.dart';

/// AI 解释服务抽象
///
/// 对外暴露两种能力：
/// - [explain] 非流式，一次性返回完整解释
/// - [explainStream] 流式增量返回（SSE）
abstract class AIExplainService {
  /// 非流式解释
  ///
  /// 统一使用命名参数以兼容多种调用风格，内部会归一为 prompt 文本。
  /// 支持 `prompt` / `question` / `stem` / `content` / `text` / `topic` 等别名。
  Future<String> explain({
    String? prompt,
    String? question,
    String? answer,
    String? userAnswer,
    String? userChoice,
    String? stem,
    String? content,
    String? text,
    String? topic,
    String? explanation,
    String? options,
    List<String>? choices,
    String? correctAnswer,
    String? systemPrompt,
    String? positionalPrompt,
  });

  /// 流式解释，SSE 增量
  Stream<String> explainStream({
    String? prompt,
    String? question,
    String? answer,
    String? userAnswer,
    String? userChoice,
    String? stem,
    String? content,
    String? text,
    String? topic,
    String? explanation,
    String? options,
    List<String>? choices,
    String? correctAnswer,
    String? systemPrompt,
    String? positionalPrompt,
  });
}

/// 占位服务：未配置或网络/鉴权失败时的兜底
class PlaceholderExplainService implements AIExplainService {
  const PlaceholderExplainService();

  @override
  Future<String> explain({
    String? prompt,
    String? question,
    String? answer,
    String? userAnswer,
    String? userChoice,
    String? stem,
    String? content,
    String? text,
    String? topic,
    String? explanation,
    String? options,
    List<String>? choices,
    String? correctAnswer,
    String? systemPrompt,
    String? positionalPrompt,
  }) async {
    final q = _resolvePrompt(
      positionalPrompt,
      prompt: prompt,
      question: question,
      stem: stem,
      content: content,
      text: text,
      topic: topic,
    );
    if (q.trim().isEmpty) {
      return 'AI 占位解释：未提供题目内容，暂无法生成解析。';
    }
    // 清理 iOS 同款 prompt 包装，仅取真正选中文字用于占位展示
    var displayQ = q.trim();
    if (displayQ.contains('【用户选中的文字】')) {
      final start = displayQ.indexOf('【用户选中的文字】') + '【用户选中的文字】'.length;
      var rest = displayQ.substring(start).trim();
      final endMarkers = ['【整题上下文】', '请按上述要求解析'];
      var end = rest.length;
      for (final m in endMarkers) {
        final idx = rest.indexOf(m);
        if (idx != -1 && idx < end) end = idx;
      }
      displayQ = rest.substring(0, end).trim();
      if (displayQ.isEmpty) displayQ = q.trim();
    }
    if (displayQ.length > 200) displayQ = '${displayQ.substring(0, 200)}…';
    // 简单本地占位解释，不依赖网络
    final buffer = StringBuffer();
    buffer.writeln('【占位解析】');
    buffer.writeln();
    buffer.writeln('题目：$displayQ');
    if (answer != null && answer.trim().isNotEmpty) {
      buffer.writeln('参考答案：$answer');
    }
    if (correctAnswer != null && correctAnswer.trim().isNotEmpty) {
      buffer.writeln('参考答案：$correctAnswer');
    }
    if (userAnswer != null && userAnswer.trim().isNotEmpty) {
      buffer.writeln('你的作答：$userAnswer');
    }
    if (userChoice != null && userChoice.trim().isNotEmpty) {
      buffer.writeln('你的作答：$userChoice');
    }
    if (explanation != null && explanation.trim().isNotEmpty) {
      buffer.writeln('原始解析：$explanation');
    }
    buffer.writeln();
    buffer.writeln('提示：当前为占位服务，未调用远端模型。如需 AI 详细讲解，请在设置中配置 API Key。');
    return buffer.toString();
  }

  @override
  Stream<String> explainStream({
    String? prompt,
    String? question,
    String? answer,
    String? userAnswer,
    String? userChoice,
    String? stem,
    String? content,
    String? text,
    String? topic,
    String? explanation,
    String? options,
    List<String>? choices,
    String? correctAnswer,
    String? systemPrompt,
    String? positionalPrompt,
  }) async* {
    final full = await explain(
      prompt: prompt,
      question: question,
      answer: answer,
      userAnswer: userAnswer,
      userChoice: userChoice,
      stem: stem,
      content: content,
      text: text,
      topic: topic,
      explanation: explanation,
      options: options,
      choices: choices,
      correctAnswer: correctAnswer,
      systemPrompt: systemPrompt,
      positionalPrompt: positionalPrompt,
    );
    // 模拟流式：按 20 字分片
    const chunkSize = 20;
    for (var i = 0; i < full.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, full.length);
      yield full.substring(i, end);
      // 微小延迟以保留流式体感，但不阻塞过久
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// 便捷：支持位置参数调用（供外部直接传 String）
  Future<String> explainText(String promptText) {
    return explain(prompt: promptText);
  }

  Stream<String> explainTextStream(String promptText) {
    return explainStream(prompt: promptText);
  }
}

/// OpenCode 网关实现，基于 Dio 的 chat/completions + SSE
///
/// - 使用 dio，不使用 http（满足任务要求）
/// - 支持非流式与流式
/// - 401、网络错误、空响应均有友好文案与 fallback 占位
class OpenCodeExplainService implements AIExplainService {
  // ignore: prefer_initializing_formals
  OpenCodeExplainService({
    Dio? dio,
    AIConfig? config,
    this.fallbackService = const PlaceholderExplainService(),
  })  : _dio = dio, // ignore: prefer_initializing_formals
        _config = config ?? AIConfig.instance;

  final Dio? _dio;
  final AIConfig _config;
  final AIExplainService fallbackService;

  Dio get _client {
    if (_dio != null) return _dio;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 10),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    // 修复：移除对 10.0.2.2 的硬编码代理（仅模拟器宿主 Clash 需要）
    // 真机上 10.0.2.2 不可达会导致 30s 超时叠加，体感为“不开 VPN 就不通”
    // 默认 DIRECT，由系统 VPN/代理自动接管；模拟器如需走宿主代理请在模拟器设置中手动配置代理
    // DNS 兜底：系统 DNS 解析失败/污染时经 DoH 拿到真实 IP 直连（无需 VPN）
    try {
      final adapter = dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 10);
          client.findProxy = (uri) => 'DIRECT';
          // 自定义连接工厂：解析失败时走 DnsBootstrap（系统 DNS → DoH 兜底）
          // 注意：connectionFactory 模式下 dart:io 不再自动做 TLS 升级，https 需返回 SecureSocket
          client.connectionFactory = (uri, proxyHost, proxyPort) {
            final Future<Socket> socket;
            if (proxyHost != null && proxyHost.isNotEmpty) {
              // 有显式代理：直连代理地址（DIRECT 下通常为 null），https 时需 TLS 升级
              socket = _connect(proxyHost, proxyPort ?? uri.port, uri);
            } else {
              socket = _connectWithDnsBootstrap(uri);
            }
            return Future.value(ConnectionTask.fromSocket(socket, () {}));
          };
          return client;
        };
      }
    } catch (_) {}
    return dio;
  }

  /// 通过 DnsBootstrap 解析并连接：[host] 解析失败时以 DoH 兜底（无需系统 DNS/VPN）
  ///
  /// 第一轮失败后强制 DoH 重连一次，覆盖“系统解析成功但 IP 被污染/不可达”的场景。
  /// https 请求在裸 TCP 后做 TLS 升级（SNI/证书校验仍按域名）。
  Future<Socket> _connectWithDnsBootstrap(Uri uri) async {
    final addrs = await DnsBootstrap.instance.resolve(uri.host);
    var socket = await _tryConnect(addrs, uri.port);
    if (socket != null) return _maybeSecure(socket, uri);
    // 强制 DoH 重试（跳过系统 DNS 结果）
    final dohAddrs = await DnsBootstrap.instance.resolveViaDoH(uri.host);
    socket = await _tryConnect(dohAddrs, uri.port);
    if (socket != null) return _maybeSecure(socket, uri);
    throw SocketException('Failed host lookup: ${uri.host}');
  }

  /// 直接连接指定主机的辅助（代理场景）
  Future<Socket> _connect(String host, int port, Uri uri) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
    return _maybeSecure(socket, uri);
  }

  /// https 时用 [SecureSocket.secure] 升级：SNI/证书校验均按 [uri.host]
  Future<Socket> _maybeSecure(Socket socket, Uri uri) {
    if (uri.scheme == 'https') {
      return SecureSocket.secure(socket, host: uri.host);
    }
    return Future.value(socket);
  }

  Future<Socket?> _tryConnect(List<InternetAddress> addrs, int port) async {
    for (final addr in addrs) {
      try {
        return await Socket.connect(addr, port, timeout: const Duration(seconds: 8));
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 公开方法
  // ---------------------------------------------------------------------------

  @override
  Future<String> explain({
    String? prompt,
    String? question,
    String? answer,
    String? userAnswer,
    String? userChoice,
    String? stem,
    String? content,
    String? text,
    String? topic,
    String? explanation,
    String? options,
    List<String>? choices,
    String? correctAnswer,
    String? systemPrompt,
    String? positionalPrompt,
  }) async {
    final resolved = _resolvePrompt(
      positionalPrompt,
      prompt: prompt,
      question: question,
      stem: stem,
      content: content,
      text: text,
      topic: topic,
    );
    if (resolved.trim().isEmpty) {
      throw ArgumentError('explain: prompt/question 不能为空');
    }

    final apiKey = await _resolveApiKeyWithFallback();
    if (apiKey == null || apiKey.trim().isEmpty) {
      // 未配置直接走占位兜底
      return fallbackService.explain(
        prompt: prompt,
        question: question,
        answer: answer,
        userAnswer: userAnswer,
        userChoice: userChoice,
        stem: stem,
        content: content,
        text: text,
        topic: topic,
        explanation: explanation,
        options: options,
        choices: choices,
        correctAnswer: correctAnswer,
        systemPrompt: systemPrompt,
        positionalPrompt: positionalPrompt,
      );
    }

    final baseUrl = await _config.baseURL;
    final model = await _config.model;
    final url = _chatCompletionsUrl(baseUrl);

    final messages = _buildMessages(
      prompt: resolved,
      answer: answer ?? correctAnswer,
      userAnswer: userAnswer ?? userChoice,
      explanation: explanation,
      systemPrompt: systemPrompt,
      options: options,
      choices: choices,
    );

    try {
      final resp = await _client.post<Map<String, dynamic>>(
        url,
        data: {
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'stream': false,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final status = resp.statusCode ?? 0;
      if (status == 401) {
        // 尝试 embedded 兜底重试一次（C 双兜底）
        final retried = await _retryWithEmbeddedFallback(
          url: url,
          model: model,
          messages: messages,
          originalKey: apiKey,
        );
        if (retried != null) return retried;
        // 401 最终回退到占位并附带提示，不抛异常阻断做题
        final fallbackText = await fallbackService.explain(
          prompt: prompt,
          question: question,
          answer: answer,
          userAnswer: userAnswer,
          userChoice: userChoice,
          stem: stem,
          content: content,
          text: text,
          topic: topic,
          explanation: explanation,
          options: options,
          choices: choices,
          correctAnswer: correctAnswer,
          systemPrompt: systemPrompt,
          positionalPrompt: positionalPrompt,
        );
        return '【鉴权失败 401】API Key 无效或已过期 (401)，请检查 AI 配置\n\n$fallbackText';
      }
      if (status >= 400) {
        final msg = _extractErrorMessage(resp.data) ?? '请求失败（$status）';
        // 非 401 的 4xx 也回退占位，不阻断做题（与流式一致）
        final fallbackText = await fallbackService.explain(
          prompt: prompt,
          question: question,
          answer: answer,
          userAnswer: userAnswer,
          userChoice: userChoice,
          stem: stem,
          content: content,
          text: text,
          topic: topic,
          explanation: explanation,
          options: options,
          choices: choices,
          correctAnswer: correctAnswer,
          systemPrompt: systemPrompt,
          positionalPrompt: positionalPrompt,
        );
        return '【请求失败 $status】$msg\n\n$fallbackText';
      }

      final contentText = _extractContent(resp.data);
      if (contentText == null || contentText.trim().isEmpty) {
        // 空响应回退占位，不抛异常
        final fallbackText = await fallbackService.explain(
          prompt: prompt,
          question: question,
          answer: answer,
          userAnswer: userAnswer,
          userChoice: userChoice,
          stem: stem,
          content: content,
          text: text,
          topic: topic,
          explanation: explanation,
          options: options,
          choices: choices,
          correctAnswer: correctAnswer,
          systemPrompt: systemPrompt,
          positionalPrompt: positionalPrompt,
        );
        return '【空响应】AI 未返回有效内容，请稍后重试\n\n$fallbackText';
      }
      return sanitize(contentText.trim());
    } on DioException catch (e) {
      final mapped = _mapDioError(e);
      // 网络错误等可回退到占位，避免直接崩溃
      if (mapped is AIUnauthorizedException) {
        final retried = await _retryWithEmbeddedFallback(
          url: url,
          model: model,
          messages: messages,
          originalKey: apiKey,
        );
        if (retried != null) return retried;
        // 401 最终回退到占位并附带提示
        final fallbackText = await fallbackService.explain(
          prompt: prompt,
          question: question,
          answer: answer,
          userAnswer: userAnswer,
          userChoice: userChoice,
          stem: stem,
          content: content,
          text: text,
          topic: topic,
          explanation: explanation,
          options: options,
          choices: choices,
          correctAnswer: correctAnswer,
          systemPrompt: systemPrompt,
          positionalPrompt: positionalPrompt,
        );
        return '【鉴权失败 401】${mapped.message}\n\n$fallbackText';
      }
      if (mapped is AINetworkException) {
        final fallbackText = await fallbackService.explain(
          prompt: prompt,
          question: question,
          answer: answer,
          userAnswer: userAnswer,
          userChoice: userChoice,
          stem: stem,
          content: content,
          text: text,
          topic: topic,
          explanation: explanation,
          options: options,
          choices: choices,
          correctAnswer: correctAnswer,
          systemPrompt: systemPrompt,
          positionalPrompt: positionalPrompt,
        );
        return '【网络错误】${mapped.message}\n\n$fallbackText';
      }
      rethrow;
    } on AIUnauthorizedException catch (e) {
      final fallbackText = await fallbackService.explain(
        prompt: prompt,
        question: question,
        answer: answer,
        userAnswer: userAnswer,
        userChoice: userChoice,
        stem: stem,
        content: content,
        text: text,
        topic: topic,
        explanation: explanation,
        options: options,
        choices: choices,
        correctAnswer: correctAnswer,
        systemPrompt: systemPrompt,
        positionalPrompt: positionalPrompt,
      );
      return '【鉴权失败 401】${e.message}\n\n$fallbackText';
    } on AIEmptyResponseException catch (e) {
      final fallbackText = await fallbackService.explain(
        prompt: prompt,
        question: question,
        answer: answer,
        userAnswer: userAnswer,
        userChoice: userChoice,
        stem: stem,
        content: content,
        text: text,
        topic: topic,
        explanation: explanation,
        options: options,
        choices: choices,
        correctAnswer: correctAnswer,
        systemPrompt: systemPrompt,
        positionalPrompt: positionalPrompt,
      );
      return '【空响应】${e.message}\n\n$fallbackText';
    } on AIRequestException catch (e) {
      final fallbackText = await fallbackService.explain(
        prompt: prompt,
        question: question,
        answer: answer,
        userAnswer: userAnswer,
        userChoice: userChoice,
        stem: stem,
        content: content,
        text: text,
        topic: topic,
        explanation: explanation,
        options: options,
        choices: choices,
        correctAnswer: correctAnswer,
        systemPrompt: systemPrompt,
        positionalPrompt: positionalPrompt,
      );
      return '【请求失败 ${e.statusCode ?? ""}】${e.message}\n\n$fallbackText';
    } catch (e) {
      // 未预期错误，兜底到占位
      final fallbackText = await fallbackService.explain(
        prompt: prompt,
        question: question,
        answer: answer,
        userAnswer: userAnswer,
        userChoice: userChoice,
        stem: stem,
        content: content,
        text: text,
        topic: topic,
        explanation: explanation,
        options: options,
        choices: choices,
        correctAnswer: correctAnswer,
        systemPrompt: systemPrompt,
        positionalPrompt: positionalPrompt,
      );
      return '【AI 调用异常】$e\n\n$fallbackText';
    }
  }

  @override
  Stream<String> explainStream({
    String? prompt,
    String? question,
    String? answer,
    String? userAnswer,
    String? userChoice,
    String? stem,
    String? content,
    String? text,
    String? topic,
    String? explanation,
    String? options,
    List<String>? choices,
    String? correctAnswer,
    String? systemPrompt,
    String? positionalPrompt,
  }) async* {
    final resolved = _resolvePrompt(
      positionalPrompt,
      prompt: prompt,
      question: question,
      stem: stem,
      content: content,
      text: text,
      topic: topic,
    );
    if (resolved.trim().isEmpty) {
      throw ArgumentError('explainStream: prompt/question 不能为空');
    }

    final apiKey = await _resolveApiKeyWithFallback();
    if (apiKey == null || apiKey.trim().isEmpty) {
      yield* fallbackService.explainStream(
        prompt: prompt,
        question: question,
        answer: answer,
        userAnswer: userAnswer,
        userChoice: userChoice,
        stem: stem,
        content: content,
        text: text,
        topic: topic,
        explanation: explanation,
        options: options,
        choices: choices,
        correctAnswer: correctAnswer,
        systemPrompt: systemPrompt,
        positionalPrompt: positionalPrompt,
      );
      return;
    }

    final baseUrl = await _config.baseURL;
    final model = await _config.model;
    final url = _chatCompletionsUrl(baseUrl);

    final messages = _buildMessages(
      prompt: resolved,
      answer: answer ?? correctAnswer,
      userAnswer: userAnswer ?? userChoice,
      explanation: explanation,
      systemPrompt: systemPrompt,
      options: options,
      choices: choices,
    );

    Stream<String> fallbackStream() {
      return fallbackService.explainStream(
        prompt: prompt,
        question: question,
        answer: answer,
        userAnswer: userAnswer,
        userChoice: userChoice,
        stem: stem,
        content: content,
        text: text,
        topic: topic,
        explanation: explanation,
        options: options,
        choices: choices,
        correctAnswer: correctAnswer,
        systemPrompt: systemPrompt,
        positionalPrompt: positionalPrompt,
      );
    }

    try {
      final response = await _client.post<ResponseBody>(
        url,
        data: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'stream': true,
        }),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          responseType: ResponseType.stream,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final status = response.statusCode ?? 0;
      if (status == 401) {
        // 401 时尝试 embedded 重试，否则回退
        final retriedStream = await _retryStreamWithEmbeddedFallback(
          url: url,
          model: model,
          messages: messages,
          originalKey: apiKey,
        );
        if (retriedStream != null) {
          yield* retriedStream;
          return;
        }
        yield '【鉴权失败 401】API Key 无效或已过期，请检查 AI 配置\n\n';
        yield* fallbackStream();
        return;
      }
      if (status >= 400) {
        yield '【请求失败 $status】\n\n';
        yield* fallbackStream();
        return;
      }

      final data = response.data;
      if (data == null) {
        throw const AIEmptyResponseException('AI 未返回有效内容，请稍后重试');
      }

      var hasYielded = false;
      // Dio 的 ResponseBody.stream 是 Stream<Uint8List>
      final stream = data.stream;
      var buffer = '';

      await for (final chunk in stream) {
        final textChunk = utf8.decode(chunk, allowMalformed: true);
        buffer += textChunk;

        // 按行处理，保留未完整行到下一次
        final lines = buffer.split('\n');
        // 最后一行可能不完整，留到下一轮
        buffer = lines.removeLast();

        for (final rawLine in lines) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          if (payload == '[DONE]') {
            // 结束
            if (!hasYielded) {
              yield* fallbackStream();
            }
            return;
          }
          final delta = _parseDelta(payload);
          if (delta != null && delta.isNotEmpty) {
            hasYielded = true;
            yield delta;
          }
        }
      }

      // 处理残留 buffer
      if (buffer.trim().isNotEmpty) {
        final line = buffer.trim();
        if (line.startsWith('data:')) {
          final payload = line.substring(5).trim();
          if (payload != '[DONE]') {
            final delta = _parseDelta(payload);
            if (delta != null && delta.isNotEmpty) {
              hasYielded = true;
              yield delta;
            }
          }
        }
      }

      if (!hasYielded) {
        // 空响应，回退
        throw const AIEmptyResponseException('AI 未返回有效内容，请稍后重试');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final retriedStream = await _retryStreamWithEmbeddedFallback(
          url: url,
          model: model,
          messages: messages,
          originalKey: apiKey,
        );
        if (retriedStream != null) {
          yield* retriedStream;
          return;
        }
        yield '【鉴权失败 401】API Key 无效或已过期，请检查 AI 配置\n\n';
        yield* fallbackStream();
        return;
      }
      final mapped = _mapDioError(e);
      if (mapped is AINetworkException) {
        yield '【网络错误】${mapped.message}\n\n';
        yield* fallbackStream();
        return;
      }
      yield '【AI 调用异常】$e\n\n';
      yield* fallbackStream();
    } on AIEmptyResponseException catch (e) {
      yield '【空响应】${e.message}\n\n';
      yield* fallbackStream();
    } catch (e) {
      yield '【AI 调用异常】$e\n\n';
      yield* fallbackStream();
    }
  }

  // 便捷：支持位置参数调用（positional）
  Future<String> explainText(String promptText) {
    return explain(prompt: promptText);
  }

  Stream<String> explainTextStream(String promptText) {
    return explainStream(prompt: promptText);
  }

  // ---------------------------------------------------------------------------
  // 内部辅助
  // ---------------------------------------------------------------------------

  Future<String?> _resolveApiKeyWithFallback() async {
    final key = await _config.apiKey;
    if (key != null && key.trim().isNotEmpty) return key.trim();
    // 配置为空时，已在 AIConfig 中回退到 env/embedded，此处再兜一次
    if (AIConfig.embeddedFallbackKey.trim().isNotEmpty) {
      return AIConfig.embeddedFallbackKey.trim();
    }
    return null;
  }

  Future<String?> _retryWithEmbeddedFallback({
    required String url,
    required String model,
    required List<Map<String, String>> messages,
    required String originalKey,
  }) async {
    final fallbackKey = AIConfig.embeddedFallbackKey.trim();
    if (fallbackKey.isEmpty || fallbackKey == originalKey.trim()) return null;
    try {
      final resp = await _client.post<Map<String, dynamic>>(
        url,
        data: {
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'stream': false,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $fallbackKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final status = resp.statusCode ?? 0;
      if (status >= 400) return null;
      final contentText = _extractContent(resp.data);
      if (contentText == null || contentText.trim().isEmpty) return null;
      return sanitize(contentText.trim());
    } catch (_) {
      return null;
    }
  }

  Future<Stream<String>?> _retryStreamWithEmbeddedFallback({
    required String url,
    required String model,
    required List<Map<String, String>> messages,
    required String originalKey,
  }) async {
    final fallbackKey = AIConfig.embeddedFallbackKey.trim();
    if (fallbackKey.isEmpty || fallbackKey == originalKey.trim()) return null;
    try {
      final response = await _client.post<ResponseBody>(
        url,
        data: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'stream': true,
        }),
        options: Options(
          headers: {
            'Authorization': 'Bearer $fallbackKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          responseType: ResponseType.stream,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 400) return null;
      final data = response.data;
      if (data == null) return null;
      // 转为 Stream<String> 的 delta
      return _sseToDeltaStream(data.stream);
    } catch (_) {
      return null;
    }
  }

  Stream<String> _sseToDeltaStream(Stream<List<int>> byteStream) async* {
    var buffer = '';
    await for (final chunk in byteStream) {
      final textChunk = utf8.decode(chunk, allowMalformed: true);
      buffer += textChunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]' || payload.isEmpty) continue;
        final delta = _parseDelta(payload);
        if (delta != null && delta.isNotEmpty) yield delta;
      }
    }
    if (buffer.trim().isNotEmpty && buffer.trim().startsWith('data:')) {
      final payload = buffer.trim().substring(5).trim();
      if (payload != '[DONE]') {
        final delta = _parseDelta(payload);
        if (delta != null && delta.isNotEmpty) yield delta;
      }
    }
  }

  String? _parseDelta(String jsonStr) {
    try {
      final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
      final choices = obj['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final first = choices.first as Map<String, dynamic>;
      final delta = first['delta'] as Map<String, dynamic>?;
      if (delta != null) {
        final c = delta['content'];
        if (c is String && c.isNotEmpty) return sanitize(c);
        // 推理模型的 reasoning_content 为内部思考过程，不应直接展示给用户，
        // 此处忽略，等待 content 到达，期间 UI 保持 loading（正在解析…）
      }
      final message = first['message'] as Map<String, dynamic>?;
      if (message != null) {
        final c = message['content'];
        if (c is String) return sanitize(c);
      }
      // 兼容部分网关直接返回 text
      final text = first['text'];
      if (text is String) return sanitize(text);
      return null;
    } catch (_) {
      return null;
    }
  }

  String _chatCompletionsUrl(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    // baseUrl 已包含 /v1 时直接拼接 /chat/completions
    // 兼容传入末尾已带 /chat/completions 的情况
    if (trimmed.endsWith('/chat/completions')) return trimmed;
    return '$trimmed/chat/completions';
  }

  // ——— 抄自 AppleProjects/QuizBank/QuizBank/Features/AI/AIExplainService.swift ———
  static const String _systemInstructions = '''
你是审计考试辅导老师，用大白话+举例子讲懂。面向中国审计知识竞赛考生。要求：
1. 用通俗易懂的口语，先把选中句子掰开揉碎，再解释关键词；每个术语都配一句生活化类比或小例子。
2. 紧扣这句话举 1-2 个审计实务或日常例子帮记忆，必要时用 Markdown 表格对比易混概念，最后给一句口诀。
3. 准则编号不确定就说“按现行准则”，不编号。
4. 全文不要用 emoji 或特殊符号如 ✅ ❌ ✓ ✗ ✔ ✘ ★ ● 💡 📌 🎯 ✨ 🔑 💎 ◆ ◇，只用中文“可以/不可以”“是/否”加文字说明。
5. 500 字内，少用术语，不重复题干。
''';

  static String sanitize(String text) {
    var s = text;
    const map = {
      '✅': '可以', '❌': '不可以', '✓': '可以', '✗': '不可以',
      '✔': '可以', '✘': '不可以', '√': '可以', '×': '不可以',
      '★': '', '●': '·', '◆': '', '◇': '',
      '💡': '', '📌': '', '🎯': '', '✨': '', '🔑': '', '💎': '',
      '❗': '！', '❓': '？',
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll('\uFFFD', '');
    return s;
  }

  List<Map<String, String>> _buildMessages({
    required String prompt,
    String? answer,
    String? userAnswer,
    String? explanation,
    String? systemPrompt,
    String? options,
    List<String>? choices,
  }) {
    // system：优先外部传入，否则用 iOS 同款审计辅导口吻
    final system = systemPrompt?.trim().isNotEmpty == true
        ? systemPrompt!.trim()
        : _systemInstructions;

    // user：已按 sheet 拼好 "【用户选中的文字】+【整题上下文】+ 指令"，此处仅做兼容追加（避免旧调用丢字段）
    final userBuffer = StringBuffer(prompt.trim());
    if (options != null && options.trim().isNotEmpty) {
      userBuffer.writeln('\n选项：$options');
    }
    if (choices != null && choices.isNotEmpty) {
      userBuffer.writeln('\n选项：${choices.join('；')}');
    }
    if (answer != null && answer.trim().isNotEmpty) {
      userBuffer.writeln('\n参考答案：$answer');
    }
    if (userAnswer != null && userAnswer.trim().isNotEmpty) {
      userBuffer.writeln('\n我的作答：$userAnswer');
    }
    if (explanation != null && explanation.trim().isNotEmpty) {
      userBuffer.writeln('\n原始解析：$explanation');
    }
    // 若 prompt 已包含 iOS 的尾指令则不重复追加
    if (!userBuffer.toString().contains('请按上述要求解析')) {
      userBuffer.writeln('\n请给出易懂的讲解。');
    }

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': userBuffer.toString()},
    ];
  }

  String? _extractContent(Map<String, dynamic>? data) {
    if (data == null) return null;
    try {
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      if (message != null) {
        final c = message['content'];
        if (c is String && c.isNotEmpty) return sanitize(c);
        // 部分兼容：content 为 List
        if (c is List) {
          final joined = c.map((e) => (e as Map)['text']?.toString() ?? '').join();
          if (joined.isNotEmpty) return sanitize(joined);
        }
      }
      final text = first['text'];
      if (text is String && text.isNotEmpty) return sanitize(text);
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _extractErrorMessage(Map<String, dynamic>? data) {
    if (data == null) return null;
    try {
      final err = data['error'];
      if (err is Map) {
        final msg = err['message'];
        if (msg is String) return msg;
      }
      final msg = data['message'];
      if (msg is String) return msg;
      return null;
    } catch (_) {
      return null;
    }
  }

  Exception _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) {
      return const AIUnauthorizedException('API Key 无效或已过期 (401)，请检查 AI 配置');
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AINetworkException('网络超时，请检查网络后重试');
      case DioExceptionType.connectionError:
        return AINetworkException('网络连接失败，请检查网络后重试');
      case DioExceptionType.badResponse:
        if (status != null && status >= 400) {
          final msg = e.response?.data is Map
              ? _extractErrorMessage(e.response?.data as Map<String, dynamic>)
              : null;
          return AIRequestException(msg ?? '请求失败（$status）', statusCode: status);
        }
        return AINetworkException('网络错误：${e.message}');
      case DioExceptionType.cancel:
        return AINetworkException('请求已取消');
      case DioExceptionType.unknown:
      default:
        final msg = e.message ?? e.error?.toString() ?? '未知网络错误';
        // 常见无网场景会带 SocketException
        if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
          return AINetworkException('网络连接失败，请检查网络后重试');
        }
        return AINetworkException('网络错误：$msg');
    }
  }
}

// -----------------------------------------------------------------------------
// 辅助：prompt 归一
// -----------------------------------------------------------------------------

String _resolvePrompt(
  String? positional, {
  String? prompt,
  String? question,
  String? stem,
  String? content,
  String? text,
  String? topic,
}) {
  if (positional != null && positional.trim().isNotEmpty) return positional.trim();
  if (prompt != null && prompt.trim().isNotEmpty) return prompt.trim();
  if (question != null && question.trim().isNotEmpty) return question.trim();
  if (stem != null && stem.trim().isNotEmpty) return stem.trim();
  if (content != null && content.trim().isNotEmpty) return content.trim();
  if (text != null && text.trim().isNotEmpty) return text.trim();
  if (topic != null && topic.trim().isNotEmpty) return topic.trim();
  return '';
}

// -----------------------------------------------------------------------------
// 异常类型
// -----------------------------------------------------------------------------

class AIUnauthorizedException implements Exception {
  final String message;
  const AIUnauthorizedException(this.message);
  @override
  String toString() => 'AIUnauthorizedException: $message';
}

class AINetworkException implements Exception {
  final String message;
  const AINetworkException(this.message);
  @override
  String toString() => 'AINetworkException: $message';
}

class AIRequestException implements Exception {
  final String message;
  final int? statusCode;
  const AIRequestException(this.message, {this.statusCode});
  @override
  String toString() => 'AIRequestException($statusCode): $message';
}

class AIEmptyResponseException implements Exception {
  final String message;
  const AIEmptyResponseException(this.message);
  @override
  String toString() => 'AIEmptyResponseException: $message';
}

// -----------------------------------------------------------------------------
// Facade：AIExplain
// -----------------------------------------------------------------------------

/// 外观门面，根据是否已配置自动选择真实服务或占位服务
///
/// 提供静态便捷方法，满足任务中「Provide AIExplain facade」要求
class AIExplain {
  AIExplain._();

  static final AIExplainService _placeholder = const PlaceholderExplainService();

  /// 根据配置创建合适的服务实例
  static Future<AIExplainService> createService({Dio? dio, AIConfig? config}) async {
    final c = config ?? AIConfig.instance;
    final configured = await c.isConfigured;
    if (configured) {
      return OpenCodeExplainService(dio: dio, config: c, fallbackService: _placeholder);
    }
    return _placeholder;
  }

  /// 同步创建（仅基于缓存，不涉及磁盘 IO）
  static AIExplainService createServiceSync({Dio? dio, AIConfig? config}) {
    final c = config ?? AIConfig.instance;
    if (c.isConfiguredSync) {
      return OpenCodeExplainService(dio: dio, config: c, fallbackService: _placeholder);
    }
    return _placeholder;
  }

  /// 非流式便捷调用
  static Future<String> explain(
    String prompt, {
    String? question,
    String? answer,
    String? userAnswer,
    String? userChoice,
    String? stem,
    String? content,
    String? text,
    String? topic,
    String? explanation,
    String? options,
    List<String>? choices,
    String? correctAnswer,
    String? systemPrompt,
    Dio? dio,
    AIConfig? config,
  }) async {
    final service = await createService(dio: dio, config: config);
    return service.explain(
      prompt: prompt,
      question: question,
      answer: answer,
      userAnswer: userAnswer,
      userChoice: userChoice,
      stem: stem,
      content: content,
      text: text,
      topic: topic,
      explanation: explanation,
      options: options,
      choices: choices,
      correctAnswer: correctAnswer,
      systemPrompt: systemPrompt,
    );
  }

  /// 流式便捷调用
  static Stream<String> explainStream(
    String prompt, {
    String? question,
    String? answer,
    String? userAnswer,
    String? userChoice,
    String? stem,
    String? content,
    String? text,
    String? topic,
    String? explanation,
    String? options,
    List<String>? choices,
    String? correctAnswer,
    String? systemPrompt,
    Dio? dio,
    AIConfig? config,
  }) async* {
    final service = await createService(dio: dio, config: config);
    yield* service.explainStream(
      prompt: prompt,
      question: question,
      answer: answer,
      userAnswer: userAnswer,
      userChoice: userChoice,
      stem: stem,
      content: content,
      text: text,
      topic: topic,
      explanation: explanation,
      options: options,
      choices: choices,
      correctAnswer: correctAnswer,
      systemPrompt: systemPrompt,
    );
  }

  /// 兼容：直接获取 service 后自行调用
  static Future<AIExplainService> get service async => createService();

  /// 便捷：位置参数风格的别名，兼容旧调用
  static Future<String> explainText(String promptText, {Dio? dio, AIConfig? config}) {
    return explain(promptText, dio: dio, config: config);
  }

  static Stream<String> explainTextStream(String promptText, {Dio? dio, AIConfig? config}) {
    return explainStream(promptText, dio: dio, config: config);
  }
}
