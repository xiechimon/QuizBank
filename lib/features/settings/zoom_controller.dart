// 整体 UI 缩放（类浏览器 zoom）
// 范围 0.7–1.6，步长 0.1，默认 1.0；Ctrl/Cmd + =/−/0 快捷键联动。
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ZoomController extends Notifier<double> {
  static const double _min = 0.7;
  static const double _max = 1.6;
  static const double _step = 0.1;
  static const double _defaultScale = 1.0;

  @override
  double build() => _defaultScale;

  void zoomIn() {
    final next = (state + _step).clamp(_min, _max);
    state = double.parse(next.toStringAsFixed(1));
  }

  void zoomOut() {
    final next = (state - _step).clamp(_min, _max);
    state = double.parse(next.toStringAsFixed(1));
  }

  void reset() => state = _defaultScale;
}

final zoomScaleProvider = NotifierProvider<ZoomController, double>(ZoomController.new);