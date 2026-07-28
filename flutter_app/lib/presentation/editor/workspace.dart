/// Workspace + EditorViewport：编辑区布局组件（含页面宽度控制 + 块列表渲染）。
///
/// 从 editor_shell.dart 提取（2026-07-28），满足 AGENTS.md §1.2 400 行限制。
///
/// - [kMaxPageWidth]：页面最大内容宽度（Phase 3.4 Slice 5 / 3.4.8）。
/// - [Workspace]：编辑区 + 侧栏组合（Row → Expanded → Center → ConstrainedBox）。
/// - [EditorViewport]：编辑视口（ReorderableListView，渲染所有 Block）。
library;

import 'package:flutter/material.dart';

import '../../core/editing/block_types.dart';
import '../blocks/block_renderer.dart';
import '../blocks/shared/block_selection.dart';
import '../commands/commands.dart';
import '../panels/side_panel_host.dart';
import '../states/block_view_state.dart';
import '../themes/editor_tokens.dart';
import 'block_reorder.dart';
import 'editor_coordinator.dart';

/// 页面最大内容宽度（Phase 3.4 Slice 5 / 3.4.8 页面宽度控制）。
///
/// 编辑视口在宽屏（> 720）下约束于此值并居中；窄屏（< 720）不受影响。
/// 纯布局常量，无状态、不持久化（如需可调宽度，后续接入设置面板）。
const double kMaxPageWidth = 720.0;

/// Workspace：编辑区 + 侧栏组合（Phase 3.0 仅占位）。
///
/// Phase 3.0：侧栏隐藏（仅插槽），编辑区占满。
/// Phase 3.7+：侧栏接入 TOC（左侧滑出）。
/// Phase 3.8+：侧栏接入文件树（左侧滑出）。
class Workspace extends StatelessWidget {
  final EditorCoordinator coordinator;
  final ScrollController? scrollController;
  final Map<BlockId, GlobalKey> blockKeys;

  /// 文档存储基目录（ADR-0014）。
  final String? baseDir;

  const Workspace({
    super.key,
    required this.coordinator,
    this.scrollController,
    required this.blockKeys,
    this.baseDir,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 侧栏插槽（Phase 3.0 占位，默认隐藏）
        if (SidePanelHost.shouldShow(context))
          SidePanelHost(coordinator: coordinator),
        // 编辑视口（BlockRenderer 渲染所有块）
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxPageWidth),
              child: EditorViewport(
                coordinator: coordinator,
                controller: scrollController,
                blockKeys: blockKeys,
                baseDir: baseDir,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// EditorViewport：编辑视口（渲染所有 Block）。
///
/// 遍历 [coordinator.allIds]，为每个 Block 构造 [BlockRenderer]。
/// Phase 3.5.3/4/5 起使用 [ReorderableListView] 支持拖拽重排，
/// 每个 item 包裹 [BlockSelectionChrome] 提供选中态 + 悬浮工具栏 + 拖拽手柄。
class EditorViewport extends StatelessWidget {
  final EditorCoordinator coordinator;
  final ScrollController? controller;
  final Map<BlockId, GlobalKey> blockKeys;

  /// 文档存储基目录（ADR-0014）。
  final String? baseDir;

  const EditorViewport({
    super.key,
    required this.coordinator,
    this.controller,
    required this.blockKeys,
    this.baseDir,
  });

  @override
  Widget build(BuildContext context) {
    final ids = coordinator.allIds;
    // 修剪已删除块的孤儿 GlobalKey（Level 1 评审发现 3：原为只读 TOC 未触发，
    // 但编辑操作落地前须消除 —— 否则 _blockKeys 随块增删无限膨胀）。
    // 仅移除当前不再存在的 id，putIfAbsent 会在下次渲染时按需重建。
    if (blockKeys.isNotEmpty) {
      final liveIds = ids.toSet();
      blockKeys.removeWhere((id, _) => !liveIds.contains(id));
    }
    if (ids.isEmpty) {
      return const Center(
        child: Text('（空文档）', style: TextStyle(fontSize: 16)),
      );
    }
    return ReorderableListView.builder(
      scrollController: controller,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.all(EditorTokens.viewportPadding),
      itemCount: ids.length,
      onReorderItem: _onReorderItem,
      itemBuilder: (context, index) {
        final id = ids[index];
        final element = coordinator.getBlock(id);
        // state 应已在 EditorCoordinator 构造时初始化；
        // 此处 ?? 兜底防御：若 state 未初始化，使用默认 BlockViewState
        final state = coordinator.viewStateOf(id) ?? BlockViewState(id: id);
        final child = element == null
            ? const SizedBox.shrink()
            : BlockRenderer(
                element: element,
                state: state,
                coordinator: coordinator,
                baseDir: baseDir,
              );
        // 包裹选中视觉外壳 + 悬浮工具条 + 拖拽手柄（Phase 3.5.3/4/5）
        return BlockSelectionChrome(
          key: blockKeys.putIfAbsent(id, () => GlobalKey()),
          coordinator: coordinator,
          blockId: id,
          index: index,
          child: child,
        );
      },
    );
  }

  /// 拖拽重排落点 → [MoveBlockCommand]。
  ///
  /// 使用 [ReorderableListView.onReorderItem]（newIndex 已扣除被移除项），
  /// 索引 → 命令参数映射委托纯函数 [blockReorderArgs]（便于单测）。
  void _onReorderItem(int oldIndex, int newIndex) {
    final args = blockReorderArgs(coordinator.allIds, oldIndex, newIndex);
    if (args == null) return;
    coordinator.handle(
      MoveBlockCommand(
        targetId: args.targetId,
        refId: args.refId,
        before: args.before,
      ),
    );
  }
}
