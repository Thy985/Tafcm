/// FallbackBlockRenderer：未实现专用 Renderer 的 BlockElement 降级渲染器。
///
/// 落地 [ADR-0022 Renderer Failure Policy]。
///
/// **核心契约**（ADR-0022 §2.1）：
/// - Renderer MUST NOT crash on unknown BlockElement
/// - 未实现的 [DocumentElement] 子类型经此 widget 降级渲染
/// - 降级策略：反向序列化为 markdown source → 委托给 [ParagraphBlock]
///
/// **用户可见效果**（ADR-0022 §2.2）：
/// - `TaskListItemElement` → 显示 `- [ ] task` / `- [x] task`（可编辑）
/// - `ListElement` → 显示 `- item` / `1. item`（可编辑）
/// - `HorizontalRuleElement` → 显示 `---`（可编辑）
///
/// **observability 协同**（ADR-0022 §2.4）：
/// - 每个元素类型在每个 App 生命周期内只报告一次（静态去重 Set）
/// - 报告类型：`UnsupportedBlockFallback`
/// - 用于数据驱动 Phase 3.5+ Renderer 实现优先级
///
/// **Phase 3.5+ 替换**：
/// 实现专用 Renderer 后，删除 [BlockRenderer] 中对应 case 的 `FallbackBlockRenderer`
/// 分支，改用专用 widget。本文件可保留作为后续未实现类型的统一 fallback。
library;

import 'package:flutter/widgets.dart';

import '../../core/editing/block_serializer.dart' show fromElement;
import '../../core/observability/observability_service.dart';
import '../../data/models/document.dart';
import '../editor/editor_coordinator.dart';
import '../states/block_view_state.dart';
import 'paragraph/paragraph_block.dart';

/// 未实现专用 Renderer 的 BlockElement 降级渲染器。
///
/// 见 [library doc] 与 ADR-0022。
class FallbackBlockRenderer extends StatefulWidget {
  /// 当前块的 UI 视图状态（透传给 [ParagraphBlock]）。
  final BlockViewState state;

  /// 当前块的 AST 数据（未实现专用 Renderer 的类型）。
  final DocumentElement element;

  /// 当前页面绑定的 [EditorCoordinator]（透传给 [ParagraphBlock]）。
  final EditorCoordinator coordinator;

  /// 文档存储基目录（ADR-0014）。非空时本地图片用 [Image.file] 渲染。
  final String? baseDir;

  const FallbackBlockRenderer({
    super.key,
    required this.state,
    required this.element,
    required this.coordinator,
    this.baseDir,
  });

  @override
  State<FallbackBlockRenderer> createState() => _FallbackBlockRendererState();
}

class _FallbackBlockRendererState extends State<FallbackBlockRenderer> {
  /// 已报告过的元素类型（App 生命周期内去重）。
  ///
  /// ADR-0022 §2.4：每个未实现类型只向 observability 报告一次，
  /// 避免频繁触发污染 [ObservabilityService.lastErrorSnapshot]。
  /// 重启 App 后重置（合理：用户可能再次触发，需重新统计）。
  ///
  /// 注：此处属 observability 通知去重，非业务状态（AGENTS.md §6.1.7 例外）。
  static final Set<String> _reportedTypes = <String>{};

  @override
  void initState() {
    super.initState();
    _reportFallback();
  }

  /// 向 observability 报告降级事件（去重）。
  ///
  /// ADR-0022 §2.4：用 element.runtimeType 作为去重 key。
  /// 同一类型在 App 生命周期内只报告一次。
  void _reportFallback() {
    final typeName = widget.element.runtimeType.toString();
    if (_reportedTypes.contains(typeName)) return;
    _reportedTypes.add(typeName);

    final obs = widget.coordinator.observability;
    if (obs == null) return;
    obs.captureError(
      type: 'UnsupportedBlockFallback',
      message: 'BlockType $typeName rendered via FallbackBlockRenderer '
          '(no dedicated renderer implemented yet, see ADR-0022)',
      commandParams: {
        'element_type': typeName,
        'block_id': widget.state.id.toString(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. 反向序列化为 markdown source（不丢数据）
    final source = fromElement(widget.element);

    // 2. 构造 ParagraphElement(children: [TextElement(source)])
    //    用户看到 raw markdown source（可读、可编辑）
    final paragraphElement = ParagraphElement(
      children: [TextElement(source)],
    );

    // 3. 委托给 ParagraphBlock（复用其 render + edit 双态逻辑）
    return ParagraphBlock(
      state: widget.state,
      element: paragraphElement,
      coordinator: widget.coordinator,
      baseDir: widget.baseDir,
    );
  }
}
