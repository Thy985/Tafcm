/// MarkdownToolbar：Markdown 格式工具栏（chrome 组件）。
///
/// 落地 Phase 3.3 PR #2 Task Contract v2.1：
/// - §2.1 位置 A+B 混合（底部固定栏 + 横向滚动）
/// - §2.2 状态来源：只读 CoordinatorState
/// - §2.3 Command Layer 强制（所有修改通过 EditorCommand）
/// - §2.7.1 selection 强一致读取（onPressed 中重新读取）
/// - §2.8 CodeBlock 工具栏行为（全部禁用 + 提示）
/// - §6.3 `+` 模板菜单按钮（8 模板,子组件与配置见 toolbar_components.dart）
///
/// **依赖方向**（Hard Rule 8 + TC-ARCH-3）：chrome/ 通过 [EditorCoordinator]
/// 接收数据,不 import blocks/ / panels/,也不直接 import core/services/ ——
/// 图片选择能力经 [MarkdownToolbar.pickImage] 由页面层（providers）注入。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../commands/commands.dart';
import '../editor/editor_coordinator.dart';
import 'editor_strings.dart';
import 'toolbar_components.dart';

/// 图片「选择 + 导入 assets/」函数签名（ADR-0014）。
///
/// 返回 Markdown 相对路径（`assets/img_<hash>.<ext>`）；用户取消返回 null。
/// 生产实现由 providers 层注入（AssetService.pickAndImportImage），
/// toolbar 不感知 IO 细节（TC-ARCH-3 分层守门）。
typedef ImagePickAndImport = Future<String?> Function();

/// Markdown 格式工具栏（chrome 组件）。
///
/// **状态来源**（§2.2 只读 CoordinatorState）：
/// - `coordinator.focusedId` - 当前聚焦块 ID（null = 无聚焦）
/// - `coordinator.focusedBlockType` - 聚焦块类型（CodeBlock 时禁用工具栏）
/// - `coordinator.focusedSelection` - 聚焦块选区（§2.7.1 强一致读取）
class MarkdownToolbar extends StatelessWidget {
  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 图片选择注入点（ADR-0014）。为 null 时图片菜单项回退为纯模板插入
  /// `![alt](url)`（无文件选择流程,测试环境 / 未接线页面的降级行为）。
  final ImagePickAndImport? pickImage;

  const MarkdownToolbar({
    super.key,
    required this.coordinator,
    this.pickImage,
  });

  @override
  Widget build(BuildContext context) {
    // §2.8：CodeBlock 聚焦时显示禁用提示替代工具栏按钮
    // ADR-0011 §3：Toolbar 不 import core/editing/，通过 coordinator 便捷属性查询
    final isCodeBlock = coordinator.isFocusedOnCodeBlock;
    final hasFocused = coordinator.focusedId != null;

    if (isCodeBlock) {
      return const DisabledBar(hint: EditorStrings.codeBlockToolbarDisabled);
    }

    // ADR-0012 §Editor Context Preservation：模板菜单以「最后聚焦块」为目标，
    // 即使编辑器焦点已被弹层/工具栏抢走仍可用（templateEnabled）。
    // 格式按钮（B/I/H…）仍需当前实时焦点（enabled）。
    final hasTemplateTarget = coordinator.lastFocusedId != null;

    // 无聚焦块：格式按钮整体禁用（onPressed = null,Flutter 自动应用 disabled 样式）
    return _ToolbarButtons(
      coordinator: coordinator,
      enabled: hasFocused,
      templateEnabled: hasTemplateTarget,
      pickImage: pickImage,
    );
  }
}

/// 工具栏按钮组（11 按钮 + 横向滚动布局）。
class _ToolbarButtons extends StatelessWidget {
  final EditorCoordinator coordinator;
  final bool enabled;

  /// 模板菜单是否可用（ADR-0012：基于 lastFocusedId,失焦后仍可插入到最后编辑块）。
  final bool templateEnabled;

  final ImagePickAndImport? pickImage;

