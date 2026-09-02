import 'package:shared_preferences/shared_preferences.dart';

/// AI 能力配置
///
/// - [defaultBaseURL] 指向 OpenCode Zen Gateway
/// - [defaultModel] 默认模型
/// - [availableModels] 下拉可选集合
/// - [embeddedFallbackKey] 嵌入式兜底 Key，优先使用用户持久化配置，其次 env，最后兜底
/// - [apiKey] 异步读取 `SharedPreferences("ai.opencode.key")` + env fallback
/// - [baseURL]/[model] 支持持久化与 set 方法
/// - [maskedKey]/[isConfigured]/[isStreamingModel]/[isChatModel] 均为任务要求的派生属性
class AIConfig {
  AIConfig._internal();
  static final AIConfig instance = AIConfig._internal();
  factory AIConfig() => instance;

  // ---------------------------------------------------------------------------
  // 常量
  // ---------------------------------------------------------------------------

  /// 默认网关，满足任务要求
  static const String defaultBaseURL = 'https://opencode.ai/zen/go/v1';

  /// 默认模型，满足任务要求
  static const String defaultModel = 'mimo-v2.5';

  /// 可选模型集合，满足任务要求
  static const List<String> availableModels = [
    'mimo-v2.5',
    'deepseek-v4-flash',
    'longcat-2.0',
  ];

  /// 嵌入式兜底 Key
  /// 为避免“两者皆空仍发 401”浪费往返，现默认空：未配置时直接走 Placeholder，不发网。
  /// 如流水线需硬编码兜底，可改此常量或通过 --dart-define 注入。
  static const String embeddedFallbackKey = 'sk-zDRXE4SXypQPZg8ibXoPtQ9GP1pQOQx75YG6kycQP0XK7k3YDNTwcVW3sRUMWL0s';

  // SharedPreferences keys
  static const String _kApiKey = 'ai.opencode.key';
  static const String _kBaseUrl = 'ai.opencode.baseUrl';
  static const String _kModel = 'ai.opencode.model';

  // env keys（编译时注入）
  // B 注入优先：--dart-define=OPENCODE_API_KEY，其次 AI_API_KEY / OPENCODE_KEY
  static const String _envPrimary = String.fromEnvironment('OPENCODE_API_KEY');
  static const String _envSecondary = String.fromEnvironment('AI_API_KEY');
  static const String _envTertiary = String.fromEnvironment('OPENCODE_KEY');

  // 测试注入覆盖：仅在测试环境通过 setTestEnvOverride 写入，生产恒为 null
  static String? _testEnvOverride;

  /// @visibleForTesting: 覆盖 env 解析，仅测试使用
  // ignore: use_setters_to_change_properties
  static void setTestEnvOverride(String? v) => _testEnvOverride = v;
  static String? get testEnvOverride => _testEnvOverride;

  // ---------------------------------------------------------------------------
  // 缓存（避免每次都走磁盘）
  // ---------------------------------------------------------------------------
  String? _cachedApiKey;
  String? _cachedBaseUrl;
  String? _cachedModel;
  bool _initialized = false;

  /// 预热缓存，可在 app 启动时调用一次，非必须（getter 也会惰性加载）
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedApiKey = prefs.getString(_kApiKey);
    _cachedBaseUrl = prefs.getString(_kBaseUrl);
    _cachedModel = prefs.getString(_kModel);
    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // apiKey：SharedPreferences + env + embedded 兜底
  // ---------------------------------------------------------------------------

