# ADR-004 AI 解析接入真实模型（OpenCode Zen + MiMo 流式）

- **日期**: 2026-09-01
- **状态**: 已接受（grill-with-docs 5问收敛）
- **关联**: CONTEXT.md#AI解析, ADR-002 考点调度

## 背景
Flutter 版 `AIExplainService` 已实现 `dio + SSE`，但 `embeddedFallbackKey` 为占位，`ai.opencode.key` 为空，实际恒走 `Placeholder`。需接真实 `opencode` 网关验证流式闭环。

## 决策
1. **网关**: `https://opencode.ai/zen/go/v1`（`AIConfig.defaultBaseURL`），`chat/completions` 兼容 OpenAI
2. **模型**: 首选 `mimo-v2.5`（流式），备 `deepseek-v4-flash`（流式）、`longcat-2.0`（非流式降级）。`isStreamingModelFor = mimo|deepseek`
3. **Key 链路（C 双兜底）**: `SharedPreferences ai.opencode.key` > `--dart-define=OPENCODE_API_KEY|AI_API_KEY|OPENCODE_KEY` > `embeddedFallback` > Placeholder。设置页直连 `AIConfig.instance`
4. **失败策略**: 401/网络/空响应 不阻断，`【网络错误/401】+ Placeholder` 占位，保证题可继续做（用户已接受）
5. **隐私**: 选中文本+整题上下文（题干/选项/提交后答案/解析）发远端，不另加二次确认（用户已接受）
6. **注入方式**: 本次选 `B` 编译注入：`flutter run --dart-define=OPENCODE_API_KEY=sk-...`，本地不落明文

## 后果
- 正：零后端、全离线题库 + 云端解析互补，`mimo` 增量体验，`longcat` 成本兜底
- 负：需自行保管 `sk-...` 计费与限流，`flutter_tts` 与 `dio` 共存时注意 `awaitSpeakCompletion`

## 验证
- 真机 `AIExplainSheet` 选区→真流 3 chunk 追加可见，`longcat` 1次回调，飞行模式回退占位
