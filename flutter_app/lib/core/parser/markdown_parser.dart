import '../../data/models/document.dart';
import 'block_formula_scanner.dart';
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
///
/// issue #332：新增 boldItalic（`***text***`）——此前被 [bold] 正则的非贪婪
/// 匹配误拆成 `**` + `*text` 内层，导致用户看到 `*text`（多余 `*`）。
/// 粗斜体优先级（2）高于加粗（4），使其在 `***x***` 上优先于 bold 命中。
enum _InlineKind { image, link, code, bold, boldItalic, italic, strike }

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
  ///
  /// issue #332：粗斜体（`***text***`）与加粗同为 `*` 起始，需单独正则
  /// 且优先级高于加粗——否则加粗的非贪婪匹配会吞掉前两个 `*`，把
  /// `***x***` 误拆为 `**` + 内层 `*x` + 残留 `*`。
  static final RegExp _imageRe = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');
  static final RegExp _linkRe = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final RegExp _codeRe = RegExp(r'`([^`]+)`');
  static final RegExp _boldItalicRe = RegExp(r'\*\*\*(.+?)\*\*\*');
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
  /// issue #332（QA 2026-10-04 边界语法巡检，本批 3 项）：
  /// - Setext 标题（`==` / `--` 下划线行）：紧随段落的分隔行回填标题级别
  /// - 四空格缩进代码块：缩进 ≥4 列（tab 计 4 列）的连续行收为 [CodeElement]
  ///   （language: null），不再被当普通段落衬线体渲染
  /// - 粗斜体 `***text***`：新增 [_InlineKind.boldItalic]，不再残留多余 `*`
  ///
  /// 本批**未含**（另立 follow-up，各自需模型层或产品决策）：嵌套引用 `> >`
  /// （需 BlockquoteElement 增加 nested 字段，镜像 ListElement.nested）、
  /// 脚注 `[^1]`（是否纳入支持范围待产品确认，见 #332 备注）、HTML 块与行内
  /// HTML（渲染方式待产品决策，当前以转义文本兜底，不崩溃）、转义序列 `\_`
  /// （fuzz 语料含 `\` 但无 `\_` 组合，改动易破坏现有 backslash 用例）。
  ///
  /// [onError]：可选错误回调。core 层不 import observability（AGENTS.md
  /// §6.1.1），由调用方注入 captureError。回调同步调用，确保错误不丢。
  static List<DocumentElement> parse(
    String content, {
    MarkdownParseErrorHandler? onError,
  }) {
    if (content.isEmpty) return [];

    final List<DocumentElement> elements = [];

    // issue #336-1：CRLF 行尾统一归一。`split('\n')` 后行尾残留 `'\r'`，此前
    // 只在段落路径被 `trimmedLine` 隐式剥离，代码块分支 `codeLines.add(line)`
    // 用的是原始 line → 代码内容尾部带 `\r`（影响代码高亮 token 与导出文本
    // 保真）。统一在解析入口去掉每行尾部 `'\r'`，让 CRLF 与 LF 文档产出完全
    // 一致的 AST。仅去尾部一个，正文内部的 `\r`（罕见）原样保留。
    final lines = content
        .split('\n')
        .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l)
        .toList();

    bool inCodeBlock = false;
    String? codeLanguage;
    final List<String> codeLines = [];

    // issue #332：四空格缩进代码块（CommonMark 与围栏 ``` 并列的代码块入口）。
    // 缩进 ≥4 列（或 ≥1 个 Tab，按 4 列计）的连续行收为一个 CodeElement
    // （language: null），不再被当普通段落衬线体渲染。
    bool inIndentedCode = false;
    final List<String> indentedCodeLines = [];

    final List<ListElement> pendingListItems = [];

    void flushCodeBlock() {
      // 空代码块（```mermaid\n```）也要产出元素 —— round-trip 保真
      // （Batch 5 Mermaid 审计发现：原 isEmpty 守卫导致空块整体丢失）。
      final code = codeLines.join('\n');
      if (codeLanguage?.toLowerCase() == 'mermaid') {
        elements.add(MermaidElement(code: code));
      } else {
        elements.add(CodeElement(code: code, language: codeLanguage));
      }
      codeLines.clear();
    }

    void flushIndentedCode() {
      // 与围栏代码块同理：空内容（纯空白行）不产出元素。
      if (indentedCodeLines.isEmpty) return;
      // 内容统一剥掉首个缩进单位（tab 或至多 4 个空格），保留块内相对缩进。
      final stripped = <String>[];
      for (final l in indentedCodeLines) {
        stripped.add(l.startsWith('\t')
            ? l.substring(1)
            : l.replaceFirst(RegExp(r'^ {1,4}'), ''));
      }
      elements.add(CodeElement(code: stripped.join('\n'), language: null));
      indentedCodeLines.clear();
      // 复位：允许空行后的下一个缩进块重新进入入口判定——不复位则第二个块
      // 因 !inIndentedCode 为假而被拒，退化成带缩进前缀的段落文本。
      inIndentedCode = false;
    }

    ParagraphElement? pendingParagraph;
    void flushParagraph() {
      if (pendingParagraph != null) {
        elements.add(pendingParagraph!);
        pendingParagraph = null;
      }
    }

    /// ADR-0029：平铺列表项按 indent 递归构建嵌套树。
    /// 每项收集「indent > 自身」的连续后续项作为 nested（递归）。
    List<ListElement> buildNestedTree(List<ListElement> flat) {
      final result = <ListElement>[];
      var i = 0;
      while (i < flat.length) {
        final item = flat[i];
        var j = i + 1;
        while (j < flat.length && flat[j].indent > item.indent) {
          j++;
        }
        final children = j > i + 1
            ? buildNestedTree(flat.sublist(i + 1, j))
            : const <ListElement>[];
        result.add(ListElement(
          children: item.children,
          ordered: item.ordered,
          indent: item.indent,
          nested: children,
        ));
        i = j;
      }
      return result;
    }

    void flushListItems() {
      if (pendingListItems.isEmpty) return;
      // ADR-0029：平铺项按 indent 递归构建嵌套树（不再拍平合并子项）。
      elements.addAll(buildNestedTree(pendingListItems));
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

        // issue #332：四空格缩进代码块的**接续 / 收尾**（早判定）。
        // 缩进 ≥4 列（tab 计 4 列）视为代码块续行；一旦代码块打开，续行必须
        // 无条件并入（不再走列表/引用/表格分支，避免块内内容被误解析）；
        // 非缩进行则收尾并放行到后续分支。
        //
        // 此处只处理「已打开的块」，故不会劫持缩进列表项——缩进列表项的**入口**
        // 在下方段落 fall-through 处的晚判定（列表分支若先命中则代码块不启动）。
        final indentedHere =
            RegExp(r'^(?: {4,}|\t)').hasMatch(line) && line.trim().isNotEmpty;
        if (inIndentedCode) {
          if (indentedHere) {
            indentedCodeLines.add(line);
            continue;
          }
          flushIndentedCode();
        }

        if (line.trim().isEmpty) {
          flushParagraph();
          flushListItems();
          flushTable();
          elements.add(const EmptyLineElement());
          continue;
        }

        // 块级公式（issue #321）：`$$` 定界行独占的标准多行写法
        // （`$$\n...\n$$`）在块级先收集成一块，再交给 _parseInline 统一解析，
        // 产出**单个** displayMode FormulaElement（此前被逐行拆成字面文本，
        // `$$` 定界行还退化成空公式）。
        // - 单行 `$$...$$`（endIndex == lineIndex）不进入本分支，走既有路径
        // - 未闭合 `$$`（scan 返回 null）降级为既有逐行行为，不抛异常
        //
        // **空 latex 对称**：`$$\n$$`（块级空围栏）与单行 `$$$$` 都被解析为
        // latex 为空的 display 公式（经 `_stripFenceNewlines` 归一），二者不区分
        // 来源写法。这是刻意选择——空块按公式卡片渲染，避免同一内容在不同写法
        // 下走不同渲染路径（文本 ↔ 卡片）导致 round-trip 翻转。
        final displayBlock = BlockFormulaScanner.scan(lines, lineIndex);
        if (displayBlock != null && displayBlock.endIndex > lineIndex) {
          flushParagraph();
          flushListItems();
          flushTable();
          elements.add(ParagraphElement(
            children: _parseInline(displayBlock.source),
          ));
          lineIndex = displayBlock.endIndex;
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
            // PR-3：标题内容走 _parseInline（解析只发生一次）。
            children: _parseInline(line.substring(level).trim()),
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

          // ADR-0029：平铺收集（保留 indent），flush 时按缩进构建嵌套树；
          // 不再把缩进子项拍平合并进父项文本（BUG-5 round-trip 不保真根因）。
          pendingListItems.add(ListElement(
            children: inlineChildren,
            ordered: isOrdered,
            indent: indent,
          ));
          continue;
        }

        if (trimmedLine.startsWith('> ')) {
          flushParagraph();
          flushListItems();
          flushTable();
          // PR-2：引用内容在解析器层即转为 Inline AST（解析只发生一次），
          // 渲染/导出直接消费 children，不再各自补字符串解析。
          elements.add(BlockquoteElement(
            children: _parseInline(trimmedLine.substring(2).trim()),
          ));
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
            // PR-2：cell 字符串在解析器层即转为 Inline AST（解析只发生一次）。
            final inlineCells = cells.map(_parseInline).toList();
            if (currentTable == null) {
              currentTable = TableElement(headers: inlineCells, rows: []);
            } else {
              currentTable!.rows.add(inlineCells);
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

        // issue #332：Setext 标题——分隔行（全为 `=` 或 `-`）紧随段落时，
        // 把段落提升为标题（`=` → level 1，`-` → level 2）。
        //
        // 必须在水平分割线判定**之前**：`===` / `---` 同形于 HR 正则。区分依据是
        // 块起始前的空行语义——Setext 分隔行紧接段落（`pendingParagraph` 非空且
        // 未经 flush）；HR 与段落的分隔行则被前一个空行打断（paragraph 已 flush）。
        // 这是 CommonMark 的实际行为，故无歧义。
        //
        // **单行限制（已知 CommonMark 偏差）**：仅当在途段落为**单行**（children
        // 无内嵌 `\n`）时才升为标题。理由：ATX 序列化 `## a\nb` 会让 `b` 脱出标题，
        // 破坏 round-trip 不动点；多行 Setext 标题在真实文档中几乎不存在，回退为
        // 段落 + 分隔线（或 HR）语义无害且往返稳定。issue #332 的用例均为单行。
        if (RegExp(r'^\s*(=+|-+)\s*$').hasMatch(trimmedLine) &&
            pendingParagraph != null &&
            pendingParagraph!.children.isNotEmpty &&
            !pendingParagraph!.children
                .any((c) => c is TextElement && c.text.contains('\n'))) {
          final level = trimmedLine.trim().startsWith('=') ? 1 : 2;
          elements.add(HeadingElement(
            level: level,
            children: pendingParagraph!.children,
          ));
          pendingParagraph = null;
          continue;
        }

        // 水平分割线：--- / *** / ___（3 个及以上）
        if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
          flushParagraph();
          flushListItems();
          flushTable();
          elements.add(const HorizontalRuleElement());
          continue;
        }

        // issue #332：四空格缩进代码块的**入口**（晚判定）——缩进 ≥4 列且非空，
        // 且上方列表 / 任务列表 / 引用 / 表格 / HR 分支均未命中，才收为 CodeElement
        // （language: null）。置于段落 fall-through 之前，使独立缩进块成为代码，
        // 而缩进列表项 / 缩进引用已被对应分支先命中，不受影响。
        //
        // 段落守卫：CommonMark 规定缩进代码块**不能打断段落**——`text\n    x`
        // 中 `    x` 应作为段落续行（`<p>text\nx</p>`），仅当无在途段落
        // （空行已 flush 或位于文档开头）时才可启动缩进代码块。
        if (indentedHere &&
            !inIndentedCode &&
            (pendingParagraph == null || pendingParagraph!.children.isEmpty)) {
          flushParagraph();
          flushListItems();
          flushTable();
          inIndentedCode = true;
          indentedCodeLines.add(line);
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
        flushIndentedCode();
        elements.add(ParagraphElement(
          children: [TextElement(line)],
        ));
      }
    }

    // issue #336-3：EOF 时未闭合代码块与闭合路径统一走 flushCodeBlock()。
    // 旧实现只在内层非空时补一个 CodeElement，导致两处不对称：
    //   (a) 未闭合的**空**代码块（` ```\n`）整体丢失——而闭合空块
    //       （` ```mermaid\n``` `）在 flushCodeBlock 里是特意保真的；
    //   (b) 未闭合的 mermaid 围栏产出 CodeElement(language: mermaid) 而非
    //       MermaidElement，两个元素走不同渲染路径（解析结果随文件是否
    //       完整而翻转，违反 round-trip 稳定性）。
    // 未闭合即视为已闭合：内容已在围栏内收集完毕，EOF 不携带额外语义。
    if (inCodeBlock) {
      flushCodeBlock();
    }
    flushIndentedCode();
    flushParagraph();
    flushListItems();
    flushTable();

    return elements;
  }

  static bool _isTableSeparatorRow(String line) {
    // issue #336-2：至少需要 `||`（长度 2）才有可切分的内层内容。
    // 单字符行 `|` 的 `substring(1, line.length - 1)` 即 `substring(1, 0)` →
    // RangeError，经外层 try/catch 降级后仍会触发 onError 上报，向
    // observability 注入误报噪音（B-5 兜底虽不崩，但错误流被污染）。
    // 分隔行本身必然形如 `|-|-|`（≥2 字符），早退不改变任何合法输入的行为。
    if (line.length < 2) return false;

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
    // issue #336-2：单字符行 `|` 同时满足 startsWith/endsWith('|')，但
    // `substring(1, line.length - 1)` 即 `substring(1, 0)` → RangeError。
    // 与 _isTableSeparatorRow 的守卫同源（合法表格行至少 `||`）。
    if (line.length < 2) return null;

    if (!line.startsWith('|') || !line.endsWith('|')) return null;
    
    final inner = line.substring(1, line.length - 1);
    if (inner.trim().isEmpty) return null;
    
    final cells = inner.split('|').map((s) => s.trim()).toList();
    if (cells.isEmpty || (cells.length == 1 && cells[0].isEmpty)) return null;
    
    return cells;
  }

  /// 公开的内联解析入口，供导出器与 cell 渲染复用。
  ///
  /// 设计动机：`TableElement.headers` / `TableElement.rows` 在 PR-2 后已统一为
  /// `List<List<InlineElement>>`（见 data/models/document.dart），cell 字符串在
  /// 解析器层即转为 Inline AST，使公式 / 加粗等行内语法在表格里与正文一致渲染。
  /// 此方法暴露 [_parseInline] 同一套逻辑，供外部以单字符串形式复用。
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
  /// 图片 > 链接 > 粗斜体 > 行内代码 > 加粗 > 斜体 > 删除线 > 纯文本。
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
      // issue #332：粗斜体优先级置于加粗/代码之前——同起点时 boldItalic 必赢，
      // 否则 `***x***` 被 bold 正则吃掉前两个 `*`（详见 _boldItalicRe 注释）。
      consider(_boldItalicRe, 2, _InlineKind.boldItalic);
      consider(_codeRe, 3, _InlineKind.code);
      consider(_boldRe, 4, _InlineKind.bold);
      consider(_italicStarRe, 5, _InlineKind.italic);
      consider(_italicUnderRe, 5, _InlineKind.italic);
      consider(_strikeRe, 6, _InlineKind.strike);

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
      // issue #332：粗斜体 = 内层再套一层加粗，复用既有嵌套能力
      // （inline_spans.dart 的 Bold → Italic 递归已支持），渲染为粗斜体。
      // 序列化为 `***x***`（InlineSerializer 的 `**`+`*x*`+`**` 拼接），
      // round-trip 保真。
      case _InlineKind.boldItalic:
        return BoldElement(
          children: [
            ItalicElement(children: _parseInlineStyle(hit.match.group(1) ?? '')),
          ],
        );
      case _InlineKind.italic:
        return ItalicElement(
            children: _parseInlineStyle(hit.match.group(1) ?? ''));
      case _InlineKind.strike:
        return StrikethroughElement(
            children: _parseInlineStyle(hit.match.group(1) ?? ''));
    }
  }
}
