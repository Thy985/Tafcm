/// 通用泛型状态历史管理器。
///
/// 提供 Undo / Redo 栈，支持任意类型 `<T>` 的状态快照或操作日志。
/// 默认上限 50，可配置。
///
/// Phase 2.6 起，[EditorHistory] 包装 `HistoryManager<Transaction>` 提供
/// Transaction 级 API（coalescing / pushOperation / 等），本类保持向后兼容。
///
/// 详见 ADR-0008 §6（包装而非重写）。
library;

class HistoryManager<T> {
  final List<T> _undoStack = [];
  final List<T> _redoStack = [];
  final int maxHistorySize;

  HistoryManager({this.maxHistorySize = 50});

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// 当前栈顶状态（最新 push 的状态）。
  ///
  /// Phase 2.6 新增：用于 EditorHistory coalescing 检查。
  /// 栈为空时返回 null。
  T? get lastOrNull => _undoStack.isEmpty ? null : _undoStack.last;

  /// Redo 栈顶状态（下一个将被 redo 的条目）。
  ///
  /// Phase 3.3：op-delta 模型下，coordinator 需在 redo 前取得「将被重做的
  /// Transaction」，以便把同一条目回环压入对应栈（快照交换模型要求 currentState
  /// 携带可重放的 ops，而非空占位）。栈为空时返回 null。
  T? get redoLastOrNull => _redoStack.isEmpty ? null : _redoStack.last;

  /// 替换栈顶状态（用于 coalescing 合并）。
  ///
  /// Phase 2.6 新增：EditorHistory.pushOperation 检测到可合并 op 时，
  /// 构造新的合并 Transaction 并替换栈顶，保持栈不变长。
  ///
  /// 栈为空时抛 [StateError]（调用方应先检查 lastOrNull != null）。
  void replaceLast(T newItem) {
    if (_undoStack.isEmpty) {
      throw StateError('replaceLast called on empty undo stack');
    }
    _undoStack[_undoStack.length - 1] = newItem;
  }

  void push(T state) {
    _undoStack.add(state);
    _redoStack.clear();

    if (_undoStack.length > maxHistorySize) {
      _undoStack.removeAt(0);
    }
  }

  T? undo(T currentState) {
    if (!canUndo) return null;

    _redoStack.add(currentState);
    return _undoStack.removeLast();
  }

  T? redo(T currentState) {
    if (!canRedo) return null;

    _undoStack.add(currentState);
    return _redoStack.removeLast();
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
