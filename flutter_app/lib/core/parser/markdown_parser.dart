import '../../data/models/document.dart';
import 'formula_extractor.dart';

/// Markdown 解析异常。
///
/// P1 修复（2026-08-04, B-5）：原 [MarkdownParser.parse] 对单行解析失败
/// 无任何防护——任意一行触发 RegExp 异常 / RangeError / 内部不变量失败，
/// 整个文档解析崩溃 → 调用方 [EditorPage._loadFromFile] catch 后回退种子文档，
/// 用户看到的是"打开后变成演示文档"。修复后单行错误降级为 [ParagraphElement]，
/// 解析继续，并通过 [MarkdownParseError] 回调通知调用方（presentation 层负责
/// 送入 observability）。
class MarkdownParseException implements Exception {
  final String message;
  final int? lineIndex;
  final String? lineSnippet;

  MarkdownParseException(this.message, {this.lineIndex, this.lineSnippet});

  @override
  String toString() {
    final buf = StringBuffer('MarkdownParseException: $message');
    if (lineIndex != null) buf.write(' (line $lineIndex)');
    if (lineSnippet != null) {
      // 截断长行，避免错误消息过长。
      final s = lineSnippet!;
      final snip = s.length > 80 ? '${s.substring(0, 80)}...' : s;
      buf.write(': "$snip"');
    }
    return buf.toString();
  }
}

/// 单行解析错误回调签名。
///
/// [lineIndex]：0-based 行号；[error]：异常对象；[line]：触发异常的原文行。
typedef MarkdownParseErrorHandler =
    void Function(int lineIndex, Object error, String line);

/// 行内 token 的语义类型，按 ADR-0004 优先级排列。
enum _InlineKind { image, link, code, bold, italic, strike }

/// 行内 token 命中结果，用于在多个候选中选最早 / 最高优先级的那个。
class _InlineHit {
  final _InlineKind kind;
  final int start;
  final int end;
  final int priority;
  final RegExpMatch match;

  const _InlineHit({
    required this.kind,
    required this.start,
    required this.end,
    required this.priority,
    required this.match,
  });
}

class MarkdownParser {
  /// 行内语法正则，按 ADR-0004 优先级组织：
  /// 图片 > 链接 > 行内代码 > 加粗 > 斜体 > 删除线。
  static final RegExp _imageRe = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');
  static final RegExp _linkRe = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final RegExp _codeRe = RegExp(r'`([^`]+)`');
  static final RegExp _boldRe = RegExp(r'\*\*(.+?)\*\*');
  static final RegExp _italicStarRe = RegExp(r'\*([^*\n]+?)\*');
  static final RegExp _italicUnderRe = RegExp(r'_(?=\S)([^\n_]+?)_(?=\s|$)');
  static final RegExp _strikeRe = RegExp(r'~~(.+?)~~');

  /// 解析 Markdown 文本为 [DocumentElement] 列表。
  ///
  /// P1 修复（2026-08-04, B-5）：原实现对单行解析失败无防护，任意一行触发
  /// RegExp 异常 / RangeError → 整个文档解析崩溃 → 调用方 catch 后回退种子
  /// 文档。修复后：
  /// - 单行解析失败降级为 [ParagraphElement]（保留原文），解析继续
  /// - 通过 [onError] 回调通知调用方（presentation 层送入 observability）
  /// - 不再让一行坏数据让整个文档打不开
  ///
  /// [onError]：可选错误回调。core 层不 import observability（AGENTS.md
  /// §6.1.1），由调用方注入 captureError。回调同步调用，确保错误不丢。
  static List<DocumentElement> parse(
    String content, {
    MarkdownParseErrorHandler? onError,
  }) {
    if (content.isEmpty) return [];

    final List<DocumentElement> elements = [];
    final lines = content.split('\n');

    bool inCodeBlock = false;
    String? codeLanguage;
    final List<String> codeLines = [];

    final List<ListElement> pendingListItems = [];

    void flushCodeBlock() {
      if (codeLines.isEmpty) return;
      final code = codeLines.join('\n');
      if (codeLanguage?.toLowerCase() == 'mermaid') {
        elements.add(MermaidElement(code: code));
      } else {
        elements.add(CodeElement(code: code, language: codeLanguage));
      }
      codeLines.clear();
    }

    ParagraphElement? pendingParagraph;
    void flushParagraph() {
      if (pendingParagraph != null) {
        elements.add(pendingParagraph!);
        pendingParagraph = null;
      }
    }

    void flushListItems() {
      if (pendingListItems.isEmpty) return;
      for (final item in pendingListItems) {
        elements.add(item);
      }
      pendingListItems.clear();
    }

    int getIndent(String line) {
      int indent = 0;
      for (int i = 0; i < line.length; i++) {
        if (line[i] == ' ') {
          indent++;
        } else if (line[i] == '\t') {
          indent += 4;
        } else {
          break;
        }
      }
      return indent ~/ 2;
    }

    TableElement? currentTable;
    void flushTable() {
      if (currentTable != null) {
        elements.add(currentTable!);
        currentTable = null;
      }
    }

    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];

