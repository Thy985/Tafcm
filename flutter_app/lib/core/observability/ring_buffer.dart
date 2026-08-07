/// 固定大小的环形缓冲区（Ring Buffer）。
///
/// 用于 Observability System 的事件存储：默认保留最近 N 条记录，
/// 新记录覆盖最旧记录。内存常驻，不写盘。
///
/// 落地 ADR-0021 §2.1（Interaction Trace 环形缓冲区）。
library;

/// 固定大小的环形缓冲区。
///
/// 线程安全通过 Dart 单线程模型保证（无并发问题）。
/// 时间复杂度：追加 O(1)，遍历 O(n)。
class RingBuffer<T> {
  final int _capacity;
  final List<T?> _buffer;
  int _head = 0; // 下一个写入位置
  int _count = 0; // 当前元素数

  RingBuffer(this._capacity)
      : assert(_capacity > 0, 'Capacity must be positive'),
        _buffer = List<T?>.filled(_capacity, null);

  /// 当前元素数（≤ [capacity]）。
  int get count => _count;

  /// 最大容量。
  int get capacity => _capacity;

  /// 是否已满。
  bool get isFull => _count == _capacity;

  /// 是否为空。
  bool get isEmpty => _count == 0;

  /// 追加一条记录。若已满，覆盖最旧记录。
  void add(T value) {
    _buffer[_head] = value;
    _head = (_head + 1) % _capacity;
    if (_count < _capacity) _count++;
  }

  /// 返回所有记录（从最旧到最新）。
  List<T> toList() {
    final result = <T>[];
    final start = isFull ? _head : 0;
    final len = _count;
    for (int i = 0; i < len; i++) {
      final idx = (start + i) % _capacity;
      final item = _buffer[idx];
      if (item != null) result.add(item);
    }
    return result;
  }

  /// 清空所有记录。
  void clear() {
    for (int i = 0; i < _capacity; i++) {
      _buffer[i] = null;
    }
    _head = 0;
    _count = 0;
  }
}