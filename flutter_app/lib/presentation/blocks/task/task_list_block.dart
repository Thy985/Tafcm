/// TaskListBlock：任务列表块（render + edit 双态）。
///
/// P0-1 UI/UX 修复（2026-08-29）：从 [FallbackBlockRenderer] 降级（原始 Markdown
/// 源码 `- [ ] text` 显示）升级为 WYSIWYG——checkbox 图标 + 行内富文本；点击
/// checkbox 翻转勾选（经 [UpdateBlockSourceCommand]，保持 Command Layer 强制）。
library;

import 'package:flutter/material.dart';

import '../../../core/editing/block_serializer.dart' show InlineSerializer;
import '../../../core/editing/block_types.dart';
import '../../../data/models/document.dart';
import '../../commands/commands.dart';
import '../../editor/editor_coordinator.dart';
import '../../states/block_view_state.dart';
import '../../theme/app_typography.dart';
import '../../themes/editor_tokens.dart';
import '../base_block_state.dart';
import '../shared/inline_spans.dart';

/// 任务列表块 Widget（StatefulWidget，依赖 BaseBlockState 共享样板）。
class TaskListBlock extends StatefulWidget {
  /// 当前块的 UI 视图状态。
  final BlockViewState state;

  /// 当前块的 AST 数据（[TaskListItemElement]）。
  final TaskListItemElement element;

  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 文档存储基目录（ADR-0014）。非空时本地相对图片路径用 [Image.file] 渲染。
  final String? baseDir;

  const TaskListBlock({
    super.key,
    required this.state,
    required this.element,
    required this.coordinator,
    this.baseDir,
  });

  @override
  State<TaskListBlock> createState() => _TaskListBlockState();
}

/// 任务列表块 State：extends [BaseBlockState] 共享 controller / focus / commit 样板。
class _TaskListBlockState extends BaseBlockState<TaskListBlock> {
  @override
  BlockId get blockId => widget.state.id;

  @override
  RenderMode get currentMode => widget.state.mode;

  @override
  RenderMode previousMode(TaskListBlock oldWidget) => oldWidget.state.mode;

  /// edit 态多行（任务项可能含多行文本）。
  @override
  int? get editFieldMaxLines => null;

  @override
  Widget buildRenderContent(BuildContext context) {
    final el = widget.element;
    final tokens = EditorTokens.of(context);
    return GestureDetector(
      onTap: onBlockTap,
      child: Padding(
        padding: EdgeInsets.only(left: el.indent * 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // checkbox：点击翻转勾选（不进入编辑态）
            GestureDetector(
              onTap: _toggleChecked,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Icon(
                  el.checked ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: el.checked ? tokens.brandPrimary : tokens.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text.rich(
                buildInlineSpans(
                  el.children,
                  TextStyle(
                    fontFamily: AppTypography.serif,
                    fontSize: EditorTokens.paragraphFontSize,
                    height: 1.85,
                    decoration: el.checked
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: el.checked ? tokens.textSecondary : null,
                  ),
                  context,
                  baseDir: widget.baseDir,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 翻转勾选态：`- [ ]` ↔ `- [x]`（构造新 source 经 Command 派发，走 undo 栈）。
  void _toggleChecked() {
    final el = widget.element;
    final mark = el.checked ? ' ' : 'x';
    final newSource =
        '${'  ' * el.indent}- [$mark] ${InlineSerializer.serialize(el.children)}';
    coordinator.handle(
      UpdateBlockSourceCommand(blockId: blockId, newSource: newSource),
    );
  }
}
