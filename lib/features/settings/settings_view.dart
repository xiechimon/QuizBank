// M3 极简设置：仅模型切换，无 Key 暴露
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai/ai_config.dart';
import 'update_checker.dart';

class _SettingsState {
  final String model;
  final bool loading;
  const _SettingsState({this.model = '', this.loading = true});
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
    await cfg.ensureInitialized();
    final model = await cfg.model;
    state = _SettingsState(model: model, loading: false);
  }

  Future<void> setModel(String m) async {
    await AIConfig.instance.setModel(m.trim());
    final model = await AIConfig.instance.model;
    state = _SettingsState(model: model, loading: false);
  }
}

@Deprecated('Use _settingsProvider / AIConfig.instance')
final aiConfigProvider = _settingsProvider;
typedef AiConfig = _SettingsState;

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(_settingsProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: st.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                // 单一设置项
                Card(
                  elevation: 0,
                  color: cs.surfaceContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.memory_rounded, size: 20, color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('解析模型', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                st.model == 'longcat-2.0' ? '一次返回' : '流式输出',
                                style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 紧凑下拉，无边框
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: AIConfig.availableModels.contains(st.model) ? st.model : AIConfig.defaultModel,
                              icon: Icon(Icons.expand_more_rounded, size: 20, color: cs.onSurfaceVariant),
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                              borderRadius: BorderRadius.circular(12),
                              items: AIConfig.availableModels
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                                  .toList(),
                              onChanged: (v) async {
                                if (v == null || v == st.model) return;
                                await ref.read(_settingsProvider.notifier).setModel(v);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切换为 $v')));
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _UpdateCard(),
                const SizedBox(height: 24),
                // 底部关于，弱化为脚注而非卡片
                Center(
                  child: Text(
                    'QuizBank · 1170 题 · 17 模块',
                    style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 检查更新卡片：显示当前版本，点击手动检查（多通道 + SHA256 校验见 UpdateService）
class _UpdateCard extends StatefulWidget {
  const _UpdateCard();

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    currentAppVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _checking
            ? null
            : () async {
                setState(() => _checking = true);
                await manualCheckUpdate(context);
                if (mounted) setState(() => _checking = false);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.system_update_alt_rounded, size: 20, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('检查更新', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _version.isEmpty ? '获取版本中…' : '当前版本 v$_version',
                      style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (_checking)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
