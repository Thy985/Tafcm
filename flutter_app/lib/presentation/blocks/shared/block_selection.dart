/// BlockSelectionChrome：包裹每个 Block 的选中视觉 + 悬浮工具条 + 拖拽手柄。
///
/// 落地 Phase 3.5.4（Block Selection 视觉反馈）。
/// - 当 [EditorCoordinator.focusedId] == [blockId] 时显示选中描边
/// - 悬浮 / 选中时显示 [BlockToolbar]
/// - 左侧常驻 [BlockDragHandle]（拖拽重排入口）
///
/// 依赖方向（TC-ARCH-UI-5）：仅 import editor/editor_coordinator.dart（豁免）+ commands/ + themes/ + core/editing/block_types。
library;

import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../editor/editor_coordinator.dart';
import '../../themes/editor_tokens.dart';
import 'block_drag_handle.dart';
import 'block_toolbar.dart';

/// 块选中视觉外壳。
class BlockSelectionChrome extends StatefulWidget {
  final EditorCoordinator coordinator;
  final BlockId blockId;
  final int index;
  final Widget child;

  const BlockSelectionChrome({
    super.key,
    required this.coordinator,
    required this.blockId,
    required this.index,
    required this.child,
  });

  @override
  State<BlockSelectionChrome> createState() => _BlockSelectionChromeState();
}

class _BlockSelectionChromeState extends State<BlockSelectionChrome> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: ListenableBuilder(
        listenable: widget.coordinator,
        builder: (context, _) {
          final selected = widget.coordinator.focusedId == widget.blockId;
          final showChrome = _hovering || selected;
          final tokens = EditorTokens.of(context);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧拖拽手柄槽（常驻，避免显隐导致的布局抖动）
              SizedBox(
                width: 24,
                child: BlockDragHandle(
                  index: widget.index,
                  visible: showChrome,
                ),
              ),
              // 内容 + 选中描边
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(EditorTokens.blockRadius),
                        border: Border.all(
                          color: selected
                              ? tokens.borderFocused
                              : Colors.transparent,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(4),
                      child: widget.child,
                    ),
                    if (showChrome)
                      Positioned(
                        top: -10,
                        right: 4,
                        child: BlockToolbar(
                          coordinator: widget.coordinator,
                          blockId: widget.blockId,
                          index: widget.index,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
