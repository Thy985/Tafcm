/// 公式收集 dispatcher：遍历 [DocumentElement] 树收集 [FormulaElement]。
///
/// #364（PR #360 round-4 follow-up）：元素类型分支 + `walkInline` /
/// `walkList`（ADR-0029 嵌套列表递归）此前在 pdf_exporter（2 处）与
/// word_exporter（1 处）各维护一份——#326 的 P2（Heading / TaskListItem）与
/// round-3（嵌套列表）三次漏补都源于此重复。本文件把「元素类型集合」收敛为
/// 唯一来源：新增元素类型时只需改 [_blockElements] 一处，PDF / Word 两侧
/// 收集逻辑即同步生效。
///
/// 「编译器强制」的前提是本文件的 switch **不带 default 分支**——`DocumentElement`
/// 是 sealed，无 default 时新增任何子类型都会触发 `non_exhaustive_switch_statement`
/// 报错；带 `case _` 则 analyzer 认为已穷尽而关闭该检查（详见 [_blockElements]
/// 末尾注释）。
///
/// 调用方各保留自己的结果落盘逻辑（Word 写 `formulaRels` 复合 key；PDF 按
/// displayMode 分 Set），本 dispatcher 只负责遍历，不做去重 / 编号。
///
/// 分层：`domain/services/exporters/`（与 pdf_exporter / word_exporter 同级，
/// 仅依赖 data/ 模型层，无反向依赖）。
library;

import '../../../data/models/document.dart';

/// 收集全部块元素中的公式（保留文档顺序，**不去重**）。
///
/// 覆盖 Paragraph / List（nested 任意深度）/ Table（headers + cells）/
/// Blockquote / Heading / TaskListItem。
///
/// 注意：MermaidElement / CodeElement 内容不是 LaTeX 公式，跳过；
/// latex 原样透传（含空格差异），去重交给调用方决定。
///
/// 空 [elements] 返回空序列（不抛异常）。
Iterable<FormulaElement> formulaElements(List<DocumentElement> elements) sync* {
  for (final e in elements) {
    yield* _blockElements(e);
  }
}

/// 收集单个块元素中的公式（保留顺序，不去重）。
///
/// 供按块遍历的调用方复用（如 Word 导出逐块写 `formulaRels`）。
/// 覆盖范围与 [formulaElements] 一致。
Iterable<FormulaElement> blockFormulas(DocumentElement element) sync* {
  yield* _blockElements(element);
}

/// 元素类型分派——**唯一的类型集合来源**（#364）。
///
/// `DocumentElement` 是 sealed 且本 switch **刻意不带 default 分支**：新增任何
/// 子类型都会触发 analyzer 的 `non_exhaustive_switch_statement` error（CI Analyze
/// 硬拦截），必须在此补 case——含公式的走 `yield*`，无公式的走显式 skip。
/// 补完后 PDF / Word 两侧无需同步修改。
Iterable<FormulaElement> _blockElements(DocumentElement element) sync* {
  switch (element) {
    case ParagraphElement(:final children):
      yield* _inlineFormulas(children);
    case ListElement():
      yield* _listFormulas(element);
    case TableElement(:final headers, :final rows):
      // PR-2：TableElement 已持有 InlineElement cell（解析只发生一次），
      // 直接遍历 cell AST，不再需要字符串兜底扫描。
      for (final h in headers) {
        yield* _inlineFormulas(h);
      }
      for (final row in rows) {
        for (final cell in row) {
          yield* _inlineFormulas(cell);
        }
      }
    case BlockquoteElement(:final children):
      // R3 修复（实测bugX）：引用块内公式也需预渲染，否则块渲染走 PNG
      // 兜底离屏 toImage（真机不稳定）→ 导出永久卡死。
      yield* _inlineFormulas(children);
    case HeadingElement(:final children):
      // review P2：标题 inline AST 内可含公式，不收集则预渲染缓存 miss。
      yield* _inlineFormulas(children);
    case TaskListItemElement(:final children):
      yield* _inlineFormulas(children);
    // 以下 4 类是 DocumentElement 的全部**无公式**子类型——必须显式枚举而
    // 不能用 `case _`：`DocumentElement` 是 sealed，无 default 分支时 analyzer
    // 的 `non_exhaustive_switch_statement` 会在**新增子类型未补分支**时报 error
    // （CI Analyze 硬拦截）；一旦有 `case _`，analyzer 认为已穷尽、关闭该检查，
    // 新增「含公式的块类型」会静默落入 default 被跳过——正是 #326 P2 与 round-3
    // 的漏收集失败模式。新增无公式类型时在此补一行 skip 即可。
    case CodeElement():
      // 代码块内容是字面量（可能含 `$…$` 文本），不是 LaTeX 公式，跳过。
      break;
    case MermaidElement():
      // Mermaid 走独立渲染与 rel 登记（word_exporter._collectMermaids），跳过。
      break;
    case EmptyLineElement():
      break;
    case HorizontalRuleElement():
      break;
  }
}

/// 遍历一个列表项并产出其公式（含 nested 任意深度递归）。
///
/// ADR-0029 嵌套列表可任意深度——不递归 nested 则深层列表项内公式
/// 漏收集 → 预渲染缓存 miss（review round-3 漏补点）。
Iterable<FormulaElement> _listFormulas(ListElement list) sync* {
  yield* _inlineFormulas(list.children);
  for (final n in list.nested) {
    yield* _listFormulas(n);
  }
}

/// 从 inline 子元素中筛出 [FormulaElement]。
///
/// Bold / Italic / Strikethrough 的 children 内**不含**嵌套公式——
/// `InlineSerializer` 与渲染路径均为扁平结构（公式是 leaf），故无需递归。
/// 保持扁平遍历是现有三处收集器的既定口径，纯重构不扩展。
Iterable<FormulaElement> _inlineFormulas(List<InlineElement> children) sync* {
  for (final c in children) {
    if (c is FormulaElement) yield c;
  }
}
