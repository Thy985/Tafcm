/// TransactionTracer：记录每个 Transaction 的 before/after 状态。
///
/// 解决"为什么状态突然坏了"——通过记录每个 Transaction 的
/// before/after 摘要 + Document fingerprint，可以精确定位
/// 是哪个 Transaction 导致状态变化。
///
/// 落地 ADR-0021 §2.3。
library;

import 'models.dart';
import 'ring_buffer.dart';

/// Transaction 状态变化记录器。
///
/// 通过 [RingBuffer] 存储最近 N 条 Transaction 记录。
class TransactionTracer {
  final RingBuffer<TransactionTraceEntry> _buffer;

  TransactionTracer({int capacity = 50}) : _buffer = RingBuffer(capacity);

  /// 当前记录数。
  int get count => _buffer.count;

  /// 返回所有记录（从最旧到最新）。
  List<TransactionTraceEntry> get entries => _buffer.toList();

  /// 记录一条 Transaction 状态变化。
  void record(TransactionTraceEntry entry) {
    _buffer.add(entry);
  }

  /// 清空所有记录。
  void clear() => _buffer.clear();
}