  const _ToolbarButtons({
    required this.coordinator,
    required this.enabled,
    required this.templateEnabled,
    required this.pickImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: _buildButtons(context),
        ),
      ),
    );
  }

  List<Widget> _buildButtons(BuildContext context) {
    return [
      FormatButton(
        label: 'B',
        tooltip: EditorStrings.boldTooltip,
        onPressed: enabled
            ? () => _handleWrapOrInsert(
                  prefix: '**',
                  suffix: '**',
                  noSelectionText: '****',
                  noSelectionCursorOffset: -2,
                )
            : null,
      ),
      FormatButton(
        label: 'I',
        tooltip: EditorStrings.italicTooltip,
        onPressed: enabled
            ? () => _handleWrapOrInsert(
                  prefix: '*',
                  suffix: '*',
                  noSelectionText: '**',
                  noSelectionCursorOffset: -1,
                )
            : null,
      ),
      FormatButton(
        label: 'H1',
        tooltip: EditorStrings.h1Tooltip,
        onPressed: enabled ? () => _handleInsert('# ') : null,
      ),
      FormatButton(
        label: 'H2',
        tooltip: EditorStrings.h2Tooltip,
        onPressed: enabled ? () => _handleInsert('## ') : null,
      ),
      FormatButton(
        label: 'H3',
        tooltip: EditorStrings.h3Tooltip,
        onPressed: enabled ? () => _handleInsert('### ') : null,
      ),
      FormatButton(
        label: 'Code',
        tooltip: EditorStrings.codeTooltip,
        onPressed: enabled
            ? () => _handleWrapOrInsert(
                  prefix: '`',
                  suffix: '`',
                  noSelectionText: '``',
                  noSelectionCursorOffset: -1,
                )
            : null,
      ),
      FormatButton(
        label: 'Link',
        tooltip: EditorStrings.linkTooltip,
        onPressed: enabled
            ? () => _handleWrapOrInsert(
                  prefix: '[',
                  suffix: ']()',
                  noSelectionText: '[]()',
                  noSelectionCursorOffset: -3,
                )
            : null,
      ),
      FormatButton(
        label: 'Quote',
        tooltip: EditorStrings.quoteTooltip,
        onPressed: enabled ? () => _handleInsert('> ') : null,
      ),
      FormatButton(
        label: 'OL',
        tooltip: EditorStrings.orderedListTooltip,
        onPressed: enabled ? () => _handleInsert('1. ') : null,
      ),
      FormatButton(
        label: 'UL',
        tooltip: EditorStrings.unorderedListTooltip,
        onPressed: enabled ? () => _handleInsert('- ') : null,
      ),
      FormatButton(
        label: 'Task',
        tooltip: EditorStrings.taskListTooltip,
        onPressed: enabled ? () => _handleInsert('- [ ] ') : null,
      ),
      // §6.3：`+` 模板菜单按钮（PopupMenu,8 模板）
      // ADR-0012：以 templateEnabled（lastFocusedId）为准,失焦后仍可插入。
      TemplateMenuButton(
        enabled: templateEnabled,
        onSelected: templateEnabled ? _handleTemplateSelect : null,
      ),
    ];
  }

  // ============ Command 构造与分发（§2.3 + §2.7.1）============

  /// 处理「包裹选区 / 插入文本」双路径按钮（B / I / Code / Link）。
  ///
  /// **§2.7.1 强一致读取**：Command 构造瞬间通过 [coordinator.focusedSelection]
  /// 重新读取最新 selection（不依赖节流后可能滞后的视觉态）。
  void _handleWrapOrInsert({
    required String prefix,
    required String suffix,
    required String noSelectionText,
    required int noSelectionCursorOffset,
  }) {
    final blockId = coordinator.focusedId;
    if (blockId == null) return;

    // §2.7.1：强一致读取 selection
    final selection = coordinator.focusedSelection;
    final hasSelection =
        selection != null && selection.baseOffset != selection.extentOffset;

    if (hasSelection) {
      // 有选区 → WrapSelectionCommand
      coordinator.handle(WrapSelectionCommand(
        blockId: blockId,
        prefix: prefix,
        suffix: suffix,
        selection: selection,
      ));
    } else {
      // 无选区 → InsertTextCommand（光标定位到插入文本中间或末尾）
      coordinator.handle(InsertTextCommand(
        blockId: blockId,
        text: noSelectionText,
        cursorOffset: noSelectionCursorOffset,
        selection: selection,
      ));
    }
  }

  /// 处理纯插入按钮（H1 / H2 / H3 / Quote / OL / UL / Task）。
  ///
  /// 这些按钮始终走 InsertTextCommand（不依赖选区）。
  void _handleInsert(String text) {
    final blockId = coordinator.focusedId;
    if (blockId == null) return;

    // §2.7.1：强一致读取 selection（用于计算插入位置）
    final selection = coordinator.focusedSelection;

    coordinator.handle(InsertTextCommand(
      blockId: blockId,
      text: text,
      cursorOffset: 0,
      selection: selection,
    ));
  }

  /// 处理模板菜单选择（§6.3 + §2.5.1）。
  ///
  /// 从 [kTemplateConfigs] 查找配置,构造 [InsertTemplateCommand]。
  /// **§2.5.1 Hard Rule**：不解析模板字符串内容,直接使用常量。
  /// **§2.7.1**：强一致读取 selection（仅 insert 模式使用）。
  ///
  /// 图片项在 [pickImage] 已注入时走异步资源导入流程（ADR-0014，
  /// 见 [_handleInsertImage]）；未注入时回退纯模板插入 `![alt](url)`。
  void _handleTemplateSelect(TemplateMenuItem item) {
    if (item == TemplateMenuItem.image && pickImage != null) {
      // 异步：选图 → 复制到 assets/ → 插入相对路径。
      // 不 await（onSelected 为 void 回调），用 unawaited 抑制 lint。
      unawaited(_handleInsertImage(pickImage!));
      return;
    }
    // ADR-0012 §Editor Context Preservation：打开模板弹层会抢走编辑器焦点,
    // 用 coordinator.lastFocusedId（不被 clearFocus 清空）作为插入目标,
    // 而非实时的（可能已丢失的）focusedId。
    final blockId = coordinator.lastFocusedId;
    if (blockId == null) return;
    final config = kTemplateConfigs.firstWhere((c) => c.item == item);
    // §2.7.1：强一致读取 selection（insert 模式用于计算插入位置）
    final selection = coordinator.focusedSelection;
    coordinator.handle(InsertTemplateCommand(
      blockId: blockId,
      template: config.template,
      mode: config.mode,
      selection: config.mode == TemplateInsertMode.insert ? selection : null,
      cursorOffset: config.cursorOffset,
    ));
  }

  /// 图片插入（ADR-0014）：注入的 [pick] 完成「选图 → 复制到 assets/」，
  /// 本方法在当前聚焦块光标处插入 inline `![](assets/img_<hash>.<ext>)`。
  ///
  /// **为何用 [TemplateInsertMode.insert] 而非 newBlock**：
  /// newBlock 模式把模板包成单个 TextElement 再走 tryTransform，
  /// 而图片语法是 inline（无对应 BlockType），tryTransform 不会转换，
  /// 导致 Markdown 源以纯文本残留、渲染不出图片。insert 模式改走
  /// updateSource → TextOperation → toElement → parseInline，
  /// 把 `![...](...)` 正确解析为 ImageElement，渲染层即可画出本地图片。
  ///
  /// 用户取消选择时静默返回（不插入）；导入失败（权限 / 超限 / 格式）
  /// 同样静默吞掉，UI 反馈（SnackBar）留 Phase 3.5 统一错误通道。
  Future<void> _handleInsertImage(ImagePickAndImport pick) async {
    final blockId = coordinator.lastFocusedId;
    if (blockId == null) return;
    String? relative;
    try {
      relative = await pick();
    } catch (_) {
      // TODO(Phase 3.5): AssetImportException.message 经统一错误通道提示用户。
      return;
    }
    if (relative == null) return;
    coordinator.handle(InsertTemplateCommand(
      blockId: blockId,
      template: '![]($relative)',
      mode: TemplateInsertMode.insert,
      selection: coordinator.focusedSelection,
      cursorOffset: 0,
    ));
  }
}