      // P1 B-5：单行解析降级。try 块覆盖所有块级分支 + inline 解析，
      // 任意异常都降级为 ParagraphElement（保留原文），不影响后续行。
      try {
        if (line.startsWith('```')) {
          if (!inCodeBlock) {
            flushParagraph();
            flushListItems();
            flushTable();
            inCodeBlock = true;
            codeLanguage = line.length > 3 ? line.substring(3).trim() : '';
          } else {
            inCodeBlock = false;
            flushCodeBlock();
            codeLanguage = null;
          }
          continue;
        }

        if (inCodeBlock) {
          codeLines.add(line);
          continue;
        }

        if (line.trim().isEmpty) {
          flushParagraph();
          flushListItems();
          flushTable();
          elements.add(const EmptyLineElement());
          continue;
        }

        if (line.startsWith('#')) {
          flushParagraph();
          flushListItems();
          flushTable();
          int level = 0;
          int i = 0;
          while (i < line.length && line[i] == '#') {
            level++;
            i++;
          }
          elements.add(HeadingElement(
            level: level,
            text: line.substring(level).trim(),
          ));
          continue;
        }

        final trimmedLine = line.trim();

        // 任务列表：- [ ] / - [x]（ADR-0004 块级扩展，仅新增元素）
        // 用 trimmedLine 匹配：CRLF 输入下原始 line 尾部含 '\r'，
        // '.' 不匹配 '\r' 导致 taskMatch 失败 → 误解析为普通列表项
        // （Batch 3 CRLF fuzz 发现）。
        final taskMatch =
            RegExp(r'^\s*- \[( |x|X)\]\s+(.+)$').firstMatch(trimmedLine);
        if (taskMatch != null) {
          flushParagraph();
          flushListItems();
          flushTable();
          final checked = taskMatch.group(1) != ' ';
          final itemText = taskMatch.group(2)!;
          final indent = getIndent(line);
          elements.add(TaskListItemElement(
            children: _parseInline(itemText),
            checked: checked,
            indent: indent,
          ));
          continue;
        }

        if (trimmedLine.startsWith('- ') || trimmedLine.startsWith('* ') ||
            trimmedLine.startsWith('+ ') || RegExp(r'^\d+\.\s').hasMatch(trimmedLine)) {
          flushParagraph();
          flushTable();

          final indent = getIndent(line);
          final isOrdered = RegExp(r'^\d+\.\s').hasMatch(trimmedLine);
          String itemText;

          if (isOrdered) {
            itemText = trimmedLine.replaceFirst(RegExp(r'^\d+\.\s+\d+\.\s+'), '');
            if (itemText == trimmedLine) {
              itemText = trimmedLine.replaceFirst(RegExp(r'^\d+\.\s+'), '');
            }
          } else {
            itemText = trimmedLine.substring(2);
          }

          final inlineChildren = _parseInline(itemText);

          if (indent > 0 && pendingListItems.isNotEmpty) {
            final lastItem = pendingListItems.removeLast();
            final mergedText = lastItem.children
                .whereType<TextElement>()
                .map((c) => c.text)
                .join();
            final lastInlineText = mergedText.isEmpty
                ? ''
                : '$mergedText\n${'  ' * indent}${inlineChildren
                    .whereType<TextElement>()
                    .map((c) => c.text)
                    .join()}';
            final reParsed = lastInlineText.isEmpty
                ? <InlineElement>[]
                : _parseInline(lastInlineText);
            pendingListItems.add(ListElement(
              children: reParsed,
              ordered: lastItem.ordered,
              indent: indent,
            ));
          } else {
            pendingListItems.add(ListElement(
              children: inlineChildren,
              ordered: isOrdered,
              indent: indent,
            ));
          }
          continue;
        }

