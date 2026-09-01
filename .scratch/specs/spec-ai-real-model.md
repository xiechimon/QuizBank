# Spec: AI 解析接入真实模型（OpenCode Zen · MiMo 流式）

> 源：`grill-with-docs` 5问收敛（2026-09-01）+ `ADR-004` + `CONTEXT.md#AI解析`  
> 注入：`B --dart-define=OPENCODE_API_KEY=sk-...`（C 双兜底，`ai.opencode.key` 优先）

## Problem Statement
用户在题干/解析/速记卡长按选区点「AI解析」时，当前恒走本地 `PlaceholderExplainService` 占位，无法获得真实模型的结构化讲解。需在零后端前提下接通远端 OpenAI 兼容网关，并保证流式体验、降级与离线兜底可用。

## Solution
复用已有 `AIConfig` + `OpenCodeExplainService(dio, SSE)` 链路，以 `--dart-define` 注入真实 `sk-...`，`mimo/deepseek` 走 `explainStream` 增量追加，`longcat` 降级一次返回，401/网络/空响应回退占位不阻断做题。

## User Stories
1. 作为考生，我长按题干选中一段文字，点「AI解析」，能看到选中原文回显并进入“正在解析…”态
2. 作为考生，我选区触发后，若模型为 `mimo-v2.5`，能看到 Markdown 结果边收边渲染（增量追加）
3. 作为考生，我切到 `longcat-2.0`，仍能一次拿到完整 Markdown（降级），不卡死
4. 作为考生，我在飞行模式下点解析，能看到「网络错误+占位解析」而非白屏
5. 作为考生，我 Key 401 时能看到「鉴权失败401+占位」并可重试
6. 作为考生，我的选中会带整题上下文（题干/选项/提交后答案/解析）一并让模型更准
7. 作为考生，我在速记卡 `段落/列表/表格` 选区也能调 AI，且表格横向可滚动可复制
8. 作为考生，我可在 `设置` 看到当前 `model/baseURL/maskedKey`，改后对下次解析生效
9. 作为考生，我以 `flutter run --dart-define=OPENCODE_API_KEY=sk-...` 启动后，无需再进设置即可解析
10. 作为考生，我已在设置存过 `ai.opencode.key`，则优先于编译注入生效

## Implementation Decisions
- **网关**: `defaultBaseURL=https://opencode.ai/zen/go/v1`，`chat/completions`，`Authorization: Bearer <apiKey>`
- **模型**: `defaultModel=mimo-v2.5`，`availableModels=[mimo-v2.5, deepseek-v4-flash, longcat-2.0]`，`isStreamingModelFor=mimo|deepseek` 为流式
- **Key 链路**: `AIConfig.apiKey` 读取 `SharedPreferences ai.opencode.key` > `OPENCODE_API_KEY|AI_API_KEY|OPENCODE_KEY` > `embeddedFallback` > null；`apiKeySync` 同步读缓存+env；`setApiKey/setBaseURL/setModel` 直连 `AIConfig.instance`
- **服务**: `OpenCodeExplainService(dio, AIConfig, fallback=Placeholder)` 已实现 `explain` 非流 + `explainStream` SSE（`data: {...delta} / [DONE]` 解析，`_parseDelta` 兼容 `delta.content/message.content/text`），401 自动 `embeddedFallback` 重试一次
- **UI**: `SelectableAIText(contextMenuBuilder→AI解析)` + `AIExplainSheet(DraggableScrollableSheet)` 上引用、下 `MarkdownBody(selectable:true)`，流式 `StreamSubscription` 增量 `+=delta`，30s 超时兜底
- **渲染**: `flutter_markdown_plus`，`blockquote/tableHead` 定制，表格容器 `SingleChildScrollView horizontal`
- **设置**: `settings_view.dart` 桥接 `AIConfig.instance`，`Dropdown` + `TextField` 双写 `model`，`Chip(maskedKey)` 展示

## Testing Decisions
- **Seam**: 最高 seam `AIExplainService`（`explain/explainStream`），次 seam `AIConfig(maskedKey/isStreamingModelFor)`，UI seam `AIExplainSheet` 手测
- **原则**: 只测外部行为（“给 prompt 得 Markdown/流增量/401 抛对异常”），不测 `dio` 内实现
- **已有参照**: `test/ai_test.dart` 覆盖 `isStreamingModelFor` 真值、MiMo 3 chunk 流式、`401/断流` 异常、`longcat` 降级 `onDelta` 1次、`Placeholder` 兜底、`setApiKey/baseURL/model` 持久化
- **新增**: ① 真网关集成测试 `flutter run --dart-define` 手测 `explainStream` 3 增量可见 ② 飞行模式占位回归 ③ `mimo→longcat` 切换后 1 次回调回归

## Out of Scope
- 自建网关鉴权/限流、计费看板、上下文二次确认弹窗、TTS 与 AI 并发、历史解析缓存

## Further Notes
- 前端 `dio 5.8.1` 已定，`responseType: stream` + `validateStatus <500` 处理 401
- `analysis 0` / `test 68+` 门槛不变，`database.g.dart` 不手改
- `B` 注入时注意 `sk-...` 不提交仓库，CI 用 `secrets.OPENCODE_API_KEY`

## Seams Check（待用户确认）
- [ ] `AIExplainService` 作为唯一测试 seam 是否符合预期？是否需再抽 `SseParser` 单测？
- [ ] 设置页 `model` 下拉+自定义双写是否可接受，或只要下拉？
