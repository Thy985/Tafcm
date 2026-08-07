/// BlockSelectionChrome：包裹每个 Block 的选中视觉 + 悬浮工具条 + 拖拽手柄。
///
/// 落地 Phase 3.5.4（Block Selection 视觉反馈）。
/// - 当 [EditorCoordinator.focusedId] == [blockId] 时显示选中描边
/// - 桌面：hover / 选中时显示 [BlockToolbar]
/// - 移动端：长按触发 [BlockToolbar]；选中态不自动显示（避免打字时常驻遮挡）
/// - 全禁用时整条隐藏（单块时上移/下移/删除均不可用）
/// - 左侧常驻 [BlockDragHandle]（拖拽重排入口）
///
/// 依赖方向（TC-ARCH-UI-5）：仅 import editor/editor_coordinator.dart（豁免）+ commands/ + themes/ + core/editing/block_types。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../../core/observability/models.dart' as obs;
import '../../editor/editor_coordinator.dart';
import '../../states/block_view_state.dart';
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
  Timer? _longPressTimer;

  bool get _isTouchDevice => MediaQuery.of(context).size.shortestSide < 600;

  bool _shouldShowToolbar() {
    final longPressed =
        widget.coordinator.viewStateOf(widget.blockId)?.longPressed ?? false;
    if (_isTouchDevice) {
      return longPressed;
    }
    return _hovering || widget.coordinator.focusedId == widget.blockId;
  }

  void _onLongPress() {
    widget.coordinator.recordInteraction(
      obs.UserLongPress(target: widget.blockId.value, timestamp: DateTime.now()),
    );
    final state =
        widget.coordinator.viewStateOf(widget.blockId) ??
        BlockViewState(id: widget.blockId);
    widget.coordinator.updateViewState(
      widget.blockId,
      state.copyWith(longPressed: true),
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerDown: (_) {
          _longPressTimer?.cancel();
          _longPressTimer = Timer(const Duration(milliseconds: 500), _onLongPress);
        },
        onPointerUp: (_) {
          _longPressTimer?.cancel();
        },
        onPointerCancel: (_) {
          _longPressTimer?.cancel();
        },
        behavior: HitTestBehavior.translucent,
        child: ListenableBuilder(
          listenable: widget.coordinator,
          builder: (context, _) {
            final selected = widget.coordinator.focusedId == widget.blockId;

            final showToolbar = _shouldShowToolbar();
            final tokens = EditorTokens.of(context);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: BlockDragHandle(
                    index: widget.index,
                    visible: selected || showToolbar,
                  ),
                ),
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
                      if (showToolbar)
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
      ),
    );
  }
}
