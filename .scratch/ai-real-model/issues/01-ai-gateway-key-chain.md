# 01 — AI网关与 Key 链路打通（B 编译注入优先，C双兜底）

**What to build:** 考生以 `flutter run --dart-define=OPENCODE_API_KEY=sk-...` 启动后，AI解析不再走本地占位，而是经 `opencode.ai/zen/go/v1` 用真实模型（首选 mimo-v2.5）返回结果；已在设置页存过 `ai.opencode.key` 时优先于编译注入，两者皆空才回占位。

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [ ] `flutter run --dart-define=OPENCODE_API_KEY=sk-test` 后设置页 `maskedKey` 非空且 `AIExplainService.explain("hello")` 不走占位，能命中远端或至少 401 可重试
- [ ] 清空设置再仅 `dart-define` 仍通，清空两者则回占位且无崩
- [ ] `AIConfig.isStreamingModelFor(mimo)=true, longcat=false` 判定正确，`availableModels` 含 3 项
- [ ] `flutter analyze 0` 且 `test/ai_test.dart` 回归绿
