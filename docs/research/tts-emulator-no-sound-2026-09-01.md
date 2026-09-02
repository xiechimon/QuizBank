# TTS 无声调研 — Android Studio 模拟器 + flutter_tts 4.2.3

> 2026-09-01 针对 `QuizBank` 速记卡朗读“按阅读完全没有声音”的定向调研。结论：**首因为 App 层 `QUEUE_FLUSH` 抢占 + 未等 `completionHandler`，次因为模拟器音频链路与 GoogleTTS 中文包**。前者已代码修复（`has started → has completed`），后者需按本文清单自检。

## 1. 现场证据（已脱敏）

* `adb logcat` 首轮：`D/TTS has started: c328…` → `has been stopped: … Interrupted: true` → `cancel handler → abort`。`flutter logs` 无 `[DEBUG-tts]`（`debugPrint` 被限流）。
* 二轮（加 `print` + `QUEUE_ADD` 后）：`has started: bf43… → has completed: bf43…`（26s 完播），`GoogleTTS: currentLocale=cmn-CN, dispatch: cmn-cn-x-ssa-seanet-embedded`，`STREAM_TTS volume:15`（满）。说明引擎已出声，但宿主听不见。
* `flutter test test/tts_diagnosis_test.dart` 用 `FakeTts` 驱动真 `CardReadingService`：`setLanguage zh-CN → 1, awaitSpeakCompletion true, setQueueMode 1` 均 `1`，`cleanedTexts 4 → spoken 4` 绿。链路通，问题在真引擎/音频路由。

## 2. 模拟器常见无声根因（按命中率排序）

### 2.1 音频路由未到宿主
* AVD 默认音频输出是主机声卡；若主机静音、选错输出设备（AirPlay/蓝牙）、或 `AVD → Extended Controls → Microphone/Camera` 未授权，`logcat` 仍 `has completed` 但听不见。
* 自检：`adb shell dumpsys audio | grep -A2 STREAM_TTS` 已满 15 仅证软件音量，另需 `emulator -qemu -h` 看 `audio: using …`，并在 AVD 详情页勾 **Enable audio output**，主机系统音量≠静音。

### 2.2 GoogleTTS 中文包缺失
* `flutter_tts` 在 Android 上直连 `com.google.android.tts`。`setLanguage('zh-CN')` 返回 `0/false` 则 `speak` 静默 `0`。
* 模拟器镜像常仅 `en-US`，需 **设置 → 系统 → 语言 → 文字转语音 → 首选引擎 GoogleTTS → 齿轮 → 更新语音数据 → 中文（中国）** 并下载 `cmn-cn`。`adb shell pm list packages | grep tts` 应含 `com.google.android.tts`，`getEngines` 应回 `com.google.android.tts`，`isLanguageAvailable('zh-CN')` 应 `2`/`1`（`LANG_AVAILABLE`），否则回退 `zh`。
* 参考：`pub.dev/flutter_tts#Android` 要求 `minSdk 21`、`queries` 声明 `TTS_SERVICE`（见 2.5），`setLanguage` 前可 `getLanguages`/`isLanguageAvailable` 预检。

### 2.3 SDK 26+ `onRangeStart` 暂停实现
* 文档“Pausing on Android”指 `pause` 依赖 `onRangeStart`（SDK≥26），`awaitSpeakCompletion` 与 `onRangeStart` 共同决定断点。`emulator-5554` 为 `gphone64 arm64` 通常 SDK 34 满足，但快照（snapshot）冷启动后 `TextToSpeech` 需 ~1s 连接；`CardReadingService._init` 未 `await` 即 `speak` 会丢。

### 2.4 `AndroidManifest` 缺 `TTS_SERVICE` 查询
* `pub.dev` 明确：`Android 11+` 需在 `queries` 加
  ```xml
  <queries>
    <intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>
  </queries>
  ```
  现仓库 `android/app/src/main/AndroidManifest.xml` 仅 `PROCESS_TEXT`，缺此条会导致 `getEngines`/`isLanguageAvailable` 在部分 `targetSdk34` 上孤岛。

### 2.5 队列与完成回调
* 旧代码 `awaitSpeakCompletion(true)` 异步未 `await`，`play` 首行未等 `_initFuture`，`_playCurrent` 直接 `await speak` 后 `++index`，但 `speak` 在 `QUEUE_FLUSH(0)` 下立即返回，下句 `speak` 冲掉上一句 → `Interrupted: true`。已改为 `setQueueMode(1) // ADD` + `Completer` 等 `completionHandler`，`flutter test` 已绿。

## 3. 已落地修复（本次）

* `lib/features/cards/card_reading_service.dart`：`_initFuture = _init()`，`play` 首行 `await _initFuture`；`_init` 内 `await isLanguageAvailable/setLanguage(回退 zh)/setSpeechRate/setQueueMode(1)/awaitSpeakCompletion/getLanguages/getEngines` 全 `print`；`_playCurrent` 用 `Completer` 等 `completionHandler` 再 `++index`，`stop/pause` 打栈，`dispose` 复写 `notifyListeners` 防 `used after being disposed`。
* `android/app/src/main/AndroidManifest.xml` 待补 `TTS_SERVICE`（见下）。
* `test/tts_diagnosis_test.dart` 保留为紧环：`FakeTts` 模拟 `QUEUE_ADD + completion` 回调，断言 `cleanedTexts→spoken` 一一对应。

## 4. 自检清单（按序执行，30 秒定位）

1. **听得见性**：AVD 右侧 `… → Settings → Enable audio output` 勾选；主机非静音；`adb shell "service call audio 9 i32 3"` 返回 `STREAM_TTS` 非 0。
2. **引擎与语音包**：`adb shell cmd tts get-engines` 或 `adb shell dumpsys texttospeech` 看 `cmn-cn` 是否 `installed`；设置里手动下载中文。
3. **Manifest**：补 `TTS_SERVICE`，`flutter clean; flutter run`。
4. **日志**：`flutter logs | grep DEBUG-tts`（非 `adb logcat | grep DEBUG`）看 `setLanguage zh-CN result: 1` 与 `has started → has completed` 是否成对；若 `result 0` 则走 `zh` 回退分支。
5. **真机对照**：同 `APK` 装真机（非模拟器）点同一张卡，若有声则 100% 为 AVD 音频/镜像问题。

## 5. 参考（高可信一手）

* `pub.dev/packages/flutter_tts` — Android 章节 `minSdk 21`、`TTS_SERVICE` `queries`、`setQueueMode`、`awaitSpeakCompletion`、`getLanguages/isLanguageAvailable`（`curl -s https://r.jina.ai/https://pub.dev/packages/flutter_tts` 已拉取）。
* `developer.android.com/reference/android/speech/tts/TextToSpeech` — `QUEUE_FLUSH vs QUEUE_ADD`、`isLanguageAvailable` 返回值、`ACTION_TTS_SERVICE` 查询可见性（Android 11+）。
* 现场 `adb logcat`：`TextToSpeechManagerPerUserService: Connected successfully to com.google.android.tts` 证引擎可连，`GoogleTTSServiceImpl: TTS dispatch: cmn-cn-x-ssa-seanet-embedded` 证中文包已调。

---
*下一步：若自检后仍无声，贴 `flutter logs | grep DEBUG-tts` 的 10 行与 `adb shell dumpsys texttospeech | grep -A5 cmn`，即可单变量定是引擎/语音包/音频路由。*
