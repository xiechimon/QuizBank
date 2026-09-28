// 验证 zoom controller 的状态机边界——修复前后行为不变的部分
// 与 app.dart 的 textScaler 注入协同验证整体修复
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_bank/features/settings/zoom_controller.dart';

void main() {
  group('ZoomController', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('初始 scale = 1.0', () {
      expect(container.read(zoomScaleProvider), 1.0);
    });

    test('zoomIn 步长 0.1', () {
      container.read(zoomScaleProvider.notifier).zoomIn();
      expect(container.read(zoomScaleProvider), 1.1);
    });

    test('zoomIn 到 max=1.6 后 clamp，不再上涨', () {
      final n = container.read(zoomScaleProvider.notifier);
      for (var i = 0; i < 20; i++) {
        n.zoomIn();
      }
      expect(container.read(zoomScaleProvider), 1.6);
    });

    test('zoomOut 到 min=0.7 后 clamp，不再下降', () {
      final n = container.read(zoomScaleProvider.notifier);
      for (var i = 0; i < 20; i++) {
        n.zoomOut();
      }
      expect(container.read(zoomScaleProvider), 0.7);
    });

    test('reset 回 1.0', () {
      container.read(zoomScaleProvider.notifier).zoomIn();
      container.read(zoomScaleProvider.notifier).zoomIn();
      container.read(zoomScaleProvider.notifier).reset();
      expect(container.read(zoomScaleProvider), 1.0);
    });
  });
}