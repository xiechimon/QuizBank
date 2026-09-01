# 02 — 选区触发 + 上下文 + Sheet 流式/Markdown 验证

**What to build:** 考生在题干/解析/速记卡段落·列表·表格长按选区，系统菜单首位出现「AI解析」，点后弹出 `AIExplainSheet` 上回显选中、下以 `flutter_markdown_plus` 流式增量渲染 Markdown（表格横滑可复制），整题上下文（题干/选项/提交后答案/解析）一并发往模型。

**Blocked by:** 01 — AI网关与 Key 链路打通

**Status:** ready-for-agent

- [ ] 题页/卡页 `SelectableAIText` 长按菜单首位「AI解析」可点，`AIExplainContext` 含题干/选项/提交后答案
- [ ] `mimo` 真流 3 chunk 追加可见，`longcat` 降级为 1 次完整返回，断流/401 显示占位+重试不白屏
- [ ] 速记卡富文本 `heading` 不可选、`paragraph/bullet/table` 可选且 `【】` 橙色，表格横向滚动
- [ ] `flutter analyze 0` 且 `flutter test 68+` 全绿
