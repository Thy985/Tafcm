/// HorizontalRuleBlock：水平分割线块（render + edit 双态）。
///
/// P0-1 UI/UX 修复（2026-08-29）：从 [FallbackBlockRenderer] 降级（原始 Markdown
/// 源码 `---` 显示）升级为 WYSIWYG 渲染——细分割线。
library;

import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../../data/models/document.dart';
import '../../editor/editor_coordinator.dart';
import '../../states/block_view_state.dart';
import '../../themes/editor_tokens.dart';
import '../base_block_state.dart';

/// 水平分割线块 Widget（StatefulWidget，依赖 BaseBlockState 共享样板）。
class HorizontalRuleBlock extends StatefulWidget {
  /// 当前块的 UI 视图状态。
  final BlockViewState state;

  /// 当前块的 AST 数据（[HorizontalRuleElement]）。
  final HorizontalRuleElement element;

  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  const HorizontalRuleBlock({
    super.key,
    required this.state,
    required this.element,
    required this.coordinator,
  });

  @override
  State<HorizontalRuleBlock> createState() => _HorizontalRuleBlockState();
}

/// 水平分割线块 State：extends [BaseBlockState] 共享 controller / focus / commit 样板。
class _HorizontalRuleBlockState extends BaseBlockState<HorizontalRuleBlock> {
  @override
  BlockId get blockId => widget.state.id;

  @override
  RenderMode get currentMode => widget.state.mode;

  @override
  RenderMode previousMode(HorizontalRuleBlock oldWidget) => oldWidget.state.mode;

  @override
  Widget buildRenderContent(BuildContext context) {
    return GestureDetector(
      onTap: onBlockTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Container(
          width: double.infinity,
          height: 1.5,
          color: EditorTokens.of(context).borderDefault,
        ),
      ),
    );
  }
}
