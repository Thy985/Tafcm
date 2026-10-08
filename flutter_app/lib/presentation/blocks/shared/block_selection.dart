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

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../../core/observability/models.dart' as obs;
import '../../editor/editor_coordinator.dart';
import '../../editor/editor_coordinator_notifiers.dart';
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

  /// 按下位置与「本次触摸已判定为滑动」标记（#328）。
  ///
  /// 旧实现只要触摸持续 500ms 就触发长按选中——**慢速横向滑动表格途中也
  /// 会触发**（QA 实测：工具条在滑动中弹出、块状态重建打断横滚手势）。
  /// 移动超过 touch slop 即判定为滑动，取消本次长按计时。
  Offset? _downPosition;
  bool _longPressCancelled = false;

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
        onPointerDown: (event) {
          // R-C1 修复：仅触屏指针启动长按定时器，桌面鼠标点击/拖动不触发。
          if (!_isTouchDevice) return;
          _longPressTimer?.cancel();
          _downPosition = event.position;
          _longPressCancelled = false;
          _longPressTimer = Timer(const Duration(milliseconds: 500), _onLongPress);
        },
        onPointerMove: (event) {
          // #328：手指移动超过 touch slop = 滑动而非长按——取消计时，
          // 让横向滑动（如表格横滚）不被滑动途中的选中/工具条重建打断。
          if (_longPressCancelled || _downPosition == null) return;
          if ((event.position - _downPosition!).distance > kTouchSlop) {
            _longPressCancelled = true;
            _longPressTimer?.cancel();
          }
        },
        onPointerUp: (_) {
          _longPressTimer?.cancel();
        },
        onPointerCancel: (_) {
          _longPressTimer?.cancel();
        },
        behavior: HitTestBehavior.translucent,
        // #246：只订阅本块的块级 notifier + 聚焦 id（用于选中描边跨块联动）。
        // 原为 ListenableBuilder(listenable: coordinator)——整棵视口每块都
        // 订阅全局 coordinator，任一块的任意状态变化都会让所有块重建。
        // 现拆为：
        // - 块级 notifier：文本 / 模式 / 长按态等本块状态
        // - focusNotifier：聚焦块变化时，新旧两块重建（其余块跳过）
        child: ValueListenableBuilder<int>(
          valueListenable: widget.coordinator.blockNotifiers.notifierOf(widget.blockId),
          builder: (context, blockVersion, _) =>
              ValueListenableBuilder<BlockId?>(
            valueListenable: widget.coordinator.focusNotifier,
            builder: (context, focusedId, _) {
              final selected = focusedId == widget.blockId;

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
      ),
    );
  }
}
