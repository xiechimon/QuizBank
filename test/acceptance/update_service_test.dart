import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quiz_bank/core/update_service.dart';
import 'package:quiz_bank/features/settings/settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验收：应用内自更新（无代理环境多通道）
/// 契约：
///  - 检查更新通道顺序：raw main/latest.json 直连 → 镜像轮询 → GitHub API release 资产
///  - 下载通道顺序：直连 → 镜像轮询；安装前 SHA256 强制校验（校验失败拒绝，防镜像污染）
///  - 全通道失败静默返回 null，不抛异常不阻塞启动
///  - 设置页提供「检查更新」入口，无更新时给「已是最新版本」反馈
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final payload = Uint8List.fromList(utf8.encode('fake-installer-payload'));
  final payloadSha = crypto.sha256.convert(payload).toString();

  Map<String, dynamic> latestJson({String version = '9.9.9', String sha = ''}) => {
        'version': version,
        'tag': 'v$version',
        'assetName': 'QuizBank-Setup-$version-x64.exe',
        'url': 'https://github.com/xiechimon/QuizBank/releases/download/v$version/QuizBank-Setup-$version-x64.exe',
        'sha256': sha.isEmpty ? payloadSha : sha,
        'notes': '测试更新说明',
      };

  ResponseBody jsonBody(Object j) => ResponseBody.fromString(
        jsonEncode(j),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  ResponseBody bytesBody(List<int> b) => ResponseBody.fromBytes(b, 200);

  DioException blocked(RequestOptions o) =>
      DioException(requestOptions: o, type: DioExceptionType.connectionError, error: 'blocked');

  group('自更新', () {
    test('compareVersions 按段数值比较', () {
      expect(UpdateService.compareVersions('1.10.0', '1.9.9'), 1);
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.0', '1.0.1'), -1);
      expect(UpdateService.compareVersions('2.0', '1.9.9'), 1);
    });

    test('检查更新: raw 直连成功返回新版信息', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((o) async {
        if (o.uri.host == 'raw.githubusercontent.com' && o.uri.path.endsWith('latest.json')) {
          return jsonBody(latestJson());
        }
        throw blocked(o);
      });
      final svc = UpdateService(dio: dio);
      final info = await svc.checkForUpdate(currentVersion: '1.0.0');
      expect(info, isNotNull);
      expect(info!.version, '9.9.9');
      expect(info.sha256, payloadSha);
      // 旧版本号更高时不提示更新
      expect(await svc.checkForUpdate(currentVersion: '99.0.0'), isNull);
    });

    test('检查更新: 直连被墙时镜像回退', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((o) async {
        final u = o.uri.toString();
        if (u.startsWith('https://ghfast.top/')) {
          return jsonBody(latestJson());
        }
        throw blocked(o); // raw 直连与其他镜像全部失败
      });
      final svc = UpdateService(dio: dio);
      final info = await svc.checkForUpdate(currentVersion: '1.0.0');
      expect(info, isNotNull, reason: '无代理环境应经镜像拿到更新信息');
      expect(info!.version, '9.9.9');
    });

    test('检查更新: raw 全灭时 GitHub API 通道回退', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((o) async {
        final u = o.uri.toString();
        if (u.startsWith('https://api.github.com/repos/') && u.endsWith('/releases/latest')) {
          return jsonBody({
            'tag_name': 'v9.9.9',
            'assets': [
              {'name': 'latest.json', 'browser_download_url': 'https://github.com/xiechimon/QuizBank/releases/download/v9.9.9/latest.json'},
            ],
          });
        }
        if (o.uri.host == 'github.com' && o.uri.path.endsWith('latest.json')) {
          return jsonBody(latestJson());
        }
        throw blocked(o);
      });
      final svc = UpdateService(dio: dio);
      final info = await svc.checkForUpdate(currentVersion: '1.0.0');
      expect(info, isNotNull);
      expect(info!.version, '9.9.9');
    });

    test('检查更新: 全通道失败静默返回 null', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((o) async => throw blocked(o));
      final svc = UpdateService(dio: dio);
      expect(await svc.checkForUpdate(currentVersion: '1.0.0'), isNull);
    });

    test('下载: SHA256 匹配才接受', () async {
      final tmp = await Directory.systemTemp.createTemp('qb_upd_ok');
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((o) async => bytesBody(payload));
      final svc = UpdateService(dio: dio);
      final info = UpdateInfo.fromJson(latestJson());
      final f = await svc.download(info, destDir: tmp);
      expect(f, isNotNull);
      expect(await f!.readAsBytes(), payload);
      // 校验和不匹配 → 拒绝且清理
      final bad = UpdateInfo.fromJson(latestJson(sha: '0' * 64));
      expect(await svc.download(bad, destDir: tmp), isNull, reason: 'SHA256 不匹配必须拒绝安装');
      expect(File('${tmp.path}${Platform.pathSeparator}${bad.assetName}').existsSync(), isFalse);
      await tmp.delete(recursive: true);
    });

    test('下载: 直连被墙时镜像回退且仍校验', () async {
      final tmp = await Directory.systemTemp.createTemp('qb_upd_mirror');
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((o) async {
        final u = o.uri.toString();
        if (u.startsWith('https://gh-proxy.com/')) return bytesBody(payload);
        throw blocked(o); // github 直连与第一个镜像失败
      });
      final svc = UpdateService(dio: dio);
      final f = await svc.download(UpdateInfo.fromJson(latestJson()), destDir: tmp);
      expect(f, isNotNull, reason: '应轮询到可用镜像完成下载');
      expect(await f!.readAsBytes(), payload);
      await tmp.delete(recursive: true);
    });

    testWidgets('设置页: 手动检查更新，无更新时提示已是最新', (t) async {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'QuizBank',
        packageName: 'com.example.quiz_bank',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await t.pumpWidget(ProviderScope(
        overrides: [updateServiceProvider.overrideWithValue(_NoUpdateService())],
        child: const MaterialApp(home: SettingsView()),
      ));
      await t.pumpAndSettle();
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.textContaining('当前版本'), findsOneWidget);
      await t.tap(find.text('检查更新'));
      await t.pumpAndSettle();
      expect(find.text('已是最新版本'), findsOneWidget);
    });
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions opts) _handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      _handler(options);

  @override
  void close({bool force = false}) {}
}

class _NoUpdateService extends UpdateService {
  _NoUpdateService() : super(dio: Dio());
  @override
  Future<UpdateInfo?> checkForUpdate({required String currentVersion}) async => null;
}
