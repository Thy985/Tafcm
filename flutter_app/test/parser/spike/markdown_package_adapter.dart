/// Migration Spike A 侧：package:markdown → Tafcm AST Adapter。
///
/// Phase 3.9 §2.1 Spike 计划：评估 package:markdown 替代「CommonMark/GFM
/// 语法识别层」的可行性。本文件实现 Adapter/Mapper —— 把官方 markdown 包
/// 的 AST（Node，统一 `Element(tag)` 结构）映射到 Tafcm 的
/// DocumentElement。
///
/// 注意：这是 **Spike 实验代码**（仅测试用），不是生产实现。生产替换与否
/// 由 A/B 7 维度数据决定（见 Migration Spike 报告）。
library;

import 'package:markdown/markdown.dart' as md;

import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/data/models/document.dart';

/// 把 markdown 包 AST 映射为 Tafcm DocumentElement 列表。
///
/// 覆盖：heading / paragraph（含 inline）/ list（含 task-list）/
/// code / table / quote / formula（`$...$` / `$$...$$`）/ mermaid /
/// horizontal rule。
///
/// 映射策略（最简版）：按 `Element.tag` 分发；未知/无法映射的节点
/// 降级为 ParagraphElement（与手写 parser 的降级语义一致）。
List<DocumentElement> adaptDocument(String source) {
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final nodes = document.parseLines(source.split('\n'));
  return nodes.expand(adaptNode).toList();
}

/// 映射单个节点（可能产生 0..n 个 Tafcm 元素）。
List<DocumentElement> adaptNode(md.Node node) {
  if (node is md.Text) {
    return [ParagraphElement(children: [TextElement(node.text)])];
  }
  if (node is! md.Element) {
    return [ParagraphElement(children: [TextElement(node.textContent)])];
  }
  final e = node;
  final tag = e.tag;
  // 标题
  if (tag.startsWith('h') && tag.length == 2) {
    final level = int.tryParse(tag.substring(1)) ?? 1;
    return [HeadingElement(level: level, text: e.textContent)];
  }
  // 段落
  if (tag == 'p') {
    return [ParagraphElement(children: adaptInlines(e.children ?? []))];
  }
  // 列表（GFM：ul / ol / li；task-list 由 li 内 checkbox 表达）
  if (tag == 'ul') {
    return _adaptListItems(e, ordered: false);
  }
  if (tag == 'ol') {
    return _adaptListItems(e, ordered: true);
  }
  // 代码块（GFM fenced：pre > code，语言在 class 或 info 中）
  if (tag == 'pre') {
    final codeNode = e.children?.whereType<md.Element>().firstWhere(
          (c) => c.tag == 'code',
          orElse: () => md.Element.text('code', ''),
        );
    final lang = _codeLanguage(codeNode);
    final code = codeNode?.textContent ?? '';
    if (lang == 'mermaid') {
      return [MermaidElement(code: code)];
    }
    return [CodeElement(code: code, language: lang)];
  }
  // 表格（GFM：table > thead/tr/th + tbody/tr/td）
  if (tag == 'table') {
    return [_adaptTable(e)];
  }
  // 引用
  if (tag == 'blockquote') {
    return [
      BlockquoteElement(
        children: MarkdownParser.parseInline(e.textContent),
      ),
    ];
  }
  // 水平分割线
  if (tag == 'hr') {
    return [HorizontalRuleElement()];
  }
  // HTML 块 → 降级为段落（保留原文）
  if (tag == 'html' || tag == 'script' || tag == 'style') {
    return [ParagraphElement(children: [TextElement(e.textContent)])];
  }
  // 兜底：未知元素降级为段落
  return [ParagraphElement(children: [TextElement(e.textContent)])];
}

/// 提取 fenced code 语言（Spike 简化：从 `code` 元素 class 或首个子文本）。
String? _codeLanguage(md.Element? codeNode) {
  if (codeNode == null) return null;
  final cls = codeNode.attributes['class'];
  if (cls != null && cls.startsWith('language-')) {
    return cls.substring('language-'.length);
  }
  return null;
}

