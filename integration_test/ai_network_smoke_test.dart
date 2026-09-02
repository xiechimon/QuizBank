// 端到端实测：在模拟器（DNS 已损坏）上验证 AI 解析无需 VPN
// 运行：flutter test integration_test/ai_network_smoke_test.dart -d emulator-5554
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quiz_bank/features/ai/ai_explain_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AI 解析在系统 DNS 损坏环境仍可用（DoH 兜底）', (tester) async {
    final service = await AIExplain.service;
    final result = await service.explain(prompt: '审计工作底稿的作用是什么？用一句话回答。');
    print('AI_RESULT_PREFIX>>>$result<<<');
    expect(result.contains('【网络错误】'), isFalse, reason: '不应走网络错误占位');
    expect(result.contains('【占位解析】'), isFalse, reason: '不应走占位解析');
    expect(result.contains('【鉴权失败'), isFalse);
    expect(result.length, greaterThan(5));
  });
}
