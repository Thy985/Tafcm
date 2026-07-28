/// BlockDragHandle：块左侧拖拽手柄（ReorderableListView 拖拽入口）。
///
/// 落地 Phase 3.5.5（Drag & Drop 重排）。
/// 用 [ReorderableDragStartListener] 把按压 / 长按事件转交 ReorderableListView
/// 驱动重排；必须作为 ReorderableListView item 子树的一部分（才能经
/// `ReorderableListView.of` 找到祖先）。
library;

import 'package:flutter/material.dart';

/// 块拖拽手柄。
///
/// [index] 为该块在列表中的位置（与 itemBuilder 的 index 一致）。
/// [visible] 控制手柄明显度（悬浮 / 选中时更明显），但始终可交互。
class BlockDragHandle extends StatelessWidget {
  final int index;
  final bool visible;

  const BlockDragHandle({
    super.key,
    required this.index,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = Icon(
      Icons.drag_handle,
      size: 18,
      color: Theme.of(context)
          .colorScheme
          .onSurface
          .withValues(alpha: visible ? 0.6 : 0.25),
    );
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.6,
          duration: const Duration(milliseconds: 120),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: child,
          ),
        ),
      ),
    );
  }
}