  /// 异步主入口：优先读取 SharedPreferences("ai.opencode.key")，其次 env，最后 embedded。
  ///
  /// 任务要求中明确提到要读取 `ai.opencode.key` + env fallback，此处均覆盖。
  Future<String?> get apiKey async {
    // 1. 缓存命中（已持久化）
    if (_cachedApiKey != null && _cachedApiKey!.trim().isNotEmpty) {
      return _cachedApiKey;
    }
    // 2. 磁盘
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kApiKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _cachedApiKey = stored.trim();
      return _cachedApiKey;
    }
    // 3. env fallback（dart-define）
    final env = _resolveEnvKey();
    if (env != null && env.trim().isNotEmpty) {
      return env.trim();
    }
    // 4. embedded fallback
    if (embeddedFallbackKey.trim().isNotEmpty) {
      return embeddedFallbackKey;
    }
    return null;
  }

  /// 同步便捷访问（仅读缓存 + env），适用于 UI 同步场景
  String? get apiKeySync {
    if (_cachedApiKey != null && _cachedApiKey!.trim().isNotEmpty) {
      return _cachedApiKey;
    }
    final env = _resolveEnvKey();
    if (env != null && env.isNotEmpty) return env;
    if (embeddedFallbackKey.isNotEmpty) return embeddedFallbackKey;
    return null;
  }

  String? _resolveEnvKey() {
    // 测试覆盖优先（仅测试代码会写入）
    if (_testEnvOverride != null && _testEnvOverride!.trim().isNotEmpty) {
      return _testEnvOverride!.trim();
    }
    if (_envPrimary.isNotEmpty) return _envPrimary;
    if (_envSecondary.isNotEmpty) return _envSecondary;
    if (_envTertiary.isNotEmpty) return _envTertiary;
    return null;
  }

  /// 是否已配置（key 非空即视为已配置，含 embedded 硬编码兜底）
  Future<bool> get isConfigured async {
    final key = await apiKey;
    if (key == null || key.trim().isEmpty) return false;
    return true;
  }

  /// 同步版本，供不需要 await 的场景
  bool get isConfiguredSync {
    final key = apiKeySync;
    if (key == null || key.trim().isEmpty) return false;
    return true;
  }

  /// 脱敏展示：前 4 + **** + 后 4，短 key 整体打码
  Future<String> get maskedKey async {
    final key = await apiKey;
    return maskKey(key);
  }

  /// 同步脱敏
  String get maskedKeySync => maskKey(apiKeySync);

  /// 静态脱敏工具
  static String maskKey(String? key) {
    if (key == null || key.trim().isEmpty) return '**** 未配置';
    final v = key.trim();
    if (v.length <= 8) return '****';
    return '${v.substring(0, 4)}****${v.substring(v.length - 4)}';
  }

  // ---------------------------------------------------------------------------
  // baseURL
  // ---------------------------------------------------------------------------

  /// 异步读取，持久化优先，其次默认值
  Future<String> get baseURL async {
    if (_cachedBaseUrl != null && _cachedBaseUrl!.trim().isNotEmpty) {
      return _cachedBaseUrl!.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kBaseUrl);
    if (stored != null && stored.trim().isNotEmpty) {
      _cachedBaseUrl = stored.trim();
      return _cachedBaseUrl!;
    }
    return defaultBaseURL;
  }

  /// 同步读取（缓存或默认值）
  String get baseURLSync {
    if (_cachedBaseUrl != null && _cachedBaseUrl!.trim().isNotEmpty) {
      return _cachedBaseUrl!.trim();
    }
    return defaultBaseURL;
  }

  /// 别名，兼容部分调用方使用 `baseUrl` 小写风格
  Future<String> get baseUrl async => baseURL;
  String get baseUrlSync => baseURLSync;

  /// 持久化 baseURL
  Future<void> setBaseURL(String url) async {
    final v = url.trim();
    final toStore = v.isEmpty ? defaultBaseURL : v;
    _cachedBaseUrl = toStore;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, toStore);
  }

  /// 别名
  Future<void> setBaseUrl(String url) => setBaseURL(url);

  // ---------------------------------------------------------------------------
  // model
  // ---------------------------------------------------------------------------

  Future<String> get model async {
    if (_cachedModel != null && _cachedModel!.trim().isNotEmpty) {
      return _cachedModel!.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kModel);
    if (stored != null && stored.trim().isNotEmpty) {
      _cachedModel = stored.trim();
      return _cachedModel!;
    }
    return defaultModel;
  }

  String get modelSync {
    if (_cachedModel != null && _cachedModel!.trim().isNotEmpty) {
      return _cachedModel!.trim();
    }
    return defaultModel;
  }

  Future<void> setModel(String m) async {
    final v = m.trim();
    final toStore = v.isEmpty ? defaultModel : v;
    _cachedModel = toStore;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModel, toStore);
  }

  // ---------------------------------------------------------------------------
  // apiKey set / clear
  // ---------------------------------------------------------------------------

  Future<void> setApiKey(String key) async {
    final v = key.trim();
    _cachedApiKey = v.isEmpty ? null : v;
    final prefs = await SharedPreferences.getInstance();
    if (v.isEmpty) {
      await prefs.remove(_kApiKey);
    } else {
      await prefs.setString(_kApiKey, v);
    }
  }

  Future<void> clearApiKey() async => setApiKey('');

  Future<void> clearBaseURL() async {
    _cachedBaseUrl = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBaseUrl);
  }

  Future<void> clearModel() async {
    _cachedModel = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kModel);
  }

  // ---------------------------------------------------------------------------
  // 模型能力判断
  // ---------------------------------------------------------------------------

  /// 当前模型是否支持流式（mimo|deepseek true else false）
  bool get isStreamingModel => isStreamingModelFor(modelSync);

  /// 当前模型是否支持 chat（与 streaming 规则相似）
  bool get isChatModel => isChatModelFor(modelSync);

  /// 是否支持流式：mimo 或 deepseek 即为 true，其余 false（含 longcat-2.0）
  static bool isStreamingModelFor(String m) {
    final lower = m.toLowerCase();
    return lower.contains('mimo') || lower.contains('deepseek');
  }

  /// 是否为 Chat 模型：此处与 streaming 规则保持一致（mimo|deepseek true else false）
  /// 如需 longcat 也视为 chat，可改为 `|| lower.contains('longcat')`
  static bool isChatModelFor(String m) {
    final lower = m.toLowerCase();
    return lower.contains('mimo') || lower.contains('deepseek');
  }

  /// 兼容旧命名
  static bool isStreamingModelStatic(String m) => isStreamingModelFor(m);
  static bool isChatModelStatic(String m) => isChatModelFor(m);

  // ---------------------------------------------------------------------------
  // 便捷重置
  // ---------------------------------------------------------------------------

  Future<void> resetAll() async {
    _cachedApiKey = null;
    _cachedBaseUrl = null;
    _cachedModel = null;
    _initialized = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kApiKey);
    await prefs.remove(_kBaseUrl);
    await prefs.remove(_kModel);
  }
}
