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
  /// 支持的开定界行形态（判定按 `trim` 后的行内容）：
  /// - 定界符独占行：`$$`（允许前导缩进与尾随空白）
  /// - 定界符紧跟正文：`$$\begin{aligned}` / `$$ E=mc^2`
  ///   （[InlineSerializer] 把含换行的 latex 写成开闭定界符跨行的单块；
  ///   手写时把公式首行写在开定界行上也属同一形态）
  ///
  /// **开定界行内已有正文会被保留，不丢弃**：`trim` 只剥首尾空白，
  /// `$$ E=mc^2` 的正文 `E=mc^2` 随 source 一起进入解析，产出
  /// latex = ` E=mc^2`。因此不把「定界符后紧跟正文」当作非法形态降级——
  /// 那样会让序列化回写形态和手写首行公式都退回字面文本。
  ///
  /// **首行尾随空白会被裁剪**：`trim` 同时作用于首尾，`$$ E=mc^2   ` 的
  /// 三个尾随空格在 source 里已丢，但内部行（含换行后的行）只剥 `\r`、
  /// 保留全部空白。该不对称是既有惰性尾部空白语义的一小块，round-trip
  /// 不翻转（已验证）；若日后需要严格保真首行尾随空白，需把首行单独按
  /// `_stripCr` 处理而非 `trim`。
  static ({int endIndex, String source})? scan(
    List<String> lines,
    int startIndex,
  ) {
    if (startIndex < 0 || startIndex >= lines.length) return null;

    final first = _stripCr(lines[startIndex]).trim();
    // 行首（忽略前导空白）出现 `$$` 即按块级公式尝试闭合扫描。
    //
    // **前导空白容忍是刻意契约**（见测试「开定界行允许前导空白」）：
    // 本解析器对 4 空格缩进行的处理是**普通正文**而非 CommonMark 的缩进代码块
    // （`markdown_parser.dart` 只识别 ``` fence，无 indent-code-block 分支）。
    // 因此缩进的 `$$` 不会与代码块语义冲突；若日后引入 indent 代码块识别，
    // 必须在这里把前导空白 > 0 的行排除掉，否则该行为会被静默覆盖。
    if (!first.startsWith(r'$$')) return null;

    const firstScanFrom = 2;
    var source = first;
    // 增量续扫下标：每轮只从上一轮**已扫完**的文本末尾继续，而不是每轮对
    // 全量 source 从头重扫（后者在未闭合 `$$` + 长文档下退化为 O(n²)）。
    //
    // 续扫起点取「追加前」的 `source.length - 1`，即**回退一格**。这是保守取
    // 值而非必要优化：追加的 `'\n'` 本身已隔断跨拼接缝的 `$$` 定界对与
    // `\$` 转义对，从追加位置起扫即等价正确。回退一格让 `_findMatchingDelimiter`
    // 重看旧文本末字符一次，避免任何对「拼接缝位置」的推理依赖。
    //
    // **回退一格重看旧末字符是恒 no-op，不是功能必需**：
    // `_findMatchingDelimiter` 的守卫 `i < text.length - 1` 使末字符既不能当
    // `$$` 对的起点（其后必为刚追加的 `'\n'`，凑不成第二个 `$`），也不能当
    // `\$` 转义对的起点（同样要求后接 `$` 或 `\\`）。因此
    // `scanFrom = source.length`（0 偏移）与 `source.length - 1` 产出完全相同
    // 的结果。保留 `-1` 只为让重扫起点与「已扫完的文本末尾」这一语义直觉对齐，
    // 代价是每轮至多多看 1 个字符，总量仍为线性。
    var scanFrom = firstScanFrom;
    var end = FormulaExtractor.findDisplayDelimiter(source, scanFrom);
    var index = startIndex;
    while (end == -1 && index + 1 < lines.length) {
      index++;
      scanFrom = source.length - 1;
      source = '$source\n${_stripCr(lines[index])}';
      end = FormulaExtractor.findDisplayDelimiter(source, scanFrom);
    }
    if (end == -1) return null;
    return (endIndex: index, source: source);
  }

  /// 去掉行尾 CRLF 残留的 `\r`（解析器按 `\n` 切行，Windows 文件会残留）。
  static String _stripCr(String line) =>
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
}
