/// CommandTracer：记录每个 [EditorCommand] 的执行轨迹。
///
/// 这是 Tafcm 可观测系统最重要的一层——Command 是系统行为的原子单位。
/// 大量编辑器 bug 发生在 Command 生成/参数/执行层面。
///
/// 落地 ADR-0021 §2.2。
library;

import 'models.dart';
import 'ring_buffer.dart';

/// Command 执行轨迹记录器。
///
/// 通过 [RingBuffer] 存储最近 N 条 Command 记录，内存常驻，不写盘。
class CommandTracer {
  final RingBuffer<CommandTraceEntry> _buffer;

  CommandTracer({int capacity = 500}) : _buffer = RingBuffer(capacity);

  /// 当前记录数。
  int get count => _buffer.count;

  /// 返回所有记录（从最旧到最新）。
  List<CommandTraceEntry> get entries => _buffer.toList();

  /// 记录一条 Command 执行轨迹。
  void record(CommandTraceEntry entry) {
    _buffer.add(entry);
  }

  /// 清空所有记录。
  void clear() => _buffer.clear();
}