        if (trimmedLine.startsWith('> ')) {
          flushParagraph();
          flushListItems();
          flushTable();
          elements.add(BlockquoteElement(text: trimmedLine.substring(2).trim()));
          continue;
        }

        if (trimmedLine.startsWith('|')) {
          flushParagraph();
          flushListItems();

          if (_isTableSeparatorRow(trimmedLine)) {
            continue;
          }

          final cells = _parseTableRow(trimmedLine);
          if (cells != null && cells.isNotEmpty) {
            if (currentTable == null) {
              currentTable = TableElement(headers: cells, rows: []);
            } else {
              currentTable!.rows.add(cells);
            }
            continue;
          }
          // `|` 开头但非合法表格行（如 `|pipe| xxx` 不以 `|` 结尾）：
          // 不吞行，降级为普通段落继续解析（CAP-008 fuzz 审计发现）。
          if (currentTable != null) {
            flushTable();
          }
        } else if (currentTable != null) {
          flushTable();
        }

        // 水平分割线：--- / *** / ___（3 个及以上）
        if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
          flushParagraph();
          flushListItems();
          flushTable();
          elements.add(const HorizontalRuleElement());
          continue;
        }

        // 普通段落行：先 flush 挂起的列表，否则列表会被延迟到文档末尾
        // （顺序错误，CAP-008 fuzz 审计发现）。
        flushListItems();
        // ignore: prefer_const_constructors — children 需可变，下方 addAll 追加 inline
        pendingParagraph ??= ParagraphElement(children: <InlineElement>[]);
        if (pendingParagraph!.children.isNotEmpty) {
          // 多行段落合并时保留行间换行（Markdown hard-break 语义）。
          // 此前 addAll 直接拼接丢失 '\n'，导致 parse→serialize→parse
          // round-trip 结构不一致（CAP-008 fuzz 审计发现）。
          pendingParagraph!.children.add(const TextElement('\n'));
        }
        final inline = _parseInline(trimmedLine);
        pendingParagraph!.children.addAll(inline);
      } catch (e) {
        // P1 B-5：单行解析失败 → 降级为 ParagraphElement（保留原文），
        // flush 当前所有 pending 块状态后追加降级段落，继续解析下一行。
        onError?.call(lineIndex, e, line);
        // 退化路径前先 flush，避免 pending 状态错乱（如未闭合的 list/table）。
        flushParagraph();
        flushListItems();
        flushTable();
        elements.add(ParagraphElement(
          children: [TextElement(line)],
        ));
      }
    }

    if (inCodeBlock && codeLines.isNotEmpty) {
      elements.add(CodeElement(code: codeLines.join('\n'), language: codeLanguage));
    }
    flushParagraph();
    flushListItems();
    flushTable();

    return elements;
  }

  static bool _isTableSeparatorRow(String line) {
    final inner = line.substring(1, line.length - 1);
    final cells = inner.split('|');
    for (final cell in cells) {
      final trimmed = cell.trim();
      if (trimmed.isEmpty) continue;
      if (!RegExp(r'^[-:]+$').hasMatch(trimmed)) {
        return false;
      }
    }
    return true;
  }

  static List<String>? _parseTableRow(String line) {
    if (!line.startsWith('|') || !line.endsWith('|')) return null;
    
    final inner = line.substring(1, line.length - 1);
    if (inner.trim().isEmpty) return null;
    
    final cells = inner.split('|').map((s) => s.trim()).toList();
    if (cells.isEmpty || (cells.length == 1 && cells[0].isEmpty)) return null;
    
    return cells;
  }

  /// 公开的内联解析入口，供导出器在表格 cell 等场景下复用。
  ///
  /// 设计动机：`TableElement.headers` / `TableElement.rows` 当前是 `List<String>`，
  /// 导出器需要把 cell 字符串解析为 inline children 以渲染 cell 内的公式 / 加粗。
  /// 此方法暴露了 [parseInline] 内部使用的逻辑，但行为完全一致。
  static List<InlineElement> parseInline(String text) {
    return _parseInline(text);
  }

  static List<InlineElement> _parseInline(String text) {
    final List<InlineElement> elements = [];
    final formulas = FormulaExtractor.extractFormulas(text);

    if (formulas.isEmpty) {
      // 仅裁剪前导空白（规范化缩进内容），**保留尾部空白**。
      // 尾部空格是合法内容（如自动续列表产生的 "- " 空列表项），
      // 若用 text.trim() 会丢失续行光标位置，破坏 round-trip。
      final trimmed = text.trimLeft();
      if (trimmed.isNotEmpty) {
        elements.addAll(_parseInlineStyle(trimmed));
      }
      return elements;
    }

    int lastEnd = 0;
    for (final formula in formulas) {
      if (formula.start > lastEnd) {
        final textContent = text.substring(lastEnd, formula.start);
        if (textContent.isNotEmpty) {
          elements.addAll(_parseInlineStyle(textContent));
        }
      }
      elements.add(FormulaElement(
        latex: formula.latex,
        displayMode: formula.displayMode,
      ));
      lastEnd = formula.end;
    }

    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd);
      if (remaining.isNotEmpty) {
        elements.addAll(_parseInlineStyle(remaining));
      }
    }

    return elements;
  }

  /// 按 ADR-0004 优先级解析行内样式：
  /// 图片 > 链接 > 行内代码 > 加粗 > 斜体 > 删除线 > 纯文本。
  ///
  /// 在文本中从左到右扫描所有候选 token，取**最早起始**者；若多个 token
  /// 起始位置相同，按优先级（图片最优先，删除线最低）裁决。命中处
  /// 递归解析内层内容以支持嵌套（如加粗内嵌斜体）。
  static List<InlineElement> _parseInlineStyle(String text) {
    final List<InlineElement> out = [];
    if (text.isEmpty) return out;

    int pos = 0;
    while (pos < text.length) {
      _InlineHit? best;
      void consider(RegExp re, int priority, _InlineKind kind) {
        final m = re.firstMatch(text.substring(pos));
        if (m == null) return;
        final start = pos + m.start;
        if (best == null ||
            start < best!.start ||
            (start == best!.start && priority < best!.priority)) {
          best = _InlineHit(
            kind: kind,
            start: start,
            end: pos + m.end,
            priority: priority,
            match: m,
          );
        }
      }

      consider(_imageRe, 0, _InlineKind.image);
      consider(_linkRe, 1, _InlineKind.link);
      consider(_codeRe, 2, _InlineKind.code);
      consider(_boldRe, 3, _InlineKind.bold);
      consider(_italicStarRe, 4, _InlineKind.italic);
      consider(_italicUnderRe, 4, _InlineKind.italic);
      consider(_strikeRe, 5, _InlineKind.strike);

      if (best == null) {
        out.add(TextElement(text.substring(pos)));
        break;
      }
      if (best!.start > pos) {
        out.add(TextElement(text.substring(pos, best!.start)));
      }
      out.add(_buildInline(best!));
      pos = best!.end;
    }
    return out;
  }

  /// 把命中的行内 token 转换为 [InlineElement]，内层内容递归解析以支持嵌套。
  static InlineElement _buildInline(_InlineHit hit) {
    switch (hit.kind) {
      case _InlineKind.image:
        return ImageElement(
            alt: hit.match.group(1) ?? '', url: hit.match.group(2) ?? '');
      case _InlineKind.link:
        return LinkElement(
            text: hit.match.group(1) ?? '', url: hit.match.group(2) ?? '');
      case _InlineKind.code:
        return InlineCodeElement(hit.match.group(1) ?? '');
      case _InlineKind.bold:
        return BoldElement(children: _parseInlineStyle(hit.match.group(1) ?? ''));
      case _InlineKind.italic:
        return ItalicElement(
            children: _parseInlineStyle(hit.match.group(1) ?? ''));
      case _InlineKind.strike:
        return StrikethroughElement(
            children: _parseInlineStyle(hit.match.group(1) ?? ''));
    }
  }
}
