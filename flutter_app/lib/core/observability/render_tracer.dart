/// RenderTracer：记录渲染/导出管线可观测事件。
///
/// 使用 RingBuffer 存储，默认保留最近 500 条事件。
/// 记录代码块主题切换、language chip 显示、PDF CJK 字体回退等事件。
///
/// 与 [InteractionTracer] 区分：后者记录用户语义交互（tap/input/undo），
/// 本类记录渲染/导出管线的内部决策事件（theme select/chip render/font fallback）。
///
/// 落地 ADR-0023 §2.1 扩展（渲染可观测层）。
library;

import 'models.dart';
import 'ring_buffer.dart';

/// 渲染/导出轨迹记录器。
///
/// 线程安全通过 Dart 单线程模型保证。
/// 时间复杂度：记录 O(1)，遍历 O(n)。
class RenderTracer {
  final RingBuffer<RenderObservabilityEvent> _buffer;

  RenderTracer({int capacity = 500})
      : _buffer = RingBuffer<RenderObservabilityEvent>(capacity);

  /// 当前记录数。
  int get count => _buffer.count;

  /// 最大容量。
  int get capacity => _buffer.capacity;

  /// 返回所有记录（从最旧到最新）。
  List<RenderObservabilityEvent> get entries => _buffer.toList();

  /// 记录一条渲染/导出事件。
  void record(RenderObservabilityEvent event) {
    _buffer.add(event);
  }

  /// 清空所有记录。
  void clear() {
    _buffer.clear();
  }
}