/// ParagraphBlock：段落块（render + edit 双态）。
///
/// 落地 Phase 3.0 Task Contract §3.3（3 种 BlockType 之一）+ ADR-0009 §3.3。
/// 落地 Phase 3.1-A Task Contract §3.1.A.2（R4 评审反馈）：
/// - `_ParagraphBlockState` 改为 `extends BaseBlockState<ParagraphBlock>` 共享样板
/// - 消除约 40 行 controller / focus / commit 重复代码
/// 落地 Phase 3.2 Task Contract §3.0 方案 A（基类统一调度）：
/// - 移除 `build()` 重写（基类统一分发）
/// - 移除 `_buildEditing()` / `_buildRendered()`
/// - `buildRenderContent` 仅实现 render 态差异
///
/// **双态切换**（参考 Phase 2.9 Prototype Demo 1）：
/// - [RenderMode.rendered]：渲染最终样式（[ParagraphElement.children] → [Text.rich]）
/// - [RenderMode.editing]：由基类 `buildEditField` 提供 [TextField]
///
/// **用户事件流**（Hard Rule 2：Command Layer 强制）：
/// 1. 点击块 → `coordinator.setFocus(id)` 切到 editing mode
/// 2. 用户输入 → `TextEditingController` 记录
/// 3. 失焦 → `coordinator.handle(UpdateBlockSourceCommand(...))` 提交
/// 4. `coordinator.notifyListeners()` → `AnimatedBuilder` 重建
///
/// **行内渲染**（2026-08-29，P0-1 UI/UX 修复）：inline span 构建已提取到
/// [blocks/shared/inline_spans.dart]，与列表 / 任务块共用同一实现。
library;

import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../../data/models/document.dart';
import '../../editor/editor_coordinator.dart';
import '../../states/block_view_state.dart';
import '../../theme/app_typography.dart';
import '../../themes/editor_tokens.dart';
import '../base_block_state.dart';
import '../formula/formula_block.dart';
import '../shared/inline_spans.dart';

/// 段落块 Widget（Stateless，仅持有 props）。
class ParagraphBlock extends StatefulWidget {
  /// 当前块的 UI 视图状态。
  final BlockViewState state;

  /// 当前块的 AST 数据（[ParagraphElement]）。
  final ParagraphElement element;

  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 文档存储基目录（ADR-0014）。非空时本地相对图片路径用 [Image.file] 渲染。
  final String? baseDir;

  const ParagraphBlock({
    super.key,
    required this.state,
    required this.element,
    required this.coordinator,
    this.baseDir,
  });

  @override
  State<ParagraphBlock> createState() => _ParagraphBlockState();
}

/// 段落块 State：extends [BaseBlockState] 共享 controller / focus / commit 样板。
///
/// **Phase 3.1-A R4 修订**：从独立 State 改为 `extends BaseBlockState<ParagraphBlock>`,
/// 消除约 40 行 controller / focus / commit 样板。
/// **Phase 3.2 §3.0 方案 A 修订**：移除 build() / _buildEditing() / _buildRendered(),
/// 仅保留 buildRenderContent + edit 态配置。
class _ParagraphBlockState extends BaseBlockState<ParagraphBlock> {
  @override
  BlockId get blockId => widget.state.id;

  @override
  RenderMode get currentMode => widget.state.mode;

  @override
  RenderMode previousMode(ParagraphBlock oldWidget) => oldWidget.state.mode;

  /// edit 态多行（段落可能含换行）。
  @override
  int? get editFieldMaxLines => null;

  @override
  Widget buildRenderContent(BuildContext context) {
    // P0-3：纯块级公式（仅含一个 displayMode=true 的 FormulaElement）按 Typora 公式块渲染
    // （纯 serif italic、居中、无卡片；真实 SVG 渲染由 FormulaBlock 内部经 FormulaSvgService 处理）。
    if (_isPureBlockFormula(widget.element)) {
      final formula = widget.element.children.first as FormulaElement;
      return GestureDetector(
        onTap: onBlockTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.state.isFocused
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(EditorTokens.blockRadius),
          ),
          child: FormulaBlock(
            element: formula,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onBlockTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: widget.state.isFocused
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(EditorTokens.blockRadius),
        ),
        child: Text.rich(
          buildInlineSpans(
            widget.element.children,
            const TextStyle(
              fontFamily: AppTypography.serif,
              fontSize: EditorTokens.paragraphFontSize,
              height: 1.85,
            ),
            context,
            baseDir: widget.baseDir,
          ),
        ),
      ),
    );
  }

  /// 判断段落是否为「纯块级公式」：仅含一个 [FormulaElement] 且其 [displayMode] 为 true。
  ///
  /// 块级公式 `$$...$$` 在编辑器中解析为仅含此 FormulaElement 的 [ParagraphElement]，
  /// 由本 Block 委派 [FormulaBlock] 做 Typora 化独立渲染（不新增 [BlockRenderer] case）。
  bool _isPureBlockFormula(ParagraphElement element) {
    if (element.children.length != 1) return false;
    final only = element.children.first;
    return only is FormulaElement && only.displayMode;
  }
}
