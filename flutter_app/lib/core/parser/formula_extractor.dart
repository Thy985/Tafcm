/// FormulaExtractor：从纯文本中抽取行内 / 块级 LaTeX 公式。
///
/// 供 `MarkdownParser._parseInline` 在解析行内内容时调用，也供
/// [BlockFormulaScanner] 复用同一套定界符 / 转义规则。
library;

class FormulaMatch {
  final String latex;
  final int start;
  final int end;
  final bool displayMode;

  const FormulaMatch({
    required this.latex,
    required this.start,
    required this.end,
    required this.displayMode,
  });
}

class FormulaExtractor {
  static const Set<String> _latexCommands = {
    'vec', 'hat', 'bar', 'tilde', 'overline', 'underline',
    'dot', 'ddot', 'check', 'breve', 'grave', 'acute',
    'widehat', 'widetilde', 'overset', 'underset',
    'overbrace', 'underbrace', 'overleftarrow', 'overrightarrow',
    'frac', 'dfrac', 'tfrac', 'binom', 'cfrac',
    'sqrt',
    'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
    'arcsin', 'arccos', 'arctan',
    'sinh', 'cosh', 'tanh', 'coth',
    'log', 'ln', 'exp',
    'lim', 'limsup', 'liminf',
    'sum', 'prod', 'int', 'oint', 'iint', 'iiint', 'iiiint',
    'bigcup', 'bigcap', 'bigoplus', 'bigotimes', 'bigvee', 'bigwedge',
    'mathrm', 'mathbf', 'mathit', 'mathsf', 'mathtt',
    'mathcal', 'mathfrak', 'mathbb', 'operatorname', 'text', 'textbf', 'textit',
    'leq', 'le', 'geq', 'ge', 'neq', 'ne',
    'approx', 'sim', 'simeq', 'cong', 'equiv', 'doteq', 'triangleq',
    'propto', 'prec', 'succ', 'preceq', 'succeq', 'll', 'gg',
    'in', 'notin', 'ni', 'owns',
    'subset', 'supset', 'subseteq', 'supseteq', 'nsubseteq', 'nsupseteq',
    'cup', 'cap', 'setminus', 'emptyset', 'varnothing',
    'pm', 'mp', 'times', 'div', 'cdot', 'ast', 'star', 'circ', 'bullet',
    'oplus', 'ominus', 'otimes', 'oslash', 'odot',
    'to', 'mapsto', 'rightarrow', 'leftarrow', 'leftrightarrow',
    'Rightarrow', 'Leftarrow', 'Leftrightarrow',
    'uparrow', 'downarrow', 'updownarrow', 'Uparrow', 'Downarrow',
    'infty', 'partial', 'nabla', 'forall', 'exists', 'nexists',
    'therefore', 'because', 'square',
    'langle', 'rangle', 'lfloor', 'rfloor', 'lceil', 'rceil',
    'ldots', 'cdots', 'vdots', 'ddots',
    'color', 'textcolor', 'colorbox', 'boxed', 'fbox',
    'cancel', 'bcancel', 'xcancel',
    'quad', 'qquad',
    'stackrel',
    'arg', 'argmin', 'argmax',
    'min', 'max', 'sup', 'inf', 'det', 'dim', 'ker', 'deg', 'hom', 'gcd',
    'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'varepsilon',
    'zeta', 'eta', 'theta', 'vartheta', 'iota', 'kappa',
    'lambda', 'mu', 'nu', 'xi', 'omicron', 'pi', 'varpi',
    'rho', 'varrho', 'sigma', 'varsigma', 'tau', 'upsilon',
    'phi', 'varphi', 'chi', 'psi', 'omega',
    'Gamma', 'Delta', 'Theta', 'Lambda', 'Xi', 'Pi',
    'Sigma', 'Upsilon', 'Phi', 'Psi', 'Omega',
  };

