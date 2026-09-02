import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/features/ai/ai_config.dart';
import 'package:quiz_bank/features/ai/ai_explain_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

// regression for bug: mimo streaming shows "暂无结果" due to reasoning_content ignored
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mimo reasoning_content should be ignored, not shown as thinking', () async {
    SharedPreferences.setMockInitialValues({});
    await AIConfig.instance.resetAll();
    await AIConfig.instance.setModel('mimo-v2.5');
    // mock SSE with reasoning then content
    final ssePayload = [
      'data: ${jsonEncode({"choices":[{"delta":{"content":null,"reasoning_content":"The user asks","tool_calls":null}}]})}',
      'data: ${jsonEncode({"choices":[{"delta":{"content":null,"reasoning_content":" to parse","tool_calls":null}}]})}',
      'data: ${jsonEncode({"choices":[{"delta":{"content":"省公司","reasoning_content":null,"tool_calls":null}}]})}',
      'data: ${jsonEncode({"choices":[{"delta":{"content":"审批","reasoning_content":null,"tool_calls":null}}]})}',
      'data: [DONE]',
    ].join('\n');
    final body = ResponseBody.fromString(ssePayload, 200, headers: {Headers.contentTypeHeader: ['text/event-stream']});
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500, responseType: ResponseType.stream));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
      handler.resolve(Response(requestOptions: opts, statusCode: 200, data: body));
    }));
    final svc = OpenCodeExplainService(dio: dio, config: AIConfig.instance, fallbackService: const PlaceholderExplainService());
    SharedPreferences.setMockInitialValues({});
    await AIConfig.instance.setApiKey('sk-test-regression');
    final chunks = await svc.explainStream(prompt: 'hello').toList();
    // reasoning should be ignored (not shown), only content should be yielded
    expect(chunks.join(), isNot(contains('The user asks')));
    expect(chunks.join(), contains('省公司'));
    expect(chunks.join(), contains('审批'));
    // reasoning 2 chunks ignored, only 2 content chunks should remain
    expect(chunks.length, 2);
  });

  test('sheet should not show 暂无结果 while streaming loading', () async {
    // This is a UI logic regression: _loading true while streaming should show spinner, not "暂无结果"
    // We verify the fix by checking that ai_explain_sheet.dart build condition includes streaming+empty
    final file = File('lib/features/ai/ai_explain_sheet.dart');
    final content = await file.readAsString();
    expect(content, contains('_loading || (_streaming && _result.isEmpty'));
    expect(content, contains('if (mounted) setState(() => _loading = true);'));
  });
}
