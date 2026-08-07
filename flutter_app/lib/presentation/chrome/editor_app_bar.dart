/// EditorAppBar：编辑器顶部 AppBar（chrome 组件）。
///
/// 落地 Phase 3.0 Task Contract §3.1（v1.1 新增 chrome/ 目录）+ ADR-0009 §3。
/// Phase 3.1-A PR #2：新增"切换到旧版"隐藏入口（§3.4）。
/// **Phase 3.3 PR #1**：接入 dirty tracking（§3.3.1）+ Undo/Redo 按钮（§3.3.5）。
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
import '../theme/app_theme.dart';

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

  /// 打开文件树侧栏的回调（Phase 3.4.2）。
  final VoidCallback? onOpenFileTree;

  /// 导出诊断数据 zip 的回调（Phase 3.7.3）。
  ///
  /// 接到 [EditorPage] 时由该回调驱动 [ObservabilityService.exportDiagnosticZip] 调用，
  /// 结果（zip 路径）通过 SnackBar 展示。`null` 时不显示菜单项。
  final VoidCallback? onExportDiagnostics;

  /// 当前主题模式（Phase 3.4.3 / ADR-0015：3 值 light/dark/sepia）。
  ///
  /// 仅用于渲染切换按钮的图标 / tooltip，反映**当前**主题；
  /// chrome/ 保持 Riverpod-free，主题状态由 [EditorPage] 从 provider 透传。
  final AppThemeMode themeMode;

  /// 循环切换主题的回调（Phase 3.4.3：light → dark → sepia → light）。
  final VoidCallback? onCycleTheme;

  const EditorAppBar({
    super.key,
    required this.coordinator,
    this.title = '未命名',
    this.isModified = false,
    this.focusMode = false,
    this.onToggleFocus,
    this.onOpenToc,
    this.onExportTo,
    this.onOpenFileTree,
    this.onExportDiagnostics,
    this.themeMode = AppThemeMode.light,
    this.onCycleTheme,
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
        // Phase 3.4.2：文件树侧栏开关（VS Code Mobile 风格：默认隐藏，☰ 触发）
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: '文件树',
          onPressed: onOpenFileTree,
        ),
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
        // Phase 3.4.3 / ADR-0015：3 值主题切换（明亮 → 夜间 → 护眼 → 明亮）。
        // 图标反映**当前**主题，保持切换入口可发现；主题状态由 EditorPage 透传，
        // chrome/ 不直接依赖 Riverpod（与 onToggleFocus / onOpenToc 一致的回调模式）。
        IconButton(
          icon: Icon(_themeIcon(themeMode)),
          tooltip: _themeTooltip(themeMode),
          onPressed: onCycleTheme,
        ),
        // Phase 3.3 §3.3.3：焦点模式切换（全屏进入 / 退出）
        IconButton(
          icon: Icon(focusMode ? Icons.fullscreen_exit : Icons.fullscreen),
          tooltip: focusMode ? '退出焦点模式' : '焦点模式',
          onPressed: onToggleFocus,
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
                  leading: Icon(Icons.text_snippet),
                  title: Text('导出为 TXT'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        // Phase 3.1-A PR #2：more_vert 菜单含"切换到旧版编辑器"隐藏入口。
        // 入口不直接暴露在 AppBar 主操作区，需要点开 more_vert 才能看到，
        // 满足"普通用户不会发现，方便需要回退的用户找到"的产品要求。
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多',
          onSelected: (value) => _onMenuSelected(context, value),
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'about',
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('关于'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (onExportDiagnostics != null)
              const PopupMenuItem<String>(
                value: 'export_diagnostics',
                child: ListTile(
                  leading: Icon(Icons.bug_report),
                  title: Text('导出诊断数据'),
                  subtitle: Text('调试用 zip'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem<String>(
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

  /// 当前主题模式对应的图标（反映当前状态，而非"点击后"的状态）。
  static IconData _themeIcon(AppThemeMode mode) => switch (mode) {
        AppThemeMode.light => Icons.light_mode,
        AppThemeMode.dark => Icons.dark_mode,
        AppThemeMode.sepia => Icons.brightness_medium,
      };

  /// 当前主题模式对应的 tooltip（含"点击切换到下一主题"提示）。
  static String _themeTooltip(AppThemeMode mode) => switch (mode) {
        AppThemeMode.light => '主题：明亮（点击切换到夜间）',
        AppThemeMode.dark => '主题：夜间（点击切换到护眼）',
        AppThemeMode.sepia => '主题：护眼（点击切换到明亮）',
      };

  void _onBack(BuildContext context) {
    // P1 修复（2026-08-06，phase3.5-realdevice-issues 问题 2）：
    // 原 `Navigator.maybePop()` 在栈空时静默无操作（冷启动恢复 / 外部 URI 拉起时
    // 编辑器为栈底，无上一页）→ 按钮点了没反应。改为：能 pop 则 pop，
    // 否则兜底跳 /home（与 ADR-0018 Decision 4 启动决策链一致）。
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  /// 处理 PopupMenu 选择。
  ///
  /// - `about`：显示 AboutDialog（Phase 3.1-A PR #2 占位实现）
  /// - `export_diagnostics`：触发诊断数据导出（Phase 3.7.3）
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
      case 'export_diagnostics':
        onExportDiagnostics?.call();
        break;
      case 'legacy':
        // Phase 3.1-A PR #2：跳转到 legacy fallback 路由。
        // 旧 EditorScreen 保留一个 release 周期，收集用户反馈后移除。
        // P1 修复（2026-08-06）：用 push 保留返回栈，用户可从 legacy 返回新编辑器。
        context.push('/editor-legacy');
        break;
    }
  }
}
