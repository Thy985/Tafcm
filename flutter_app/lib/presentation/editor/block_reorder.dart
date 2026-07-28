/// Block 重排索引 → [MoveBlockCommand] 参数的纯函数（Phase 3.5.5）。
///
/// 与 [ReorderableListView.onReorderItem] 语义对齐：框架在触发回调前已扣除
/// 被移除项，等价于 `list.insert(newIndex, list.removeAt(oldIndex))`。
/// 因此落点参照块即原列表 [newIndex] 处的块；方向由 `newIndex < oldIndex` 决定。
///
/// 抽成纯函数便于单元测试，且避免 [EditorViewport] 内联逻辑无法覆盖。
library;

import '../../core/editing/block_types.dart';

/// [MoveBlockCommand] 三要素。
typedef MoveBlockReorderArgs = ({BlockId targetId, BlockId refId, bool before});

/// 由 ReorderableListView 的 (oldIndex, newIndex) 推导 [MoveBlockCommand] 参数。
///
/// 返回 null 的情形（调用方应跳过 dispatch）：
/// - 索引越界
/// - oldIndex == newIndex（无实际移动）
MoveBlockReorderArgs? blockReorderArgs(
  List<BlockId> ids,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 ||
      newIndex < 0 ||
      oldIndex >= ids.length ||
      newIndex >= ids.length) {
    return null;
  }
  if (oldIndex == newIndex) return null;
  return (
    targetId: ids[oldIndex],
    refId: ids[newIndex],
    before: newIndex < oldIndex,
  );
}
