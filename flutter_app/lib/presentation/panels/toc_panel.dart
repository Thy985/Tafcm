/// TocPanel：目录（大纲）侧滑面板（Phase 3.4.1）。
///
/// 落地 Phase 3.4 Task Contract v1.1 §3.1 + ADR（文档运行时基础设施）。
///
/// **职责**：
/// - 从 [EditorCoordinator.allIds] 遍历，筛选 [HeadingElement] 生成大纲
/// - 标题文本**复用 [MarkdownParser.parseInline]**（inline parser）渲染，
///   不手写正则剥离 `**` —— 例：`# **Hello** world` 显示 `Hello world`
/// - 点击条目 → [EditorCoordinator.setFocus] + [onJump] 回调（由 EditorShell 负责滚动 / 关闭抽屉）
///
/// **依赖方向**（Hard Rule 8）：panels/ → editor/ + core/parser + data/models。
/// 仅 import [EditorCoordinator]（不 import editor/ 其他文件 / blocks/ / chrome/）。
library;

import 'package:flutter/material.dart';

import '../../core/editing/block_types.dart';
import '../../core/parser/markdown_parser.dart';
import '../../data/models/document.dart';
import '../editor/editor_coordinator.dart';

/// 单个 TOC 条目（不可变快照）。
class _TocItem {
  final BlockId id;
  final int level;
  final String rawText;

  const _TocItem({
    required this.id,
    required this.level,
    required this.rawText,
  });
}

/// 目录（大纲）面板：列出文档所有标题，点击跳转。
///
/// 通常由 [Scaffold.drawer] 承载（手机端 Drawer 覆盖，不占持久布局宽度，
/// 见 Phase 3.4 Task Contract §9.1）。
class TocPanel extends StatelessWidget {
  /// 当前页面绑定的 [EditorCoordinator]。
  final EditorCoordinator coordinator;

  /// 点击条目的跳转回调（由 EditorShell 实现：滚动到块 + 关闭抽屉）。
  /// [EditorCoordinator.setFocus] 已由本面板调用，此回调仅负责 UI 层滚动 / 关闭。
  final ValueChanged<BlockId>? onJump;

  const TocPanel({
    super.key,
    required this.coordinator,
    this.onJump,
  });

  /// 从 coordinator 提取标题列表（按文档顺序）。
  List<_TocItem> _collect() {
    final items = <_TocItem>[];
    for (final id in coordinator.allIds) {
      final element = coordinator.getBlock(id);
      if (element is HeadingElement) {
        items.add(_TocItem(id: id, level: element.level, rawText: element.text));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final items = _collect();
        return Drawer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DrawerHeader(
                child: Text(
                  '目录',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text('（暂无标题）', style: TextStyle(fontSize: 14)),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          // 复用 inline parser 还原标题文本（含 **bold** 等）
                          final inlines = MarkdownParser.parseInline(item.rawText);
                          return InkWell(
                            key: Key('toc_${item.id}'),
                            onTap: () {
                              coordinator.setFocus(item.id);
                              onJump?.call(item.id);
                            },
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: 16.0 + (item.level - 1) * 12.0,
                                right: 16.0,
                                top: 8.0,
                                bottom: 8.0,
                              ),
                              child: Text.rich(
                                TextSpan(
                                  style: baseStyle,
                                  children: _inlineSpans(inlines, textColor),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 把 [MarkdownParser.parseInline] 输出的 inline 元素树渲染为 [InlineSpan]。
  ///
  /// 复用现有 inline parser（不手写正则），保持与正文渲染一致的语义。
  List<InlineSpan> _inlineSpans(List<InlineElement> children, Color textColor) {
    final spans = <InlineSpan>[];
    for (final child in children) {
      spans.addAll(_renderInline(child, textColor));
    }
    return spans;
  }

  List<InlineSpan> _renderInline(InlineElement child, Color textColor) {
    if (child is TextElement) {
      return [TextSpan(text: child.text)];
    } else if (child is BoldElement) {
      return [
        TextSpan(
          children: child.children.expand((c) => _renderInline(c, textColor)).toList(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ];
    } else if (child is ItalicElement) {
      return [
        TextSpan(
          children: child.children.expand((c) => _renderInline(c, textColor)).toList(),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ];
    } else if (child is StrikethroughElement) {
      return [
        TextSpan(
          children: child.children.expand((c) => _renderInline(c, textColor)).toList(),
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ),
      ];
    } else if (child is InlineCodeElement) {
      return [
        TextSpan(
          text: child.code,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ];
    } else if (child is LinkElement) {
      return [
        TextSpan(
          text: child.text,
          style: TextStyle(
            color: ThemeData().colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      ];
    } else if (child is FormulaElement) {
      return [TextSpan(text: '\$${child.latex}\$')];
    } else if (child is ImageElement) {
      return [TextSpan(text: child.alt.isNotEmpty ? child.alt : '[图片]')];
    }
    return [];
  }
}
