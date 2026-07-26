/// EditorAppBar：编辑器顶部 AppBar（chrome 组件）。
///
/// 落地 Phase 3.0 Task Contract §3.1（v1.1 新增 chrome/ 目录）+ ADR-0009 §3。
/// Phase 3.1-A PR #2：新增"切换到旧版"隐藏入口（§3.4）。
/// **Phase 3.3 PR #1**：接入 dirty tracking（§3.3.1）+ Undo/Redo 按钮（§3.3.5）。
/// **Phase 3.4 Slice 7**：新增导出 PopupMenu（§3.7，3.4.4 导出进度反馈），
///   选中目标格式后回调 `onExportTo(format)`，具体导出动作与进度展示由
///   EditorPage / ExportProgressOverlay 接管（chrome/ 保持 Riverpod-free，
///   AGENTS.md §6.1 + §6.5 守门）。
///
/// **职责**：
/// - 显示当前文档标题（Phase 3.3：从 coordinator.title 透传）
/// - 显示修改状态指示器（Phase 3.3：从 coordinator.isDirty 透传）
/// - 提供返回按钮（返回到文件管理页）
/// - **Phase 3.3**：提供 Undo / Redo IconButton（基于 coordinator.canUndo / canRedo）
/// - **Phase 3.1-A PR #2**：more_vert 菜单含"切换到旧版编辑器"入口（跳 `/editor-legacy`）
/// - **Phase 3.4 Slice 7**：导出 PopupMenu 触发 [EditorCoordinator] 内容导出
///
/// **不实现**（Phase 3.4+）：
/// - 自动保存指示
/// - 字号缩放控件
///
/// **依赖方向**（Hard Rule 8）：chrome/ 通过 [EditorCoordinator] 接收数据，
/// 不 import blocks/ / panels/。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/services/export_service.dart';
import '../editor/editor_coordinator.dart';

/// 编辑器顶部 AppBar（chrome 组件）。
class EditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// AppBar 标题（Phase 3.3：从 coordinator.title 透传）。
  final String title;

  /// 是否有未保存修改（Phase 3.3：从 coordinator.isDirty 透传）。
  final bool isModified;

  /// 是否处于焦点模式（Phase 3.3 §3.3.3：隐藏 chrome）。
  final bool focusMode;

  /// 切换焦点模式的回调（Phase 3.3 §3.3.3）。
  final VoidCallback? onToggleFocus;

  /// 打开目录（大纲）抽屉的回调（Phase 3.4.1）。
  final VoidCallback? onOpenToc;

  /// 触发导出动作的回调（Phase 3.4 Slice 7 / 3.4.4）。
  ///
  /// 接到 [EditorPage] 时由该回调驱动 MarkdownExporter.exportToXxx 调用，
  /// 并把进度通过 `exportProgressProvider` 暴露给 ExportProgressOverlay。
  /// `null` 时不显示导出按钮。
  final ValueChanged<ExportFormat>? onExportTo;

  const EditorAppBar({
    super.key,
    required this.coordinator,
    this.title = '未命名',
    this.isModified = false,
    this.focusMode = false,
    this.onToggleFocus,
    this.onOpenToc,
    this.onExportTo,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (isModified) ...[
            const SizedBox(width: 4),
            const Text(
              '•',
              style: TextStyle(fontSize: 20),
            ),
          ],
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回',
        onPressed: () => _onBack(context),
      ),
      actions: [
        // Phase 3.4.1：目录（大纲）抽屉开关
        IconButton(
          icon: const Icon(Icons.list_alt),
          tooltip: '目录',
          onPressed: onOpenToc,
        ),
        // Phase 3.3 §3.3.5：Undo 按钮（基于 coordinator.canUndo 启用/禁用）
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: '撤销',
          onPressed: coordinator.canUndo ? () => coordinator.undo() : null,
        ),
        // Phase 3.3 §3.3.5：Redo 按钮（基于 coordinator.canRedo 启用/禁用）
        IconButton(
          icon: const Icon(Icons.redo),
          tooltip: '重做',
          onPressed: coordinator.canRedo ? () => coordinator.redo() : null,
        ),
        // Phase 3.4 Slice 7 / §3.7：导出 PopupMenu（PDF / Word / TXT）。
        // 仅在 EditorPage 注入了 onExportTo 时显示。
        if (onExportTo != null)
          PopupMenuButton<ExportFormat>(
            icon: const Icon(Icons.ios_share),
            tooltip: '导出',
            onSelected: onExportTo!,
            itemBuilder: (context) => const [
              PopupMenuItem<ExportFormat>(
                value: ExportFormat.pdf,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf),
                  title: Text('导出为 PDF'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<ExportFormat>(
                value: ExportFormat.docx,
                child: ListTile(
                  leading: Icon(Icons.description),
                  title: Text('导出为 Word（.docx）'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<ExportFormat>(
                value: ExportFormat.txt,
                child: ListTile(
                  leading: Icon(Icons.text_snippet_outlined),
                  title: Text('导出为 TXT'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        // Phase 3.3 §3.3.3：焦点模式切换（全屏进入 / 退出）
        IconButton(
          icon: Icon(focusMode ? Icons.fullscreen_exit : Icons.fullscreen),
          tooltip: focusMode ? '退出焦点模式' : '焦点模式',
          onPressed: onToggleFocus,
        ),
        // Phase 3.1-A PR #2：more_vert 菜单含"切换到旧版编辑器"隐藏入口。
        // 入口不直接暴露在 AppBar 主操作区，需要点开 more_vert 才能看到，
        // 满足"普通用户不会发现，方便需要回退的用户找到"的产品要求。
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多',
          onSelected: (value) => _onMenuSelected(context, value),
          itemBuilder: (context) => const [
            PopupMenuItem<String>(
              value: 'about',
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('关于'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem<String>(
              value: 'legacy',
              child: ListTile(
                leading: Icon(Icons.history),
                title: Text('切换到旧版编辑器'),
                subtitle: Text('fallback · 迁移期保留'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onBack(BuildContext context) {
    // Phase 3.0：返回到文件管理页（路由由 main.dart 配置）
    Navigator.of(context).maybePop();
  }

  /// 处理 PopupMenu 选择。
  ///
  /// - `about`：显示 AboutDialog（Phase 3.1-A PR #2 占位实现）
  /// - `legacy`：跳转到 `/editor-legacy`（旧 EditorScreen fallback）
  void _onMenuSelected(BuildContext context, String value) {
    switch (value) {
      case 'about':
        showAboutDialog(
          context: context,
          applicationName: 'FormulaFix',
          applicationVersion: 'Phase 3.3',
          applicationLegalese: 'WYSIWYG 编辑器 · Phase 3.0+',
        );
        break;
      case 'legacy':
        // Phase 3.1-A PR #2：跳转到 legacy fallback 路由。
        // 旧 EditorScreen 保留一个 release 周期，收集用户反馈后移除。
        context.go('/editor-legacy');
        break;
    }
  }
}