/// ul/ol → 顶层 ListElement 列表（md 包 ListItem 无 indent 概念，
/// Spike 评估顶层语法识别；嵌套列表暂不展开 —— 作为扩展成本观察点）。
List<DocumentElement> _adaptListItems(md.Element list, {required bool ordered}) {
  final items = list.children ?? const [];
  final result = <DocumentElement>[];
  for (final item in items) {
    if (item is md.Element && item.tag == 'li') {
      // task-list：`[ ]` / `[x]` 前缀（GFM 由 li 内 input[type=checkbox] 表达）
      final checkbox = item.children
          ?.whereType<md.Element>()
          .where((c) => c.tag == 'input' && c.attributes['type'] == 'checkbox')
          .toList();
      final isTask = checkbox != null && checkbox.isNotEmpty;
      final checked = isTask && checkbox.first.attributes['checked'] != null;
      final textChildren = item.children
              ?.whereType<md.Element>()
              .where((c) => c.tag != 'input')
              .expand((c) => c.children ?? const <md.Node>[])
              .toList() ??
          const <md.Node>[];
      if (isTask) {
        result.add(TaskListItemElement(
          children: adaptInlines(textChildren),
          checked: checked,
          indent: 0,
        ));
      } else {
        result.add(ListElement(
          children: adaptInlines(textChildren),
          ordered: ordered,
          indent: 0,
        ));
      }
    }
  }
  return result;
}

/// table → TableElement（GFM：thead 首行 + tbody 行；cells 文本化）。
TableElement _adaptTable(md.Element table) {
  final rows = <md.Element>[];
  for (final child in table.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'thead') {
      rows.addAll(child.children?.whereType<md.Element>() ?? const []);
    } else if (child is md.Element && child.tag == 'tbody') {
      rows.addAll(child.children?.whereType<md.Element>() ?? const []);
    } else if (child is md.Element && child.tag == 'tr') {
      rows.add(child);
    }
  }
  final cells = <List<String>>[];
  for (final tr in rows) {
    final rowCells = <String>[];
    for (final cell in tr.children ?? const <md.Node>[]) {
      if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
        rowCells.add(cell.textContent.trim());
      }
    }
    cells.add(rowCells);
  }
  final headers = cells.isNotEmpty ? cells.first : <String>[];
  final body = cells.length > 1 ? cells.sublist(1) : <List<String>>[];
  // PR-2：cell 字符串解析为 Inline AST（与 MarkdownParser 一致）。
  return TableElement(
    headers: headers.map(MarkdownParser.parseInline).toList(),
    rows: body
        .map((row) => row.map(MarkdownParser.parseInline).toList())
        .toList(),
  );
}

/// inline 节点 → Tafcm InlineElement（按 tag 分发）。
List<InlineElement> adaptInlines(List<md.Node> nodes) {
  final result = <InlineElement>[];
  for (final n in nodes) {
    if (n is md.Text) {
      result.add(TextElement(n.text));
    } else if (n is md.Element) {
      result.addAll(adaptInlineElement(n));
    } else {
      result.add(TextElement(n.textContent));
    }
  }
  return result;
}

List<InlineElement> adaptInlineElement(md.Element e) {
  switch (e.tag) {
    case 'em':
      return [ItalicElement(children: adaptInlines(e.children ?? []))];
    case 'strong':
      return [BoldElement(children: adaptInlines(e.children ?? []))];
    case 'del':
      return [StrikethroughElement(children: adaptInlines(e.children ?? []))];
    case 'code':
      return [InlineCodeElement(e.textContent)];
    case 'a':
      return [LinkElement(url: e.attributes['href'] ?? '', text: e.textContent)];
    case 'img':
      return [
        ImageElement(alt: e.attributes['alt'] ?? '', url: e.attributes['src'] ?? ''),
      ];
    case 'br':
      return [TextElement('\n')];
    default:
      // 未知 inline（含 md 包不认识的 `$...$` —— 按 Text 处理，
      // 公式识别为「扩展成本」观察点：需自定义 InlineSyntax）
      return [TextElement(e.textContent)];
  }
}
