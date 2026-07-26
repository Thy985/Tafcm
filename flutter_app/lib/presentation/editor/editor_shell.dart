/// EditorShell：编辑器外壳（布局壳，组合 chrome + workspace + status）。
///
/// 落地 Phase 3.0 Task Contract §3.2 + ADR-0009 §3（Editor Shell Architecture）。
/// Phase 3.3 PR #2B：新增 MarkdownToolbar（§2.1 位置 A+B 混合布局）。
/// Phase 3.3 PR #4：字号缩放（§3.3.2）+ 焦点模式（§3.3.3）。
///
/// **布局**（v2.1 修订：新增 MarkdownToolbar）：
/// ```
/// ┌──────────────────────────────────────┐
/// │ AppBar（title + modified + Undo/Redo + 焦点） │ ← chrome/editor_app_bar.dart
/// ├────────────┬─────────────────────────┤
/// │            │                         │
/// │ SidePanel  │     EditorViewport      │ ← blocks/block_renderer.dart
/// │ （占位）   │  （Block 渲染列表）     │
/// ├────────────┴─────────────────────────┤
/// │ MarkdownToolbar（11 按钮 + 横向滚动） │ ← chrome/markdown_toolbar.dart
/// ├──────────────────────────────────────┤
/// │ StatusBar（块数 / 字数 / 缩放控制）   │ ← chrome/editor_status_bar.dart
/// └──────────────────────────────────────┘
/// ```
///
/// **状态（PR #4）**：
/// - `_zoomScale`：字号缩放因子（§9.1 方案 B `MediaQuery.textScaler`）。
///   纯 UI 状态，**不进 CoordinatorState**——避免污染文档 dirty 标记与持久化链（§12.3 豁免）。
///   默认 1.0，范围 `[_kMinScale, _kMaxScale]` = `[0.8, 1.25]`。
/// - `_focusMode`：焦点模式（§3.3.3，隐藏 chrome）。
///   纯 UI 状态，同上不入 CoordinatorState。
///
/// **职责**：仅布局 + 持有 UI 状态 + 传递 [EditorCoordinator]。
/// **不实现**（Phase 3.1+）：TOC / 文件树 / 主题切换 / 快捷键 / 修改状态指示持久化。
library;

import 'package:flutter/material.dart';

import '../../core/editing/block_types.dart';
import '../blocks/block_renderer.dart';
import '../chrome/editor_app_bar.dart';
import '../theme/app_theme.dart';
import '../chrome/editor_status_bar.dart';
import '../chrome/markdown_toolbar.dart';
import '../panels/side_panel_host.dart';
import '../panels/toc_panel.dart';
import '../states/block_view_state.dart';
import 'editor_coordinator.dart';

/// EditorShell：组合 chrome + workspace + status 的布局壳。
///
/// 由 [EditorPage] 挂载，接收 [EditorCoordinator] 并通过 [EditorScope] 注入。
/// Phase 3.3 PR #4 起为 [StatefulWidget]，持有缩放 / 焦点等纯 UI 状态。
class EditorShell extends StatefulWidget {
  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 当前主题模式（Phase 3.4.3：由 [EditorPage] 从 provider 透传给 AppBar 切换按钮）。
  final AppThemeMode themeMode;

  /// 循环切换主题的回调（Phase 3.4.3：light → dark → sepia → light）。
  final VoidCallback? onCycleTheme;

  const EditorShell({
    super.key,
    required this.coordinator,
    this.themeMode = AppThemeMode.light,
    this.onCycleTheme,
  });

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  static const double _kMinScale = 0.8;
  static const double _kMaxScale = 1.25;
  static const double _kZoomStep = 0.1;

  double _zoomScale = 1.0;
  bool _focusMode = false;

  /// TOC 抽屉 / 滚动定位所需的 Scaffold 句柄（Phase 3.4.1）。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 编辑区滚动控制器（Phase 3.4.1：TOC 点击跳转到块）。
  final ScrollController _scrollController = ScrollController();

  /// 每个块的稳定 GlobalKey（Phase 3.4.1：Scrollable.ensureVisible 定位）。
  final Map<BlockId, GlobalKey> _blockKeys = {};

  /// 双指缩放基线：onScaleStart 时记录当前缩放，onScaleUpdate 乘手势 scale。
  double _scaleStart = 1.0;

  void _zoomIn() =>
      setState(() => _zoomScale = (_zoomScale + _kZoomStep).clamp(_kMinScale, _kMaxScale));
  void _zoomOut() =>
      setState(() => _zoomScale = (_zoomScale - _kZoomStep).clamp(_kMinScale, _kMaxScale));
  void _zoomReset() => setState(() => _zoomScale = 1.0);
  void _toggleFocus() => setState(() => _focusMode = !_focusMode);

