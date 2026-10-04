/// BlockFormulaScanner：多行块级公式（`$$`）定界边界扫描（issue #321）。
///
/// [MarkdownParser.parse] 逐行解析，多行 `$$\n...\n$$` 曾被拆成逐行字面文本
/// （`$$` 定界行退化成空公式，正文原样显示）。本扫描器在块级先收集闭合的
/// display 公式块，交回完整原文交给 `MarkdownParser._parseInline` 统一解析，
/// 与单行 `$$...$$` 走同一条链路（`_findInlineFormulaEnd` 仍禁止行内跨行）。
library;

import 'formula_extractor.dart';

/// 多行块级公式定界扫描器（纯函数，无状态）。
abstract final class BlockFormulaScanner {
  /// 扫描以 [lines][startIndex] 行为**开定界行**的块级公式块。
  ///
  /// 返回 `(endIndex, source)`：
  /// - [Record.endIndex]：闭合 `$$` 所在行下标（含）
  /// - [Record.source]：整块原文（已去掉每行 CRLF 残留 `\r`），可直接送入
  ///   `MarkdownParser._parseInline`
  ///
  /// 未闭合（文档内再无 `$$`）返回 `null`，调用方据此降级为既有逐行行为。
  ///
  /// 两种写法均支持：
  /// - 标准写法：`$$` 定界行独占（`$$\n...\n$$`）
  /// - 序列化回写形态：`$$\begin{aligned}\n...\n\end{aligned}$$`
  ///   （[InlineSerializer] 把含换行的 latex 写成开闭定界符跨行的单块）
  static ({int endIndex, String source})? scan(
    List<String> lines,
    int startIndex,
  ) {
    if (startIndex < 0 || startIndex >= lines.length) return null;

    final first = _stripCr(lines[startIndex]).trim();
    // 仅识别「行首即 `$$`」的块（CommonMark display 公式要求定界符独占行首）。
    // 行中出现的 `$$...$$` 仍走 _parseInline 的单行分支，避免把整段正文吞进公式。
    if (!first.startsWith(r'$$')) return null;

    const contentStart = 2;
    var source = first;
    var end = FormulaExtractor.findDisplayDelimiter(source, contentStart);
    var index = startIndex;
    while (end == -1 && index + 1 < lines.length) {
      index++;
      source = '$source\n${_stripCr(lines[index])}';
      end = FormulaExtractor.findDisplayDelimiter(source, contentStart);
    }
    if (end == -1) return null;
    return (endIndex: index, source: source);
  }

  /// 去掉行尾 CRLF 残留的 `\r`（解析器按 `\n` 切行，Windows 文件会残留）。
  static String _stripCr(String line) =>
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
}
