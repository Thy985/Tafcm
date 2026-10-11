/// EditorStatusBar：编辑器底部状态栏（chrome 组件）。
/// 落地 Phase 3.0 Task Contract §3.1（v1.1 新增 chrome/ 目录）+ §3.2 布局图。
/// **Phase 3.3 PR #1**：接入字数统计（§3.3.4）+ 移除 Undo/Redo 文字（已由 AppBar 按钮接管）。
/// **#246**：改用 ValueListenableBuilder 局部化刷新，仅块数/字数/Undo-Redo 变化时重建。
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../editor/autosave_service.dart';
import '../editor/editor_coordinator.dart';
import '../editor/editor_coordinator_notifiers.dart';
import '../themes/editor_tokens.dart';

/// 编辑器底部状态栏（chrome 组件）。
class EditorStatusBar extends StatefulWidget {
  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 当前字号缩放因子（Phase 3.3 §3.3.2，1.0 = 默认）。
  final double zoomScale;

  /// 放大 / 缩小 / 重置回调（Phase 3.3 §3.3.2）。
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomReset;

  /// 自动保存服务（issue #340-B）。非空时底栏显示真实保存状态
  /// （未保存 / 保存中 / 已保存 / 重试中）；null 时不显示保存项
  /// （测试 / golden 场景，保持既有渲染不变）。
  final AutosaveService? autosave;

  const EditorStatusBar({
    super.key,
    required this.coordinator,
    this.zoomScale = 1.0,
    this.onZoomIn,
    this.onZoomOut,
    this.onZoomReset,
    this.autosave,
  });

  @override
  State<EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends State<EditorStatusBar> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        height: EditorTokens.statusBarHeight,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        // P1 微修复（真机 CORE-005 阻塞）：真机字体比测试环境宽，状态栏 Row 在
        // 360dp 屏宽下溢出 12px。用 SingleChildScrollView 横向滚动兜底，宽屏
        // 仍正常显示，窄屏可滑动而非报 RenderFlex overflow。Spacer 在无 max
        // width 约束下不工作，改为固定 SizedBox 间距。
        //
        // #246：保留原 SingleChildScrollView + Row 结构（OverflowBar 会重排
        // 子项间距，与原视觉基线不符），仅把两个纯文本项换成块级订阅。
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // #246：块数订阅 blockCountNotifier，仅块数变化时重建
              ValueListenableBuilder<int>(
                builder: (context, blockCount, _) =>
                    _buildItem('块数: $blockCount'),
                valueListenable: widget.coordinator.blockCountNotifier,
              ),
              const SizedBox(width: 16),
              // Phase 3.3 §3.3.4：字数统计
              // #246：字数订阅 wordCountNotifier，仅字数变化时重建
              ValueListenableBuilder<int>(
                builder: (context, wordCount, _) =>
                    _buildItem('字数: $wordCount'),
                valueListenable: widget.coordinator.wordCountNotifier,
              ),
              // issue #340-B：真实保存状态（已保存 / 保存中 / 未保存 / 重试中）。
              // 此前底栏只有「可撤销/—」「可重做/—」，其中的 `—` 被误读为
              // 坏掉的保存指示；现显示真实落盘状态，消除"编辑是否安全"的焦虑。
              // 仅注入 autosave 时渲染（golden / 测试场景保持原渲染不变）。
              if (widget.autosave != null) ...[
                const SizedBox(width: 16),
                _SaveStatusItem(
                  coordinator: widget.coordinator,
                  autosave: widget.autosave!,
                ),
              ],
              const SizedBox(width: 16),
              // Phase 3.3 §3.3.5：Undo/Redo 状态（简短文字提示,按钮在 AppBar）
              // #246：订阅 undoRedoNotifier，仅 Undo/Redo 可用性变化时重建
              ValueListenableBuilder<bool>(
                builder: (context, canUndoRedo, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildItem(
                        widget.coordinator.canUndo ? '可撤销' : '—'),
                    const SizedBox(width: 8),
                    _buildItem(
                        widget.coordinator.canRedo ? '可重做' : '—'),
                  ],
                ),
                valueListenable: widget.coordinator.undoRedoNotifier,
              ),
              const SizedBox(width: 16),
              // Phase 3.3 §3.3.2：字号缩放控制（替代调试「聚焦」项）
              _buildZoomControls(),
            ],
          ),
        ),
      ),
    );
  }

  /// 字号缩放控制簇（Phase 3.3 §3.3.2）：缩小 / 百分比 / 放大 / 重置。
  Widget _buildZoomControls() {
    final percent = (widget.zoomScale * 100).round();
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          iconSize: 16,
          tooltip: '缩小',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: widget.onZoomOut,
        ),
        Text(
          '$percent%',
          style: const TextStyle(
            fontSize: EditorTokens.statusBarFontSize,
            fontFamily: 'monospace',
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          iconSize: 16,
          tooltip: '放大',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: widget.onZoomIn,
        ),
        IconButton(
          icon: const Icon(Icons.restart_alt),
          iconSize: 16,
          tooltip: '重置字号',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: widget.zoomScale != 1.0 ? widget.onZoomReset : null,
        ),
      ],
    );
  }

  Widget _buildItem(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: EditorTokens.statusBarFontSize,
        fontFamily: 'monospace',
      ),
    );
  }
}

/// 保存状态指示项（issue #340-B）。
///
/// 订阅 [AutosaveService.status] 流 + [EditorCoordinator.dirtyNotifier]，
/// 将两个信号合成真实状态：idle 时需结合 dirty 判断「已保存」还是「未保存」
/// （idle 本身仅表示"无待处理保存"，不表示"已落盘"）。
///
/// 未注入 autosave 时不渲染（null），保持测试 / golden 场景的既有渲染不变。
class _SaveStatusItem extends StatefulWidget {
  final EditorCoordinator coordinator;
  final AutosaveService autosave;

  const _SaveStatusItem({
    required this.coordinator,
    required this.autosave,
  });

  @override
  State<_SaveStatusItem> createState() => _SaveStatusItemState();
}

class _SaveStatusItemState extends State<_SaveStatusItem> {
  AutosaveStatus _status = AutosaveStatus.idle;
  StreamSubscription<AutosaveStatus>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.autosave.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.coordinator.dirtyNotifier,
      builder: (context, isDirty, _) => _buildLabel(context, isDirty),
    );
  }

  Widget _buildLabel(BuildContext context, bool isDirty) {
    final tokens = EditorTokens.of(context);
    final (text, color) = switch (_status) {
      AutosaveStatus.saving => ('保存中…', tokens.textSecondary),
      AutosaveStatus.saved => ('已保存', tokens.textSecondary),
      AutosaveStatus.error => ('保存失败', Theme.of(context).colorScheme.error),
      AutosaveStatus.retrying => ('重试中…', Theme.of(context).colorScheme.error),
      AutosaveStatus.idle => isDirty
          ? ('未保存', tokens.textSecondary)
          : ('已保存', tokens.textSecondary),
    };
    return Text(
      text,
      style: TextStyle(
        fontSize: EditorTokens.statusBarFontSize,
        fontFamily: 'monospace',
        color: color,
      ),
    );
  }
}
