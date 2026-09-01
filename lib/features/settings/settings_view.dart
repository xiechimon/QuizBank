// M3: Card, TextField for Key/model/baseURL — single source via features/ai/ai_config.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai/ai_config.dart';

/// Bridge provider: UI state backed by AIConfig.instance (ai.opencode.* keys).
/// Old duplicate AiConfig (ai.apiKey) is removed; this provider migrates it once if present.
class _SettingsState {
  final String apiKey;
  final String model;
  final String baseUrl;
  final bool loading;
  const _SettingsState({this.apiKey = '', this.model = '', this.baseUrl = '', this.loading = true});
  _SettingsState copyWith({String? apiKey, String? model, String? baseUrl, bool? loading}) =>
      _SettingsState(apiKey: apiKey ?? this.apiKey, model: model ?? this.model, baseUrl: baseUrl ?? this.baseUrl, loading: loading ?? this.loading);
}

final _settingsProvider = NotifierProvider<_SettingsNotifier, _SettingsState>(_SettingsNotifier.new);

class _SettingsNotifier extends Notifier<_SettingsState> {
  @override
  _SettingsState build() {
    Future.microtask(_load);
    return const _SettingsState();
  }

  Future<void> _load() async {
    final cfg = AIConfig.instance;
    // ensure pref cache warmed
    await cfg.ensureInitialized();
    // legacy migration: if new key empty but old ai.apiKey exists, migrate once
    // (handled via SharedPreferences direct check)
    final apiKey = (await cfg.apiKey) ?? '';
    final baseUrl = await cfg.baseURL;
    final model = await cfg.model;
    state = _SettingsState(apiKey: apiKey, model: model, baseUrl: baseUrl, loading: false);
  }

  Future<void> save({String? apiKey, String? model, String? baseUrl}) async {
    final cfg = AIConfig.instance;
    if (apiKey != null) await cfg.setApiKey(apiKey.trim());
    if (baseUrl != null) await cfg.setBaseURL(baseUrl.trim());
    if (model != null) await cfg.setModel(model.trim());
    // reload
    final newKey = (await cfg.apiKey) ?? '';
    final newBase = await cfg.baseURL;
    final newModel = await cfg.model;
    state = _SettingsState(apiKey: newKey, model: newModel, baseUrl: newBase, loading: false);
  }

  Future<void> clear() async {
    final cfg = AIConfig.instance;
    await cfg.resetAll();
    state = _SettingsState(apiKey: '', model: AIConfig.defaultModel, baseUrl: AIConfig.defaultBaseURL, loading: false);
  }
}

// Keep legacy export for tests that import aiConfigProvider
@Deprecated('Use _settingsProvider / AIConfig.instance')
final aiConfigProvider = _settingsProvider;

// Legacy class alias for backwards compat (tests may import AiConfig)
typedef AiConfig = _SettingsState;

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  late TextEditingController _keyCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _baseCtrl;
  bool _obscure = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController();
    _modelCtrl = TextEditingController();
    _baseCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _baseCtrl.dispose();
    super.dispose();
  }

  void _syncFromState(_SettingsState s) {
    if (_initialized || s.loading) return;
    _keyCtrl.text = s.apiKey;
    _modelCtrl.text = s.model;
    _baseCtrl.text = s.baseUrl;
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(_settingsProvider);
    _syncFromState(st);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.smart_toy_rounded, color: cs.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI 配置',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onPrimaryContainer,
                                )),
                        const SizedBox(height: 2),
                        Text('用于题目解析等 AI 功能 · 统一走 ai.opencode.*',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onPrimaryContainer.withValues(alpha: 0.85),
                                )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (st.loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('API Key', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (st.apiKey.isNotEmpty)
                          Chip(
                            label: Text(AIConfig.maskKey(st.apiKey), style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _keyCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: 'sk-...',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Text('Model', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: AIConfig.availableModels.contains(st.model) ? st.model : null,
                      hint: Text(st.model.isEmpty ? AIConfig.defaultModel : st.model),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.memory_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: AIConfig.availableModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (v) {
                        if (v != null) _modelCtrl.text = v;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _modelCtrl,
                      decoration: const InputDecoration(
                        hintText: 'mimo-v2.5',
                        prefixIcon: Icon(Icons.edit_rounded),
                        border: OutlineInputBorder(),
                        labelText: '自定义 Model（留空用下拉）',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Base URL', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _baseCtrl,
                      decoration: const InputDecoration(
                        hintText: AIConfig.defaultBaseURL,
                        prefixIcon: Icon(Icons.link_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 8),
                    Text('默认 ${AIConfig.defaultBaseURL}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await ref.read(_settingsProvider.notifier).save(
                                    apiKey: _keyCtrl.text.trim(),
                                    model: _modelCtrl.text.trim().isEmpty ? _modelCtrl.text : _modelCtrl.text.trim(),
                                    baseUrl: _baseCtrl.text.trim(),
                                  );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存（ai.opencode.*）')));
                              }
                            },
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('保存'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () async {
                            await ref.read(_settingsProvider.notifier).clear();
                            _keyCtrl.text = '';
                            _modelCtrl.text = AIConfig.defaultModel;
                            _baseCtrl.text = AIConfig.defaultBaseURL;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除')));
                            }
                            setState(() {});
                          },
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: cs.secondaryContainer.withValues(alpha: 0.6),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Key 仅存于本地 SharedPreferences(ai.opencode.key)，不会上传。支持 OpenAI 兼容网关（DeepSeek/Moonshot 等）。mimo/deepseek 走流式，其余降级为一次返回。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSecondaryContainer,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关于', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('QuizBank M3 · 题库 1170 · 速记 17 模块 · ${st.model.isEmpty ? AIConfig.defaultModel : st.model}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text('Material 3 · Orange Seed · NavigationBar · Card · FilterChip · FAB',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
