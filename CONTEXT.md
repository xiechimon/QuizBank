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

### 练习会话
- **会话**：一次进入 `QuizSessionView` 的练习过程，由同一 `sessionId` 串联，其内每题提交产生一条 `AnswerLog`。*Avoid*: 轮次。
- **已提交 `submitted`**：会话内单题点选项/提交后显示正误与解析、可点“下一题”的题级状态。*Avoid*: 已完成。
- **会话已结束 `isFinished`**：`index >= questions.length`，显示结果页 `正确率/完成`。*Avoid*: 已通过。
- **考点已通过 `passed`**：会话内同一 `sessionId` 下该考点全部变式题一轮内全对，`TopicScheduler.transit` 晋升 `passed`。单题会话仅在单变式考点上才能触发。*Avoid*: 已完成。
- **关联题芯片**：卡片详情 `关联题目` 区每个 `#id` 为 `ActionChip`，点击以该题为起点 `sublist(idx)` 连续练习至末题，逐题 `已提交`→`下一题`，全部答完才 `会话已结束`。
- **关联题结果页**：`sourceRaw==cardJump` 的会话结束页为 `完成 / 下一张卡片` 双选项；`完成` 弹回当前卡，`下一张卡片` 弹回并自动翻至 `PageView` 下一张（末卡则提示已是最后一张）。*Avoid*: 再练一次（仅非 cardJump 会话可用）。

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
- **目录树**：速记首页按模块折叠，默认收起只见一级知识点；点模块头展开卡片，点卡片直达该卡详情。展开状态经 `tocExpansionProvider` 持久化（SharedPreferences），跨 tab / 跨重启记忆；筛选激活时自动全展开。
- **键盘缩放**：详情页 `Ctrl+=` 放大 / `Ctrl+-` 缩小 / `Ctrl+0` 重置，步长 0.1，范围 0.5x~3.0x，作用于 body 的 `MediaQuery.textScaler`，翻页保持，信息行显示当前百分比。
- **模块切换**：详情页 `MenuAnchor` 17 模块同页切换，页码回 0。
- **朗读（P2）**：标题喇叭 → `flutter_tts` 中文 → 行级高亮 → 播完翻页续播 → 关联题解析接力 → 断点续播。**Windows 门控**：不调 `awaitSpeakCompletion/setQueueMode/getEngines`（flutter_tts 4.2.5 Windows 原生 `FlutterResult` 双重完成缺陷 → 无声退出），完成回调走 `speak.onComplete` 事件 + Dart 侧 30s 超时兜底。
- **崩溃留痕**：`CrashLogger` 将 FlutterError / 未捕获异步错误 / zone 错误 / 生命周期事件追加写 `getApplicationSupportDirectory()/crash.log`（Windows: `%APPDATA%\com.example\quiz_bank\crash.log`）；`PlatformDispatcher.onError` 返回 true 保 UI isolate 存活。
- **关联题交互**：见“练习会话·关联题芯片”。

### 自更新
- **多通道检查**：raw `main/latest.json` 直连 → 镜像轮询（ghfast.top / gh-proxy.com / ghproxy.net）→ GitHub API release 资产；适配无代理网络，全通道失败静默跳过不阻塞启动。
- **下载与校验**：直连 → 镜像轮询；安装前 SHA256 强制校验（校验和与二进制不同源，防第三方镜像污染），失败删除换通道。
- **触发**：Windows 启动后每天一次静默检查（`update.lastAutoCheck`）；设置页「检查更新」手动入口。安装走 bat 链：延时 → Inno `/VERYSILENT` → 拉起 `Platform.resolvedExecutable` → 本进程退出。
- **CI 契约**：tag 构建生成 `latest.json`（version/tag/assetName/url/sha256）+ `SHA256SUMS`，随 Release 上传，且 latest.json 提交回 main（供 raw 镜像通道）。

## 架构决策（ADR 摘要）
- **ADR-1 题库增量**：`BankImporter` SHA256(questions.json) 存 `SharedPreferences`，hash 不变跳过，变化则按 `id` upsert 且保留 `phase/timesCorrect/isFavorite`。
- **ADR-2 考点为调度事实源**：`TopicScheduler.transit` 纯函数（today 注入），`TopicProgress.isSingleRoundPassed` 判定同 `sessionId` 内全对。
- **ADR-3 AI 网关**：`dio` + `AIConfig(baseURL/model/apiKey)`，`OPENCODE_API_KEY` dart-define 注入，`embeddedFallbackKey` 仅占位。
- **ADR-004 AI真实模型**：`opencode.ai/zen/go/v1` + `mimo-v2.5` 首选流式，`deepseek` 流式/`longcat` 降级；Key链路 `ai.opencode.key` > `OPENCODE_API_KEY` > 占位（B 编译注入），401/断流占位不阻断（2026-09-01 接受）。
- **ADR-005 AI无VPN接入**：系统 DNS（模拟器/真机污染）解析失败时 `DnsBootstrap` 经 DoH（阿里 dns.alidns.com / 腾讯 doh.pub，固定 IP + TLS SNI）拿真实 A 记录直连；`OpenCodeExplainService._client` 使用 `HttpClient.connectionFactory` 自管建连（该模式下 dart:io 不自动 TLS，https 需 `SecureSocket.secure`）。系统解析成功但 IP 不可达时强制 DoH 重试一次。缓存 5 分钟 / 负缓存 20 秒（2026-09-02 接受）。

## 非目标
- 无 Onboarding、无推送、无服务端、本地 SQLite 全量离线。

## 工程约束
- `analysis_options.yaml` 0 error 门槛；`flutter test 68+` 全绿门槛。
- `assets/data/*.docx` 不打进 bundle，仅工具链使用。
- `database.g.dart` 生成文件不手改，由 `build_runner` 产出。
