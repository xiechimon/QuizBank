import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/error_reporting.dart';
import '../../core/update_service.dart';

/// 当前版本号（package_info 失败时兜底 0.0.0，视为「永远可更新」不阻塞）
Future<String> currentAppVersion() async {
  try {
    final pi = await PackageInfo.fromPlatform();
    return pi.version;
  } catch (_) {
    return '0.0.0';
  }
}

/// 启动静默自动检查：每次进入都查，有新版必弹「立即更新」对话框；
/// 无新版或通道全灭则完全静默，不阻塞启动
Future<void> autoCheckUpdate(BuildContext context) async {
  try {
    final svc = ProviderScope.containerOf(context).read(updateServiceProvider);
    final info = await svc.checkForUpdate(currentVersion: await currentAppVersion());
    if (info != null && context.mounted) await showUpdateDialog(context, info);
  } catch (e) {
    CrashLogger.instance.log('update-auto-check', e);
  }
}

/// 手动检查（设置页）：无论结果都给反馈
Future<void> manualCheckUpdate(BuildContext context) async {
  UpdateInfo? info;
  try {
    final svc = ProviderScope.containerOf(context).read(updateServiceProvider);
    info = await svc.checkForUpdate(currentVersion: await currentAppVersion());
  } catch (_) {}
  if (!context.mounted) return;
  if (info == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已是最新版本')));
    return;
  }
  await showUpdateDialog(context, info);
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发现新版本 v${info.version}'),
      content: Text(info.notes.isEmpty ? '建议更新以获得最新功能与修复。' : info.notes),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            _downloadAndInstall(context, info);
          },
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
}

Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
  final svc = ProviderScope.containerOf(context).read(updateServiceProvider);
  final progress = ValueNotifier<double>(0);
  // 进度弹窗（不可点外关闭）
  final dialogFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('正在下载 v${info.version}'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v > 0 ? v : null),
              const SizedBox(height: 8),
              Text('${(v * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    ),
  );
  final file = await svc.download(info, onProgress: (r, t) {
    if (t > 0) progress.value = r / t;
  });
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // 关进度弹窗
  await dialogFuture.catchError((_) {});
  progress.dispose();
  if (!context.mounted) return;
  if (file == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('下载失败：网络不通或校验未通过。可稍后重试，或到 GitHub Releases 手动下载'),
    ));
    return;
  }
  if (defaultTargetPlatform != TargetPlatform.windows) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装包已下载：${file.path}')));
    return;
  }
  // 静默重装并重启（本进程将退出）
  await svc.installAndRestart(file);
}
