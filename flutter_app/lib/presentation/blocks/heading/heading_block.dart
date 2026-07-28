/// HeadingBlock：标题块（level 1-6，render + edit 双态）。
///
/// 落地 Phase 3.0 Task Contract §3.3（3 种 BlockType 之一）+ ADR-0009 §3.3。
/// 落地 Phase 3.1-A Task Contract §3.1.A.2（R4 评审反馈）：
/// - `_HeadingBlockState` 改为 `extends BaseBlockState<HeadingBlock>` 共享样板
/// - 消除约 40 行 controller / focus / commit 重复代码
/// 落地 Phase 3.2 Task Contract §3.0 方案 A（基类统一调度）：
/// - 移除 `build()` 重写（基类统一分发）
/// - 移除 `_buildEditing()` / `_buildRendered()`
/// - `buildRenderContent` 仅实现 render 态差异
/// - `editFieldMaxLines = 1`（标题单行）
///
/// **双态切换**：
/// - [RenderMode.rendered]：显示标题文本，按 [HeadingElement.level] 1-6 渲染不同字号
/// - [RenderMode.editing]：由基类 `buildEditField` 提供 [TextField]（单行）
///
/// **字号映射**（单一真相源：[EditorTokens.headingFontSizes]，对齐 tokens.json
/// `typography.scale`：h1 26 / h2 19 / h3 18 / h4 16 / h5 14 / h6 13；字体统一 serif）：
/// - h1–h3：bold
/// - h4–h6：w600（h6 附加 italic）
///
/// **依赖方向**（Hard Rule 8）：blocks/ → editor/ → core/editing/。
library;

import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../../data/models/document.dart';
import '../../themes/editor_tokens.dart';
import '../../editor/editor_coordinator.dart';
import '../../states/block_view_state.dart';
import '../../theme/app_typography.dart';
import '../base_block_state.dart';

/// 标题块（render + edit 双态，level 1-6）。
class HeadingBlock extends StatefulWidget {
  /// 当前块的 UI 视图状态。
  final BlockViewState state;

  /// 当前块的 AST 数据（[HeadingElement]）。
  final HeadingElement element;

  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  const HeadingBlock({
    super.key,
    required this.state,
    required this.element,
    required this.coordinator,
  });

  @override
  State<HeadingBlock> createState() => _HeadingBlockState();
}

/// 标题块 State：extends [BaseBlockState] 共享 controller / focus / commit 样板。
///
/// **Phase 3.1-A R4 修订**：从独立 State 改为 `extends BaseBlockState<HeadingBlock>`,
/// 消除约 40 行 controller / focus / commit 样板。
/// **Phase 3.2 §3.0 方案 A 修订**：移除 build() / _buildEditing() / _buildRendered(),
/// 仅保留 buildRenderContent + edit 态配置。
class _HeadingBlockState extends BaseBlockState<HeadingBlock> {
  @override
  BlockId get blockId => widget.state.id;

  @override
  RenderMode get currentMode => widget.state.mode;

  @override
  RenderMode previousMode(HeadingBlock oldWidget) => oldWidget.state.mode;

  /// 标题单行编辑。
  @override
  int? get editFieldMaxLines => 1;

  @override
  Widget buildRenderContent(BuildContext context) {
    return GestureDetector(
      onTap: onBlockTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: widget.state.isFocused
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(EditorTokens.blockRadius),
        ),
        child: Text(
          widget.element.text,
          style: _styleForLevel(widget.element.level),
        ),
      ),
    );
  }

  /// 按 heading level 1-6 返回对应 [TextStyle]。
  ///
  /// 字号梯度取自 [EditorTokens.headingFontSizes]（design-system/tokens.json
  /// `typography.scale`），字体统一走 [AppTypography.serif]（ADR-0017 P0-2）。
  TextStyle _styleForLevel(int level) {
    final idx = (level - 1).clamp(0, EditorTokens.headingFontSizes.length - 1);
    final size = EditorTokens.headingFontSizes[idx];
    final weight = level <= 3 ? FontWeight.bold : FontWeight.w600;
    return TextStyle(
      fontFamily: AppTypography.serif,
      fontSize: size,
      fontWeight: weight,
      fontStyle: level == 6 ? FontStyle.italic : FontStyle.normal,
    );
  }
}
