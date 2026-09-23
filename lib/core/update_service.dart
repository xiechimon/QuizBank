import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 更新元数据。CI 发版时生成 latest.json：
/// 作为 Release 资产上传 + 提交回 main 分支（raw 可经镜像获取，解决无代理环境）。
class UpdateInfo {
  final String version;
  final String tag;
  final String assetName;
  final String url;
  final String sha256;
  final String notes;

  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.assetName,
    required this.url,
    required this.sha256,
    this.notes = '',
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        version: (j['version'] ?? '') as String,
        tag: (j['tag'] ?? '') as String,
        assetName: (j['assetName'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        sha256: ((j['sha256'] ?? '') as String).toLowerCase(),
        notes: (j['notes'] ?? '') as String,
      );

  bool get isValid => version.isNotEmpty && url.isNotEmpty && sha256.length == 64;
}

/// 多通道更新检查 + 下载校验（面向无代理的国内网络环境）：
///  - 检查：raw main/latest.json 直连 → 镜像轮询 → GitHub API releases/latest 资产
///  - 下载：直连 → 镜像轮询；安装前 SHA256 强制校验，校验失败拒绝（防第三方镜像污染）
///  - 任一通道全灭：静默 null，不阻塞启动
class UpdateService {
  UpdateService({Dio? dio, this.repo = 'xiechimon/QuizBank'}) : _dio = dio ?? Dio();

  final Dio _dio;
  final String repo;

  /// 第三方 GitHub 前缀镜像（按可用性排序轮询；均不可靠故必须配 SHA256 校验）
  static const List<String> mirrors = [
    'https://ghfast.top/',
    'https://gh-proxy.com/',
    'https://ghproxy.net/',
  ];

  static const _callTimeout = Duration(seconds: 12);

  String get _rawLatestUrl => 'https://raw.githubusercontent.com/$repo/main/latest.json';
  String get _apiLatestUrl => 'https://api.github.com/repos/$repo/releases/latest';

  /// 纯函数版本比较：按段数值比较（1.10.0 > 1.9.9），缺段按 0
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }

  /// 有新版返回 UpdateInfo，否则 null（含「通道全灭」情形）
  Future<UpdateInfo?> checkForUpdate({required String currentVersion}) async {
    final info = await fetchLatestInfo();
    if (info == null) return null;
    return compareVersions(info.version, currentVersion) > 0 ? info : null;
  }

  Future<UpdateInfo?> fetchLatestInfo() async {
    // 通道 A：raw main/latest.json（直连 → 镜像）
    for (final u in [_rawLatestUrl, ...mirrors.map((m) => '$m$_rawLatestUrl')]) {
      final info = await _getJsonInfo(u);
      if (info != null) return info;
    }
    // 通道 B：GitHub API → release 资产里的 latest.json（直连 → 镜像）
    try {
      final res = await _dio
          .get<String>(_apiLatestUrl,
              options: Options(
                responseType: ResponseType.plain,
                headers: {'Accept': 'application/vnd.github+json'},
                validateStatus: (s) => s == 200,
              ))
          .timeout(_callTimeout);
      final rel = jsonDecode(res.data ?? '') as Map<String, dynamic>;
      final assets = (rel['assets'] as List?) ?? const [];
      for (final a in assets) {
        if (a is Map && a['name'] == 'latest.json') {
          final dl = a['browser_download_url'] as String?;
          if (dl == null) break;
          for (final u in [dl, ...mirrors.map((m) => '$m$dl')]) {
            final info = await _getJsonInfo(u);
            if (info != null) return info;
          }
          break;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<UpdateInfo?> _getJsonInfo(String url) async {
    try {
      final res = await _dio
          .get<String>(url,
              options: Options(
                responseType: ResponseType.plain,
                validateStatus: (s) => s == 200,
              ))
          .timeout(_callTimeout);
      final body = res.data;
      if (body == null || body.isEmpty) return null;
      final info = UpdateInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
      return info.isValid ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// 下载安装包：直连 → 镜像轮询；每个候选下载后强制 SHA256 校验，
  /// 校验失败删除文件换下一通道（校验和与二进制不同源，镜像污染装不进来）。
  Future<File?> download(UpdateInfo info, {void Function(int received, int total)? onProgress, Directory? destDir}) async {
    final dir = destDir ?? await getTemporaryDirectory();
    final dest = '${dir.path}${Platform.pathSeparator}${info.assetName}';
    for (final u in [info.url, ...mirrors.map((m) => '$m${info.url}')]) {
      try {
        await _dio.download(u, dest, onReceiveProgress: onProgress, deleteOnError: true);
        final f = File(dest);
        final sum = crypto.sha256.convert(await f.readAsBytes()).toString();
        if (sum == info.sha256) return f;
        try {
          await f.delete();
        } catch (_) {}
      } catch (_) {}
    }
    return null;
  }

  /// Windows 静默重装并重启：bat 延时 → Inno /VERYSILENT → 拉起当前 exe → 本进程退出
  Future<void> installAndRestart(File installer) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    final relaunch = Platform.resolvedExecutable;
    final bat = File('${installer.parent.path}${Platform.pathSeparator}qb_update.bat');
    await bat.writeAsString(
      '@echo off\r\n'
      'ping 127.0.0.1 -n 4 > nul\r\n'
      '"${installer.path}" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS\r\n'
      'start "" "$relaunch"\r\n'
      'del "%~f0"\r\n',
    );
    await Process.start('cmd.exe', ['/c', bat.path], mode: ProcessStartMode.detached);
    exit(0);
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
