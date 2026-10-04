/// 公式 AST 提取 helper（测试专用）。
///
/// 供 parser 侧公式解析测试共用：收集文档全部 [FormulaElement]，以及取
/// 「纯块级公式段落」（`ParagraphBlock._isPureBlockFormula` 的渲染契约）。
///
/// 本文件仅用于 test/，不放入 lib/。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/data/models/document.dart';

/// 收集文档中全部 inline 公式（含嵌套块）。
List<FormulaElement> allFormulas(List<DocumentElement> elements) {
  final out = <FormulaElement>[];
  void walkInline(List<InlineElement> children) {
    for (final child in children) {
      switch (child) {
        case FormulaElement():
          out.add(child);
        case BoldElement(:final children):
        case ItalicElement(:final children):
        case StrikethroughElement(:final children):
          walkInline(children);
        case TextElement():
        case InlineCodeElement():
        case LinkElement():
        case ImageElement():
          break;
      }
    }
  }

  void walk(List<DocumentElement> nodes) {
    for (final node in nodes) {
      switch (node) {
        case ParagraphElement(:final children):
        case ListElement(:final children):
        case TaskListItemElement(:final children):
        case BlockquoteElement(:final children):
          walkInline(children);
        case TableElement(:final headers, :final rows):
          for (final header in headers) {
            walkInline(header);
          }
          for (final row in rows) {
            for (final cell in row) {
              walkInline(cell);
            }
          }
        case HeadingElement(:final children):
          walkInline(children);
        case CodeElement():
        case MermaidElement():
        case HorizontalRuleElement():
        case EmptyLineElement():
          break;
      }
    }
  }

  walk(elements);
  return out;
}

/// 取仅含单个 [FormulaElement] 的段落，并断言**恰好存在一个**这样的段落。
///
/// 对应 `ParagraphBlock._isPureBlockFormula` 的**形状**判定（子元素恰一个
/// 且为公式元素）。本 helper **不校验** [FormulaElement.displayMode]——
/// 需要该断言的用例请自行补 `expect(formula.displayMode, isTrue)`。
ParagraphElement pureFormulaParagraph(List<DocumentElement> elements) {
  final candidates = elements
      .whereType<ParagraphElement>()
      .where((p) => p.children.length == 1 && p.children.first is FormulaElement)
      .toList();
  expect(candidates, hasLength(1),
      reason: '期望恰好一个「纯块级公式」段落，实际 AST：$elements');
  return candidates.single;
}
