/// MarkdownToolbar 子组件与模板配置（自 markdown_toolbar.dart 拆出）。
///
/// 拆分原因：TC-ARCH-7 单文件 ≤ 400 行；本文件承载无业务逻辑的
/// 展示型子组件与模板常量配置，toolbar 本体只保留 Command 编排。
library;

import 'package:flutter/material.dart';

import '../commands/commands.dart';
import 'editor_strings.dart';
import 'templates.dart';

/// 模板菜单项标识（UI 菜单分发用,非业务字符串判断,§2.5.1 Hard Rule）。
enum TemplateMenuItem {
  table,
  mermaid,
  codeBlock,
  taskList,
  quote,
  horizontalRule,
  image,
  link,
}

/// 模板配置（label + template + mode + cursorOffset 聚合,消除冗余 switch）。
typedef TemplateConfig = ({
  TemplateMenuItem item,
  String label,
  String template,
  TemplateInsertMode mode,
  int cursorOffset,
});

/// 8 种模板的配置清单（§6.3）。
const List<TemplateConfig> kTemplateConfigs = [
  (item: TemplateMenuItem.table, label: EditorStrings.templateMenuTable, template: Templates.tableDefault, mode: TemplateInsertMode.newBlock, cursorOffset: 0),
  (item: TemplateMenuItem.mermaid, label: EditorStrings.templateMenuMermaid, template: Templates.mermaidDefault, mode: TemplateInsertMode.newBlock, cursorOffset: 0),
  (item: TemplateMenuItem.codeBlock, label: EditorStrings.templateMenuCodeBlock, template: Templates.codeBlockDefault, mode: TemplateInsertMode.insert, cursorOffset: -4),
  (item: TemplateMenuItem.taskList, label: EditorStrings.templateMenuTaskList, template: Templates.taskListDefault, mode: TemplateInsertMode.newBlock, cursorOffset: 0),
  (item: TemplateMenuItem.quote, label: EditorStrings.templateMenuQuote, template: Templates.quoteDefault, mode: TemplateInsertMode.insert, cursorOffset: 0),
  (item: TemplateMenuItem.horizontalRule, label: EditorStrings.templateMenuHorizontalRule, template: Templates.horizontalRuleDefault, mode: TemplateInsertMode.insert, cursorOffset: 0),
  (item: TemplateMenuItem.image, label: EditorStrings.templateMenuImage, template: Templates.imageDefault, mode: TemplateInsertMode.insert, cursorOffset: -4),
  (item: TemplateMenuItem.link, label: EditorStrings.templateMenuLink, template: Templates.linkDefault, mode: TemplateInsertMode.insert, cursorOffset: -4),
];

/// 单个格式按钮（紧凑 TextButton + Tooltip）。
class FormatButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  const FormatButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// CodeBlock 聚焦时的禁用栏（显示提示文字替代工具栏按钮,§2.8）。
class DisabledBar extends StatelessWidget {
  final String hint;

  const DisabledBar({super.key, required this.hint});

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
      alignment: Alignment.center,
      child: Text(
        hint,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// `+` 模板菜单按钮（PopupMenu,8 模板,§6.3）。
///
/// 使用 [TemplateMenuItem] enum 作为 PopupMenuItem value,
/// 避免字符串业务判断（§2.5.1 Hard Rule）。
class TemplateMenuButton extends StatelessWidget {
  final bool enabled;
  final ValueChanged<TemplateMenuItem>? onSelected;

  const TemplateMenuButton({
    super.key,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TemplateMenuItem>(
      icon: const Icon(Icons.add, size: 20),
      tooltip: EditorStrings.templateMenuTooltip,
      enabled: enabled,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final c in kTemplateConfigs)
          PopupMenuItem(value: c.item, child: Text(c.label)),
      ],
    );
  }
}
