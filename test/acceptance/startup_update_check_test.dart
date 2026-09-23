import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:quiz_bank/core/update_service.dart';
import 'package:quiz_bank/features/settings/update_checker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验收：进入应用即自动检查更新（用户要求：一进去就弹「立即更新」）
/// 契约：每次启动都检查，有新版必弹对话框；无每日节流；同一天多次进入也弹。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('启动即查更新', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'QuizBank',
        packageName: 'com.example.quiz_bank',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    testWidgets('每次进入都弹更新对话框（无每日节流）', (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [updateServiceProvider.overrideWithValue(_HasUpdateService())],
        child: const MaterialApp(home: _Probe()),
      ));
      await t.pumpAndSettle();
      // 第一次进入：弹
      expect(find.text('发现新版本 v9.9.9'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      // 关掉，同一天再查一次：仍应弹（旧节流逻辑会静默 → 红）
      await t.tap(find.text('稍后'));
      await t.pumpAndSettle();
      await t.tap(find.text('再查'));
      await t.pumpAndSettle();
      expect(find.text('发现新版本 v9.9.9'), findsOneWidget, reason: '同一天多次进入也要弹，不做每日节流');
    });

    testWidgets('无新版时进入静默，不打扰', (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [updateServiceProvider.overrideWithValue(_NoUpdateService())],
        child: const MaterialApp(home: _Probe()),
      ));
      await t.pumpAndSettle();
      expect(find.text('发现新版本 v9.9.9'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}

/// 模拟进入应用：首帧后自动检查 + 提供手动重查按钮
class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) autoCheckUpdate(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => autoCheckUpdate(context),
          child: const Text('再查'),
        ),
      ),
    );
  }
}

class _HasUpdateService extends UpdateService {
  _HasUpdateService() : super(dio: Dio());
  @override
  Future<UpdateInfo?> checkForUpdate({required String currentVersion}) async => const UpdateInfo(
        version: '9.9.9',
        tag: 'v9.9.9',
        assetName: 'QuizBank-Setup-9.9.9-x64.exe',
        url: 'https://example.invalid/QuizBank-Setup-9.9.9-x64.exe',
        sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        notes: '',
      );
}

class _NoUpdateService extends UpdateService {
  _NoUpdateService() : super(dio: Dio());
  @override
  Future<UpdateInfo?> checkForUpdate({required String currentVersion}) async => null;
}
