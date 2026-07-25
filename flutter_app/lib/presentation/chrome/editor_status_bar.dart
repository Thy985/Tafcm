/// EditorStatusBar：编辑器底部状态栏（chrome 组件）。
///
/// 落地 Phase 3.0 Task Contract §3.1（v1.1 新增 chrome/ 目录）+ §3.2 布局图。
/// **Phase 3.3 PR #1**：接入字数统计（§3.3.4）+ 移除 Undo/Redo 文字（已由 AppBar 按钮接管）。
///
/// **职责**：
/// - 显示当前块数
/// - **Phase 3.3**：显示字数统计（coordinator.wordCount）
/// - 显示聚焦块 ID（调试用,Phase 3.4+ 移除）
/// - **Phase 3.3 §3.3.2**：字号缩放控件（缩小 / 百分比 / 放大 / 重置,见 `_buildZoomControls`）
///
/// **不实现**（Phase 3.4+）：
/// - 光标位置（行 : 列）
/// - 主题切换控件
///
/// **依赖方向**（Hard Rule 8）：chrome/ 通过 [EditorCoordinator] 接收数据,
/// 不 import blocks/ / panels/。
library;

import 'package:flutter/material.dart';

import '../editor/editor_coordinator.dart';

/// 编辑器底部状态栏（chrome 组件）。
class EditorStatusBar extends StatelessWidget {
  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 当前字号缩放因子（Phase 3.3 §3.3.2，1.0 = 默认）。
  final double zoomScale;

  /// 放大 / 缩小 / 重置回调（Phase 3.3 §3.3.2）。
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomReset;

  const EditorStatusBar({
    super.key,
    required this.coordinator,
    this.zoomScale = 1.0,
    this.onZoomIn,
    this.onZoomOut,
    this.onZoomReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _buildItem('块数: ${coordinator.blockCount}'),
          const SizedBox(width: 16),
          // Phase 3.3 §3.3.4：字数统计
          _buildItem('字数: ${coordinator.wordCount}'),
          const SizedBox(width: 16),
          // Phase 3.3 §3.3.5：Undo/Redo 状态（简短文字提示,按钮在 AppBar）
          _buildItem(coordinator.canUndo ? '可撤销' : '—'),
          const SizedBox(width: 8),
          _buildItem(coordinator.canRedo ? '可重做' : '—'),
          const Spacer(),
          // Phase 3.3 §3.3.2：字号缩放控制（替代调试「聚焦」项）
          _buildZoomControls(),
        ],
      ),
    );
  }

  /// 字号缩放控制簇（Phase 3.3 §3.3.2）：缩小 / 百分比 / 放大 / 重置。
  Widget _buildZoomControls() {
    final percent = (zoomScale * 100).round();
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          iconSize: 16,
          tooltip: '缩小',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: onZoomOut,
        ),
        Text(
          '$percent%',
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          iconSize: 16,
          tooltip: '放大',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: onZoomIn,
        ),
        IconButton(
          icon: const Icon(Icons.restart_alt),
          iconSize: 16,
          tooltip: '重置字号',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: zoomScale != 1.0 ? onZoomReset : null,
        ),
      ],
    );
  }

  Widget _buildItem(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
    );
  }
}
