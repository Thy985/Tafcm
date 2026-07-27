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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/editing/block_types.dart';
import '../../domain/services/export_service.dart';
import '../../providers/file_repository_provider.dart';
import '../../providers/providers.dart';
import '../blocks/block_renderer.dart';
import '../chrome/editor_app_bar.dart';
import '../theme/app_theme.dart';
import '../chrome/editor_status_bar.dart';
import '../chrome/markdown_toolbar.dart';
import '../panels/file_tree_panel.dart';
import '../panels/side_panel_host.dart';
import '../panels/toc_panel.dart';
import '../states/block_view_state.dart';
import 'editor_coordinator.dart';

/// 页面最大内容宽度（Phase 3.4 Slice 5 / 3.4.8 页面宽度控制）。
///
/// 编辑视口在宽屏（> 720）下约束于此值并居中；窄屏（< 720）不受影响。
/// 纯布局常量，无状态、不持久化（如需可调宽度，后续接入设置面板）。
const double kMaxPageWidth = 720.0;

/// EditorShell：组合 chrome + workspace + status 的布局壳。
///
/// 由 [EditorPage] 挂载，接收 [EditorCoordinator] 并通过 [EditorScope] 注入。
/// Phase 3.3 PR #4 起为 [ConsumerStatefulWidget]，持有缩放 / 焦点 / 文件树等纯 UI 状态。
class EditorShell extends ConsumerStatefulWidget {
  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 当前打开文档的路径（用于文件树高亮）；为 null 表示未打开具体文件。
  final String? currentPath;

  /// 点击文件树某文档的回调（参数为该文档路径），由 EditorPage 负责打开 / 持久化。
  final ValueChanged<String>? onOpenFile;

  /// 当前主题模式（Phase 3.4.3：由 [EditorPage] 从 provider 透传给 AppBar 切换按钮）。
  final AppThemeMode themeMode;

  /// 循环切换主题的回调（Phase 3.4.3：light → dark → sepia → light）。
  final VoidCallback? onCycleTheme;

  /// 文档存储基目录（ADR-0014）。非空时本地图片用 [Image.file] 渲染。
  final String? baseDir;

  /// 图片「选择 + 导入」注入点（ADR-0014，由 [EditorPage] 从 provider 解析后透传）。
  final ImagePickAndImport? pickImage;

  /// 触发导出动作的回调（Phase 3.4 Slice 7 / 3.4.4）。
  ///
  /// 接到 AppBar 导出 PopupMenu；`null` 时 AppBar 不渲染导出按钮。
  final ValueChanged<ExportFormat>? onExportTo;

  const EditorShell({
    super.key,
    required this.coordinator,
    this.currentPath,
    this.onOpenFile,
    this.themeMode = AppThemeMode.light,
    this.onCycleTheme,
    this.baseDir,
    this.pickImage,
    this.onExportTo,
  });

  @override
  ConsumerState<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends ConsumerState<EditorShell> {
  static const double _kMinScale = 0.8;
  static const double _kMaxScale = 1.25;
  static const double _kZoomStep = 0.1;

  double _zoomScale = 1.0;
  bool _focusMode = false;

  /// 文件树侧栏是否展开（Phase 3.4.2，VS Code Mobile 风格：默认隐藏）。
  bool _showFileTree = false;

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

  /// 切换文件树侧栏（Phase 3.4.2）。
  void _toggleFileTree() => setState(() => _showFileTree = !_showFileTree);

  /// 文件树点击：由文档 id 解析路径，转交 [widget.onOpenFile]（EditorPage 负责打开 + 持久化）。
  ///
  /// [documentPathFor] 当前实现（[FileRepository]）不抛异常，但 [DocumentRepository]
  /// 接口未约束"不抛异常"，未来实现（远程仓储等）可能抛。此处兜底，避免点击文件树时
  /// 因未捕获异常导致整树崩溃。失败时提示用户，不改写 [widget.onOpenFile]。
  Future<void> _openDoc(String id) async {
    try {
      final path = await ref.read(fileRepositoryProvider).documentPathFor(id);
      widget.onOpenFile?.call(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开文件失败：$e')),
      );
    }
  }

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
          :             EditorAppBar(
              coordinator: coordinator,
              title: coordinator.title,
              isModified: coordinator.isDirty,
              focusMode: _focusMode,
              onToggleFocus: _toggleFocus,
              onOpenToc: () => _scaffoldKey.currentState?.openDrawer(),
              onOpenFileTree: _toggleFileTree,
              themeMode: widget.themeMode,
              onCycleTheme: widget.onCycleTheme,
              onExportTo: widget.onExportTo,
            ),
      body: Column(
        children: [
          Expanded(
            // 编辑区 + 文件树侧栏（Phase 3.4.2）：默认仅编辑区占满；
            // 点 AppBar「文件树」按钮后，左侧嵌入 FileTreePanel（VS Code Mobile 风格）。
            child: Row(
              children: [
                if (_showFileTree)
                  SizedBox(
                    width: 260,
                    child: ref.watch(documentsProvider).when(
                      data: (docs) => FileTreePanel(
                        documents: docs,
                        currentPath: widget.currentPath,
                        onOpenFile: _openDoc,
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) =>
                          const Center(child: Text('加载失败')),
                    ),
                  ),
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
                          _zoomScale =
                              (_scaleStart * details.scale).clamp(_kMinScale, _kMaxScale);
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
                        baseDir: widget.baseDir,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 焦点模式：隐藏 MarkdownToolbar（§3.3.3）
          if (!_focusMode)
            MarkdownToolbar(
              coordinator: coordinator,
              pickImage: widget.pickImage,
            ),
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
            baseDir: baseDir,
          ),
        );
      },
    );
  }
}
