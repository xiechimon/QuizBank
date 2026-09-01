# QuizBank（审计竞赛题库）— CONTEXT

> Flutter M3 重建，iOS SwiftData 版为事实源（`AppleProjects/QuizBank/CONTEXT.md`）。本文档是 Flutter 的唯一术语表，新增术语需先经此审视。

## 术语

### 学习主轴
- **考点**：复习的基本单位 = 1 张速记卡 + 挂其下全部变式题。每题恰好属于一个考点。*Avoid*: 知识点/卡片（卡片只是载体）。
- **变式题**：同一考点下不同角度考同一知识点的题。*Avoid*: 关联题。
- **模块**：考点的分组，仅决定浏览顺序，不参与调度。17 模块 ≈ 65-70 考点。

### 考点状态（阶梯，事实源 `StudyCard.storedStatusRaw`）
- **未学 `new`**：变式题一题未答。
- **学习中 `learning`**：已答但未在一轮内全对。
- **通过 `passed`**：一轮内全部变式题答对。`passedAt=today`，`nextReviewDate=today+7`，`consolidationRound=1`。
- **毕业 `graduated`**：通过后连续 3 次巩固全对（7→30→90 天），`nextReviewDate=nil`，终身不再进队列。*自由刷题再答错 → 回退 `learning`，重走全流程*。

### 调度
- **首次学习**：看卡 → 练该考点全部变式题。
- **巩固**：通过后的到期重测，直接答题，错才回看卡。
- **今日队列 `Derived.compute`**：到期巩固全量 + 新考点补至约 40 题。巩固超量则当日不推新（复习优先）。
- **题级调度 `ReviewScheduler`**：`1/2/4/7/15` 天，仅作题目 `phase/nextReviewDate` 容错与统计，不决定队列。

### 入口
- **错题本**：`timesWrong>0 && phase<6` 的题，随时查漏，不参与调度。
- **自由刷题**：按范围/题型随机练，与调度无关。

### AI 解析
- **触发**：题干/解析/速记卡 `paragraph/bullet/table` 长按选区 → 系统选区菜单「AI解析」。
- **上下文**：选中文本 + 整题（题干/选项/提交后含答案/解析），由 `AIExplain.context` 拼装。
- **结果**：Markdown（表格/加粗/列表），`flutter_markdown_plus` 渲染，表格横向滚动可复制。
- **流式**：仅 `mimo`/`deepseek` 走 `explainStream` 增量追加；`longcat` 等降级为一次返回。**断流视为失败，不保留半截**。
- **兜底**：未配置 key / 401 / 网络错误 → `PlaceholderExplainService` 占位 + 友好提示。

### 速记卡
- **富文本**：`content` 行级语法 `|` 表格 `·` 列表 `#` 小标题 `【】` 强调。`【】` 橙色高亮，`heading` 不可选，其余可选。
- **模块切换**：详情页 `MenuAnchor` 17 模块同页切换，页码回 0。
- **朗读（P2）**：标题喇叭 → `flutter_tts` 中文 → 行级高亮 → 播完翻页续播 → 关联题解析接力 → 断点续播。

## 架构决策（ADR 摘要）
- **ADR-1 题库增量**：`BankImporter` SHA256(questions.json) 存 `SharedPreferences`，hash 不变跳过，变化则按 `id` upsert 且保留 `phase/timesCorrect/isFavorite`。
- **ADR-2 考点为调度事实源**：`TopicScheduler.transit` 纯函数（today 注入），`TopicProgress.isSingleRoundPassed` 判定同 `sessionId` 内全对。
- **ADR-3 AI 网关**：`dio` + `AIConfig(baseURL/model/apiKey)`，`OPENCODE_API_KEY` dart-define 注入，`embeddedFallbackKey` 仅占位。
- **ADR-004 AI真实模型**：`opencode.ai/zen/go/v1` + `mimo-v2.5` 首选流式，`deepseek` 流式/`longcat` 降级；Key链路 `ai.opencode.key` > `OPENCODE_API_KEY` > 占位（B 编译注入），401/断流占位不阻断（2026-09-01 接受）。

## 非目标
- 无 Onboarding、无推送、无服务端、本地 SQLite 全量离线。

## 工程约束
- `analysis_options.yaml` 0 error 门槛；`flutter test 68+` 全绿门槛。
- `assets/data/*.docx` 不打进 bundle，仅工具链使用。
- `database.g.dart` 生成文件不手改，由 `build_runner` 产出。
