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
library;

import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../../core/utils/asset_image_resolver.dart';
import '../../../data/models/document.dart';
import '../../editor/editor_coordinator.dart';
import '../../states/block_view_state.dart';
import '../../theme/app_typography.dart';
import '../../themes/editor_tokens.dart';
import '../base_block_state.dart';

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
          borderRadius: BorderRadius.circular(4),
        ),
        child: _buildInlineSpans(widget.element.children, context),
      ),
    );
  }

  /// 把 [InlineElement] 列表渲染为 [Text.rich]，支持 bold / italic / code / formula。
  ///
  /// **Phase 3.0 简化实现**：仅渲染基本 inline 类型，复杂嵌套留到 Phase 3.2+。
  Widget _buildInlineSpans(List<InlineElement> children, BuildContext context) {
    final span = _buildInlineList(
      children,
      const TextStyle(fontFamily: AppTypography.serif, fontSize: 16, height: 1.9),
      context,
    );
    return Text.rich(span);
  }

  InlineSpan _buildInlineList(
      List<InlineElement> children, TextStyle baseStyle, BuildContext context) {
    return TextSpan(
      style: baseStyle,
      children: children.map((e) => _buildInlineSpan(e, baseStyle, context)).toList(),
    );
  }

  InlineSpan _buildInlineSpan(InlineElement element, TextStyle baseStyle, BuildContext context) {
    return switch (element) {
      TextElement(:final text) => TextSpan(text: text, style: baseStyle),
      BoldElement(:final children) => TextSpan(
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
          children:
              children.map((e) => _buildInlineSpan(e, baseStyle, context)).toList(),
        ),
      ItalicElement(:final children) => TextSpan(
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          children:
              children.map((e) => _buildInlineSpan(e, baseStyle, context)).toList(),
        ),
      StrikethroughElement(:final children) => TextSpan(
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
          children:
              children.map((e) => _buildInlineSpan(e, baseStyle, context)).toList(),
        ),
      InlineCodeElement(:final code) => TextSpan(
          text: code,
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Colors.grey.shade200,
          ),
        ),
      FormulaElement(:final latex) => TextSpan(
          text: '\$$latex\$',
          style: baseStyle.copyWith(color: Colors.deepPurple),
        ),
      // Phase 3.2 §3.7：Link inline rendering（蓝色 + 下划线,不显示多余 URL）
      // 使用 EditorTokens.linkColor（TextSpan 不支持运行时 Theme 查找,需编译时常量）
      LinkElement(:final text) => TextSpan(
          text: text,
          style: baseStyle.copyWith(
            color: EditorTokens.linkColor,
            decoration: TextDecoration.underline,
          ),
        ),
      // ADR-0014：本地相对图片路径（assets/img_xxx.png）用 [Image.file] 渲染；
      // 网络地址仍占位文本（WebView 网络图留 Phase 3.5）。
      // [baseDir] 为空或文件不存在时回退占位文本（保持可读）。
      ImageElement(:final alt, :final url) =>
          _buildImageInline(url, alt, baseStyle, context),
    };
  }

  /// 渲染 [ImageElement] 为 [InlineSpan]。
  ///
  /// 本地相对路径（[baseDir] 非空且文件存在）→ [WidgetSpan] + [Image.file]；
  /// 否则回退占位文本（网络地址 / data uri / 缺基目录 / 文件缺失）。
  InlineSpan _buildImageInline(
    String url,
    String alt,
    TextStyle baseStyle,
    BuildContext context,
  ) {
    final placeholder = TextSpan(
      text: alt.isNotEmpty ? '[图片: $alt]' : '[图片]',
      style: baseStyle.copyWith(
        color: EditorTokens.of(context).textSecondary,
        fontStyle: FontStyle.italic,
      ),
    );
    // TC-ARCH-1：presentation 不直接 File()，经 core/utils 解析。
    final file = resolveLocalImageFile(widget.baseDir, url);
    if (file == null) return placeholder;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Image.file(
        file,
        height: 120,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Text(alt.isNotEmpty ? alt : '[图片]'),
      ),
    );
  }
}
