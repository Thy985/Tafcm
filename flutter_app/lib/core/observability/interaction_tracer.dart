/// InteractionTracer：记录语义层用户交互事件。
///
/// 使用 RingBuffer 存储，默认保留最近 1000 条事件。
/// 仅记录语义事件（UserTap / UserInput / UserDelete / UserFormatToggle / UserUndoRedo），
/// 不记录底层 Flutter Event（PointerDown / PointerMove 等）。
///
/// 落地 ADR-0021 §2.1（Interaction Trace）。
library;

import 'models.dart';
import 'ring_buffer.dart';

/// 用户交互轨迹记录器。
///
/// 线程安全通过 Dart 单线程模型保证。
/// 时间复杂度：记录 O(1)，遍历 O(n)。
class InteractionTracer {
  final RingBuffer<EditorInteractionEvent> _buffer;

  InteractionTracer({int capacity = 1000})
      : _buffer = RingBuffer<EditorInteractionEvent>(capacity);

  /// 当前记录数。
  int get count => _buffer.count;

  /// 最大容量。
  int get capacity => _buffer.capacity;

  /// 返回所有记录（从最旧到最新）。
  List<EditorInteractionEvent> get entries => _buffer.toList();

  /// 记录一条交互事件。
  void record(EditorInteractionEvent event) {
    _buffer.add(event);
  }

  /// 清空所有记录。
  void clear() {
    _buffer.clear();
  }
}