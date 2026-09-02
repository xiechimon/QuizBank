# QuizBank · 审计竞赛题库（Flutter M3）

> 1170 题 · 17 模块 · 65+ 考点 — Flutter Material 3 重建版，iOS SwiftData 为事实源。离线优先，本地 SQLite 全量运行。

[![Windows 单文件打包](https://github.com/xiechimon/QuizBank/actions/workflows/windows-single-exe.yml/badge.svg)](https://github.com/xiechimon/QuizBank/actions/workflows/windows-single-exe.yml)

## 功能一览

**学习主轴 · 考点**
- **考点** = 1 张速记卡 + 下挂全部变式题（同一知识点的多角度变式）
- **17 模块** 仅决定浏览顺序，不参与调度
- **速记卡富文本**：`|` 表格 · `·` 列表 · `#` 标题 · `【】` 橙色高亮，支持长按选区

**阶梯状态 & 调度**
- `未学 new` → `学习中 learning` → `通过 passed` → `毕业 graduated`（7/30/90 天三轮巩固）
- **今日队列**：到期巩固全量 + 新考点补至约 40 题，复习优先
- **题级容错**：`1/2/4/7/15` 天 `ReviewScheduler` 仅作统计，不决定队列

**练习会话**
- `QuizSessionView` 单 `sessionId` 串联，`AnswerLog` 逐题记录
- 关联题目芯片 `#id` 点任一题即以该题为起点 `sublist(idx)` 连续练至末题
- `cardJump` 结束页：`完成 / 下一张卡片` 双选项

**AI 解析**
- 题干/解析/卡片段落长按 → `AI解析`
- 上下文：选中文本 + 整题（题干/选项/答案/解析）→ `AIExplain.context`
- 模型：`opencode.ai/zen` + `mimo-v2.5` 流式首选，`deepseek` 流式，`longcat` 降级
- 无 VPN 接入：DoH（阿里/腾讯）直连重试，`HttpClient.connectionFactory` + `SecureSocket`

**TTS 朗读**
- 标题喇叭 → `flutter_tts` 中文连续播，行级高亮，播完自动翻页
- 全部卡播完接力播关联题解析
- 断点续播：`SnackBar [忽略 | 续播]` + 横划 dismiss，`SharedPreferences` 持久化

## 快速开始

```bash
flutter pub get
flutter run          # debug
flutter run --release
flutter test         # 128+ 用例
```

## 打包

| 目标 | 命令 | 产物 |
|------|------|------|
| Android APK | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Android AAB | `flutter build appbundle --release` | `build/app/outputs/bundle/release/app-release.aab` |
| Windows 单文件 | `flutter build windows --release && iscc windows/installer.iss` | `build/windows-installer/QuizBank-Setup-*.exe` |
| macOS | `flutter build macos --release` | `build/macos/Build/Products/Release/` |
| iOS | `flutter build ipa --release` | `build/ios/ipa/` |

> Windows 单文件已配好 `windows/installer.iss`（Inno Setup）+ GitHub Actions（`windows-single-exe.yml`），推到 GitHub 后云上自动出 `Setup.exe`，本地无 Windows 也能拿包。

## 架构

- **状态**：`flutter_riverpod` + `drift` (SQLite) + `shared_preferences`
- **AI**：`dio` + `flutter_markdown_plus`（流式增量渲染）
- **题库增量**：`SHA256(questions.json)` 比对，hash 不变跳过，变化按 `id` upsert 保留 `phase/timesCorrect`
- **文档源**：`CONTEXT.md` 为唯一术语表

## 目录

```
lib/
  data/          # drift database, models, providers
  features/
    cards/       # 速记卡 + TTS + 断点续播
    quiz/        # 练习会话、调度
    ai/          # AI 网关、DoH、ExplainSheet
    stats/       # 统计
  core/          # 调度纯函数
assets/data/     # questions.json / study_notes.json
```

## 工程约束

- `analysis_options.yaml` 0 error
- `flutter test` 全绿门槛
- `database.g.dart` 由 `build_runner` 生成，不手改

---
私仓部署 · 离线运行 · 无服务端
