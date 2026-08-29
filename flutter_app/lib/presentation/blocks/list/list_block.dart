/// ListBlock：列表块（render + edit 双态）。
///
/// P0-1 UI/UX 修复（2026-08-29）：从 [FallbackBlockRenderer] 降级（原始 Markdown
/// 源码 `- item` 显示）升级为 WYSIWYG 渲染——有序 / 无序标记 + 行内富文本 +
/// ADR-0029 嵌套子项递归渲染。
///
/// **双态切换**：
/// - [RenderMode.rendered]：marker（`•` / `1.`）+ 行内元素 + 嵌套子项
/// - [RenderMode.editing]：基类 TextField（Markdown 源码，与 table / code 一致）
library;

import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../../data/models/document.dart';
import '../../editor/editor_coordinator.dart';
import '../../states/block_view_state.dart';
import '../../theme/app_typography.dart';
import '../../themes/editor_tokens.dart';
import '../base_block_state.dart';
import '../shared/inline_spans.dart';

/// 列表块 Widget（StatefulWidget，依赖 BaseBlockState 共享样板）。
class ListBlock extends StatefulWidget {
  /// 当前块的 UI 视图状态。
  final BlockViewState state;

  /// 当前块的 AST 数据（[ListElement]）。
  final ListElement element;

  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 文档存储基目录（ADR-0014）。非空时本地相对图片路径用 [Image.file] 渲染。
  final String? baseDir;

  const ListBlock({
    super.key,
    required this.state,
    required this.element,
    required this.coordinator,
    this.baseDir,
  });

  @override
  State<ListBlock> createState() => _ListBlockState();
}

/// 列表块 State：extends [BaseBlockState] 共享 controller / focus / commit 样板。
class _ListBlockState extends BaseBlockState<ListBlock> {
  @override
  BlockId get blockId => widget.state.id;

  @override
  RenderMode get currentMode => widget.state.mode;

  @override
  RenderMode previousMode(ListBlock oldWidget) => oldWidget.state.mode;

  /// edit 态多行（列表项可能含多行文本）。
  @override
  int? get editFieldMaxLines => null;

  @override
  Widget buildRenderContent(BuildContext context) {
    final el = widget.element;
    // 有序列表序号：统计本块之前连续的有序列表兄弟项（AST 不保存原始序号）。
    final ordinal = el.ordered ? _topLevelOrdinal() : null;
    return GestureDetector(
      onTap: onBlockTap,
      child: Padding(
        padding: EdgeInsets.only(left: el.indent * 16.0),
        child: _buildItemRow(el, ordinal),
      ),
    );
  }

  /// 本块在「连续有序列表项」中的序号（1-based）。
  int _topLevelOrdinal() {
    final ids = coordinator.allIds;
    final idx = ids.indexOf(widget.state.id);
    var count = 1;
    for (var i = idx - 1; i >= 0; i--) {
      final prev = coordinator.getBlock(ids[i]);
      if (prev is ListElement && prev.ordered) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// 单行列表项：marker + 行内内容 + 嵌套子项（ADR-0029 递归）。
  Widget _buildItemRow(ListElement item, int? ordinal) {
    final tokens = EditorTokens.of(context);
    final marker = item.ordered ? '${ordinal ?? 1}.' : '•';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              marker,
              style: TextStyle(
                fontFamily: AppTypography.serif,
                fontSize: EditorTokens.paragraphFontSize,
                fontWeight: item.ordered ? FontWeight.w600 : FontWeight.normal,
                color: item.ordered ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                buildInlineSpans(
                  item.children,
                  const TextStyle(
                    fontFamily: AppTypography.serif,
                    fontSize: EditorTokens.paragraphFontSize,
                    height: 1.85,
                  ),
                  context,
                  baseDir: widget.baseDir,
                ),
              ),
              ..._buildNested(item.nested),
            ],
          ),
        ),
      ],
    );
  }

  /// 嵌套子项递归渲染（有序子项按兄弟位置编号）。
  List<Widget> _buildNested(List<ListElement> nested) {
    final children = <Widget>[];
    for (var i = 0; i < nested.length; i++) {
      final sub = nested[i];
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: _buildItemRow(sub, sub.ordered ? i + 1 : null),
        ),
      );
    }
    return children;
  }
}
