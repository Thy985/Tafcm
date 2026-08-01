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

import '../../core/constants/layout_constants.dart';
import '../../core/editing/block_types.dart';
import '../../domain/services/export_service.dart';
import '../../providers/file_repository_provider.dart';
import '../../providers/providers.dart';
import '../chrome/editor_app_bar.dart';
import '../theme/app_theme.dart';
import '../chrome/editor_status_bar.dart';
import '../chrome/markdown_toolbar.dart';
import '../panels/file_tree_panel.dart';
import '../panels/toc_panel.dart';
import 'editor_coordinator.dart';
import 'workspace.dart';
export 'workspace.dart';

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
  /// P1-1 响应式：窄屏(紧凑)下文件树退化为 [Drawer]（endDrawer），调用
  /// [GlobalKey.currentState] 的 [ScaffoldState.openEndDrawer] 打开覆盖层，
  /// 避免 260 固定宽挤占 375 编辑区；宽屏则内联切换（[setState] 改 [_showFileTree]）。
  void _toggleFileTree() {
    if (isCompact(context)) {
      _scaffoldKey.currentState?.openEndDrawer();
    } else {
      setState(() => _showFileTree = !_showFileTree);
    }
  }

  /// 文件树侧栏内容（Phase 3.4.2）。内联（宽屏 body Row）与抽屉（窄屏 endDrawer）
  /// 共用同一份渲染，确保两种形态内容一致。
  Widget _buildFileTree() {
    return ref.watch(documentsProvider).when(
      data: (docs) => FileTreePanel(
        documents: docs,
        currentPath: widget.currentPath,
        onOpenFile: _openDoc,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
    );
  }

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
    // P1-1 响应式：宽屏(≥600)文件树内联；窄屏退化为 endDrawer（见 _toggleFileTree）。
    final isWide = !isCompact(context);
    return Scaffold(
      key: _scaffoldKey,
      // P1-1 响应式：窄屏文件树退化为右侧抽屉（endDrawer），避免 260 固定宽挤占编辑区。
      // 宽屏不挂 endDrawer（内联侧栏已在 body 的 Row 内处理）。
      endDrawer: isWide ? null : Drawer(child: _buildFileTree()),
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
                if (isWide && _showFileTree)
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