  /// 从 [text] 中抽取全部公式，返回按出现位置排序、互不重叠的匹配列表。
  ///
  /// **`latex` 的语义（调用方须知）**：
  /// - 行内公式（`displayMode == false`）：`latex` 是 `[text, start, end)` 的
  ///   **逐字子串**（去掉首尾各一个 `$`）。
  /// - 块级公式（`displayMode == true`）：`latex` 是同一区间去掉紧贴定界符的
  ///   **一层**首尾换行（`\n` / `\r\n`，见 [_stripFenceNewlines]）后的结果，
  ///   因此**不再保证是逐字子串**——多行写法 `$$\nE=mc^2\n$$` 得到
  ///   `E=mc^2` 而非 `\nE=mc^2\n`。内部换行原样保留。
  ///   `start` / `end` 仍是**原文** `[text]` 中的字节区间下标，不受规范化影响。
  ///
  /// 这样归一化的目的：多行写法 `$$\nE=mc^2\n$$` 与单行写法 `$$E=mc^2$$` 产出
  /// **同一个** latex 字符串，SVG 预渲染缓存 key 一致，且空围栏 `$$\n$$`
  /// 与 `$$$$` 归一到同一无误判结果。只剥一层换行，正文内部换行
  /// （LaTeX 多行排版，如 `\begin{aligned}`）不受影响。
  static List<FormulaMatch> extractFormulas(String text) {
    final results = <FormulaMatch>[];

    _extractExplicitFormulas(text, results);
    _extractImplicitFormulas(text, results);

    results.sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return (b.end - b.start).compareTo(a.end - a.start);
    });

    final filtered = <FormulaMatch>[];
    int lastEnd = -1;
    for (final m in results) {
      if (m.start >= lastEnd) {
        filtered.add(m);
        lastEnd = m.end;
      }
    }

    return filtered;
  }

  static void _extractExplicitFormulas(String text, List<FormulaMatch> results) {
    int i = 0;
    while (i < text.length) {
      if (i < text.length - 1 && text[i] == '\\' &&
          (text[i + 1] == r'$' || text[i + 1] == '\\')) {
        i += 2;
        continue;
      }

      if (i < text.length - 1 && text[i] == r'$' && text[i + 1] == r'$') {
        final end = _findMatchingDelimiter(text, i + 2);
        if (end != -1) {
          results.add(FormulaMatch(
            latex: _stripFenceNewlines(text.substring(i + 2, end)),
            start: i,
            end: end + 2,
            displayMode: true,
          ));
          i = end + 2;
          continue;
        }
      }

      if (text[i] == r'$' && !_isEscaped(text, i)) {
        final end = _findInlineFormulaEnd(text, i + 1);
        if (end != -1) {
          results.add(FormulaMatch(
            latex: text.substring(i + 1, end),
            start: i,
            end: end + 1,
            displayMode: false,
          ));
          i = end + 1;
          continue;
        }
      }

      i++;
    }
  }

  static void _extractImplicitFormulas(String text, List<FormulaMatch> results) {
    final commands = _latexCommands.join('|');
    final regex = RegExp(
      '(?<![A-Za-z0-9\\\\])($commands)(?:\\{(?:[^{}]+|\\{[^{}]*\\})*\\}|\\([^)]*\\))',
    );

    for (final match in regex.allMatches(text)) {
      final matchedText = match.group(0)!;
      final hasBackslash = match.start > 0 && text[match.start - 1] == r'\';

      // issue #336-5：隐式 **括号** 形式 + 实参含逗号或空白时，按散文处理，
      // 不提取。
      //
      // 隐式提取本身是刻意特性（`vec{n}` → `\vec{n}`，见
      // formula_extractor_test「隐式公式识别」组），故只对括号形式收窄，
      // 花括号形式一律保留。理由：
      //   - `max{a,b}` / `vec{n}` 无歧义，是 LaTeX 惯用写法；
      //   - `max(a,b)` 是散文里函数调用的常态形态（`we compute max(a,b)`），
      //     且 LaTeX 双参数函数的标准写法是 `\max_{a}` 而非括号，
      //     含逗号的括号形式误判率极高；
      //   - `\([^)]*\)` 遇嵌套括号本就提前截断（`max(f(x),y)` 只取到 `(`），
      //     逗号 / 空白守卫顺带把这类破损匹配一并排除。
      //
      // 关于 `hasBackslash`：上方 regex 的 lookbehind `(?<![A-Za-z0-9\\])`
      // 已把反斜杠前缀排除在外，故本分支（隐式提取）里 `hasBackslash` 恒为
      // false，`\max(a,b)` 从来不走这里（带反斜杠的命令经 `$...\$` /
      // normalizeLatex 路径处理）。它仍保留在下方 latex 拼装处，仅作为
      // 防御性分支存在——不要据此断言 `\max(a,b)` 的行为。
      if (!hasBackslash && matchedText.contains('(')) {
        final args = matchedText.substring(1, matchedText.length - 1);
        if (args.contains(',') || RegExp(r'\s').hasMatch(args)) continue;
      }

      String latex;
      if (hasBackslash) {
        latex = matchedText;
      } else {
        latex = '\\$matchedText';
        latex = _ensureBackslashForCommands(latex);
      }

      results.add(FormulaMatch(
        latex: latex,
        start: match.start,
        end: match.end,
        displayMode: false,
      ));
    }
  }

  static String _ensureBackslashForCommands(String input) {
    if (!input.contains('{') && !input.contains('(')) return input;
    final commands = _latexCommands.join('|');
    final regex = RegExp('(?<!\\\\)\\b($commands)\\b');
    return input.replaceAllMapped(
      regex,
      (m) => '\\${m.group(1)!}',
    );
  }

  static int _findMatchingDelimiter(String text, int start) {
    int i = start;
    while (i < text.length) {
      if (i < text.length - 1 && text[i] == '\\' &&
          (text[i + 1] == r'$' || text[i + 1] == '\\')) {
        i += 2;
        continue;
      }

      if (i < text.length - 1 && text[i] == r'$' && text[i + 1] == r'$') {
        return i;
      }
      i++;
    }
    return -1;
  }

  /// 查找 display 公式闭合定界符 `$$` 的起始下标，未找到返回 -1。
  ///
  /// 与 [extractFormulas] 内部使用同一套转义规则（`\$` / `\\` 不算定界符），
  /// 供 [BlockFormulaScanner] 跨行拼接后复用，避免转义语义出现第二份实现。
  ///
  /// [start] 为开定界符 `$$` 之后的下标；扫描**允许跨 `\n`**——标准多行块级
  /// 公式（`$$\n...\n$$`）的正文就在换行之后。
  static int findDisplayDelimiter(String text, int start) =>
      _findMatchingDelimiter(text, start);

  /// 剥掉 display 公式正文紧贴定界符的一层换行（CRLF 兼容）。
  ///
  /// 多行写法 `$$\nE=mc^2\n$$` 的首尾换行是定界产物而非 LaTeX 正文，
  /// 剥掉后与单行写法 `$$E=mc^2$$` 产出**同一个** latex（SVG 预渲染缓存
  /// key 一致，且 `$$\n$$\n$$` 空块不会被当成非空公式）。
  /// 只剥一层，正文**内部**换行（LaTeX 多行排版）原样保留。
  static String _stripFenceNewlines(String latex) {
    var result = latex;
    if (result.startsWith('\r\n')) {
      result = result.substring(2);
    } else if (result.startsWith('\n')) {
      result = result.substring(1);
    }
    if (result.endsWith('\r\n')) {
      result = result.substring(0, result.length - 2);
    } else if (result.endsWith('\n')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// 行内公式 `$...$` 的闭合 `$` 下标，未闭合返回 -1。
  ///
  /// **遇 `\n` 即判未闭合是刻意行为**（issue #321 修复时确认）：行内公式按
  /// CommonMark 语义不允许跨行，若放开会让文档里任意两个孤立 `$` 跨整篇配对。
  /// 多行块级公式由 [BlockFormulaScanner] 在块级先行收集，不走本函数。
  static int _findInlineFormulaEnd(String text, int start) {
    int i = start;
    while (i < text.length) {
      if (text[i] == '\\') {
        i += 2;
        continue;
      }

      if (text[i] == r'$') {
        return i;
      }

      if (text[i] == '\n') {
        return -1;
      }
      i++;
    }
    return -1;
  }

  static bool _isEscaped(String text, int index) {
    if (index == 0) return false;
    int backslashCount = 0;
    for (int i = index - 1; i >= 0 && text[i] == '\\'; i--) {
      backslashCount++;
    }
    return backslashCount % 2 == 1;
  }

  static String normalizeLatex(String input) {
    String result = input;

    result = result.replaceAll('→', r'\to');
    result = result.replaceAll('←', r'\gets');
    result = result.replaceAll('↔', r'\leftrightarrow');
    result = result.replaceAll('⇒', r'\Rightarrow');
    result = result.replaceAll('⇔', r'\Leftrightarrow');
    result = result.replaceAll('↦', r'\mapsto');
    result = result.replaceAll('∂', r'\partial');
    result = result.replaceAll('∇', r'\nabla');
    result = result.replaceAll('∞', r'\infty');
    result = result.replaceAll('∫', r'\int');
    result = result.replaceAll('∑', r'\sum');
    result = result.replaceAll('∏', r'\prod');
    result = result.replaceAll('√', r'\sqrt');
    result = result.replaceAll('±', r'\pm');
    result = result.replaceAll('∓', r'\mp');
    result = result.replaceAll('×', r'\times');
    result = result.replaceAll('÷', r'\div');
    result = result.replaceAll('·', r'\cdot');
    result = result.replaceAll('≤', r'\leq');
    result = result.replaceAll('≥', r'\geq');
    result = result.replaceAll('≠', r'\neq');
    result = result.replaceAll('≈', r'\approx');
    result = result.replaceAll('≡', r'\equiv');
    result = result.replaceAll('∝', r'\propto');
    result = result.replaceAll('∈', r'\in');
    result = result.replaceAll('∉', r'\notin');
    result = result.replaceAll('⊂', r'\subset');
    result = result.replaceAll('⊃', r'\supset');
    result = result.replaceAll('⊆', r'\subseteq');
    result = result.replaceAll('⊇', r'\supseteq');
    result = result.replaceAll('∪', r'\cup');
    result = result.replaceAll('∩', r'\cap');
    result = result.replaceAll('∅', r'\emptyset');

    final greekLetters = {
      'Δ': r'\Delta', 'δ': r'\delta', 'π': r'\pi', 'α': r'\alpha',
      'β': r'\beta', 'γ': r'\gamma', 'ε': r'\epsilon', 'ζ': r'\zeta',
      'η': r'\eta', 'θ': r'\theta', 'ι': r'\iota', 'κ': r'\kappa',
      'λ': r'\lambda', 'μ': r'\mu', 'ν': r'\nu', 'ξ': r'\xi',
      'ρ': r'\rho', 'σ': r'\sigma', 'τ': r'\tau', 'υ': r'\upsilon',
      'φ': r'\phi', 'χ': r'\chi', 'ψ': r'\psi', 'ω': r'\omega',
      'Γ': r'\Gamma', 'Θ': r'\Theta', 'Λ': r'\Lambda', 'Ξ': r'\Xi',
      'Π': r'\Pi', 'Σ': r'\Sigma', 'Φ': r'\Phi', 'Ψ': r'\Psi', 'Ω': r'\Omega',
    };

    greekLetters.forEach((unicode, latex) {
      result = result.replaceAll(unicode, latex);
    });

    result = result.replaceAllMapped(
      RegExp(r'dy/dx'),
      (_) => r'\frac{dy}{dx}',
    );
    result = result.replaceAllMapped(
      RegExp(r'd\^2y/dx\^2'),
      (_) => r'\frac{d^2y}{dx^2}',
    );
    result = result.replaceAllMapped(
      RegExp(r'd(\w+)/d(\w+)'),
      (m) => '\\frac{d${m.group(1)}}{d${m.group(2)}}',
    );

    return result;
  }
}