  /// TOC 点击条目：聚焦块 + 滚动到可视区 + 关闭抽屉（Phase 3.4.1）。
  void _jumpToBlock(BlockId id) {
    widget.coordinator.setFocus(id);
    final key = _blockKeys[id];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.1,
        duration: const Duration(milliseconds: 300),
      );
    }
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = widget.coordinator;
    return Scaffold(
      key: _scaffoldKey,
      // Phase 3.4.1：目录（大纲）抽屉
      drawer: TocPanel(
        coordinator: coordinator,
        onJump: _jumpToBlock,
      ),
      drawerEnableOpenDragGesture: false,
      // 焦点模式：隐藏 AppBar（§3.3.3）
      appBar: _focusMode
          ? null
          : EditorAppBar(
              coordinator: coordinator,
              title: coordinator.title,
              isModified: coordinator.isDirty,
              focusMode: _focusMode,
              onToggleFocus: _toggleFocus,
              onOpenToc: () => _scaffoldKey.currentState?.openDrawer(),
              themeMode: widget.themeMode,
              onCycleTheme: widget.onCycleTheme,
            ),
      body: Column(
        children: [
          Expanded(
            // 编辑区：双指缩放（onScaleUpdate）
            // 缩放仅作用于编辑区文本（MediaQuery.textScaler），chrome 保持默认字号。
            // 双击仅用于「退出」焦点模式（_focusMode 时绑定 onDoubleTap），避免 GestureDetector
            // 在非焦点模式注册 onDoubleTap 触发 gesture arena 的 ~300ms 单击延迟,
            // 影响编辑区 TextField 光标定位 / 选词。进入焦点模式走 AppBar 全屏图标。
            child: GestureDetector(
              onScaleStart: (_) => _scaleStart = _zoomScale,
              onScaleUpdate: (details) {
                if (details.scale != 1.0) {
                  setState(() {
                    _zoomScale = (_scaleStart * details.scale).clamp(_kMinScale, _kMaxScale);
                  });
                }
              },
              onDoubleTap: _focusMode ? _toggleFocus : null,
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(_zoomScale)),
                child: Workspace(
              coordinator: coordinator,
              scrollController: _scrollController,
              blockKeys: _blockKeys,
            ),
              ),
            ),
          ),
          // 焦点模式：隐藏 MarkdownToolbar（§3.3.3）
          if (!_focusMode) MarkdownToolbar(coordinator: coordinator),
        ],
      ),
      // 焦点模式：隐藏 StatusBar（§3.3.3）
      bottomNavigationBar: _focusMode
          ? null
          : EditorStatusBar(
              coordinator: coordinator,
              zoomScale: _zoomScale,
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onZoomReset: _zoomReset,
            ),
    );
  }
}

/// Workspace：编辑区 + 侧栏组合（Phase 3.0 仅占位）。
///
/// Phase 3.0：侧栏隐藏（仅插槽），编辑区占满。
/// Phase 3.7+：侧栏接入 TOC（左侧滑出）。
/// Phase 3.8+：侧栏接入文件树（左侧滑出）。
class Workspace extends StatelessWidget {
  final EditorCoordinator coordinator;
  final ScrollController? scrollController;
  final Map<BlockId, GlobalKey> blockKeys;

  const Workspace({
    super.key,
    required this.coordinator,
    this.scrollController,
    required this.blockKeys,
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
          child: EditorViewport(
            coordinator: coordinator,
            controller: scrollController,
            blockKeys: blockKeys,
          ),
        ),
      ],
    );
  }
}

/// EditorViewport：编辑视口（渲染所有 Block）。
///
/// 遍历 [coordinator.allIds]，为每个 Block 构造 [BlockRenderer]。
class EditorViewport extends StatelessWidget {
  final EditorCoordinator coordinator;
  final ScrollController? controller;
  final Map<BlockId, GlobalKey> blockKeys;

  const EditorViewport({
    super.key,
    required this.coordinator,
    this.controller,
    required this.blockKeys,
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
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(16),
      itemCount: ids.length,
      itemBuilder: (context, index) {
        final id = ids[index];
        final element = coordinator.getBlock(id);
        // state 应已在 EditorCoordinator 构造时初始化；
        // 此处 ?? 兜底防御：若 state 未初始化，使用默认 BlockViewState
        final state = coordinator.viewStateOf(id) ?? BlockViewState(id: id);
        if (element == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          key: blockKeys.putIfAbsent(id, () => GlobalKey()),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: BlockRenderer(
            element: element,
            state: state,
            coordinator: coordinator,
          ),
        );
      },
    );
  }
}
