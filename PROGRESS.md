# 进度回执 2026-09-01 增删审视落地（跑）

## 本次「跑」完成（基于 08-31 全量完成基线）

- **P0-3 单源与术语**：新增 `CONTEXT.md`（考点/变式题/四状态/今日队列/AI解析/富文本 唯一术语表），`docs/audit-2025-09-01.md` 落盘审视结论。
- **P0 依赖瘦身**：`pubspec.yaml` 删除 `cupertino_icons/go_router`（0引用），`flutter_markdown 0.7.7+1 discontinued` → `flutter_markdown_plus 1.0.12`，移除 `assets/data/*.docx` 打包（省 388KB），`flutter pub get` + `analyze 0 issue`。
- **P1-2 错题本**：`practice_view.dart: wrongBook` 从 `timesWrong>0` 改 `timesWrong>0 && phase<6`（未掌握才进）。
- **P0-3 设置单源**：`features/settings/settings_view.dart` 删除 60 行重复 `AiConfig/AiConfigNotifier(ai.apiKey)`，改为桥接 `AIConfig.instance(ai.opencode.*)`，新增下拉选 `mimo-v2.5/deepseek/longcat` + `maskedKey` 展示。
- **P0-2 富文本**：新增 `features/cards/card_content_parser.dart`（`#`/`·`/`|`/`【】` 解析，复刻 CardCleaning.swift）+ `card_content_view.dart`（heading不可选、段落/列表/表格可选 + 橙色【】高亮），`study_home_view.dart`/`today_view.dart` 详情/桥接均切 `CardContentView`，列表预览 `replaceAll('\n',' ')`。
- **P0-1 AI 链路**：新增 `features/ai/selectable_ai_text.dart`（`SelectableText.contextMenuBuilder` 首位插入「AI解析」）+ `ai_explain_sheet.dart`（上半选中引用、下半 `MarkdownBody` 流式/降级、断流/超时/重试、占位提示），`features/quiz/question_body_view.dart` 题干/解析接入 `SelectableAIText` → `AIExplainSheet.show(question,submitted)`，卡片侧同样联通。
- **P1-3/4 细节**：`today_view.dart` 进度条 `due/total.clamp` 修正为 `dueQuestions/totalQuestions.clamp(0,1)`；`study_home_view.dart` 收藏后 `invalidate(allStudyCards/allStudyModules)` 同步、`PageController` 切换泄漏修复。

## 验证

- `flutter analyze --no-fatal-warnings` → `No issues found!`
- `flutter test` → `68 passed`（含 importer 1170 / AI 401断流 / Derived 40题 / navigation）
- 手测待补：长按选区→AI解析（mimo流式 3 chunk vs longcat 1次）、卡片表格横滑、今日约40题、错题进出

## 未做（P1/P2 留待下次 /implement）

- TTS 磨耳朵 `flutter_tts`（行级高亮/翻页续播/断点）— 需加依赖，列为 P1 按需
- `stats_view.dart` 509行拆 6 子件
- 已删 `go_router`，如需深链再加回并实现 `/today/quiz` + `-initialTab`
- `database.g.dart` 提交策略（待建 git 后 `.gitignore: *.g.dart`）

## 下一步

- `/grill-with-docs` 压 3 ADR（AI dio/SSE、调度 7/30/90、Markdown渲染）→ `/to-tickets` 拆剩余 TTS/Stats 拆分 → `/implement` TDD 逐张
