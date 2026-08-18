# Markdown 生态可替代的手写实现清单

**日期**: 2026-08-18
**说明**: 盘点 FormulaFix 中「本来可以用 Markdown 生态库，但当前为手写实现」的功能。
**判断标准**: 该功能在 pub.dev / JS 生态有成熟稳定库，且引入成本 < 维护收益。

---

## 0. 现状总览

```text
当前 pubspec 依赖（与本主题相关）：
  flutter_math_fork ^0.7.2   ← 公式渲染（fork 自 flutter_math）
  flutter_highlight ^0.7.0   ← 代码高亮（Markdown 生态库，已用）
  flutter_inappwebview ^6.0.0 ← Mermaid / MathJax 渲染载体（WebView）
  pdf 3.10.7                 ← PDF 导出（生态库，已用）
  archive / xml / crypto     ← Word OOXML 打包基础设施（生态库）

未引入的生态库：
  markdown（Dart）           ← Markdown AST 解析
  flutter_markdown           ← Markdown 渲染
  markdown_widget            ← Markdown 渲染（更现代）
  katex / flutter_katex      ← LaTeX 渲染
  docx（Dart）               ← Word 生成
```

---

## 1. 可换生态但当前手写清单

### 1.1 Markdown 解析（Parser）—— 手写 ✅ 建议保留（有理由）

| 项 | 当前实现 | 生态替代 | 评估 |
|----|---------|---------|------|
| Markdown → AST 解析 | `core/parser/markdown_parser.dart`（~500 行手写） | `markdown` 包（Dart） | **建议保留手写**：自定义元素扩展（Formula/Mermaid/TaskList）、降级容错（单行错误降级 Paragraph）、GBK 兼容均已深度定制；生态库难以匹配。Run #008 fuzz 已修复 6 个真实 bug，质量可控 |
| 行内解析（Bold/Italic/Formula/InlineCode 组合） | 同上 `_parseInline` | `markdown` 包 inline 解析 | 同上，深度定制（`**混*合**` 嵌套语义与生态不同） |

### 1.2 Markdown 序列化（Serializer）—— 手写 ✅ 建议保留

| 项 | 当前实现 | 生态替代 | 评估 |
|----|---------|---------|------|
| AST → Markdown 文本 | `markdown_serializer.dart` + `block_serializer.dart` | `markdown` 包无序列化能力；`markdown_widget` 无 | **无成熟生态替代**（Dart 生态序列化库缺失），保留手写是唯一选择 |
| round-trip 一致性 | roundtrip_fuzz_test（1000 轮） | 无 | 生态库本身也缺此能力 |

### 1.3 LaTeX 公式渲染 —— 已用生态（flutter_math_fork）⚠️ 有可选替代

| 项 | 当前实现 | 生态替代 | 评估 |
|----|---------|---------|------|
| 公式渲染 | `flutter_math_fork`（已用） | `katex_flutter` / `flutter_katex` | 当前 fork 已满足；如需 KaTeX 精确排版可评估，非必须 |
| 公式提取（PDF 导出用） | `formula_extractor.dart` 手写 | 无直接生态 | 保留手写 |

### 1.4 Mermaid 渲染 —— 手写封装（JS 生态）⚠️ 可评估

| 项 | 当前实现 | 生态替代 | 评估 |
|----|---------|---------|------|
| Mermaid 图渲染 | `mermaid_block.dart` + WebView 加载 `mermaid.min.js`（assets 手写封装） | Flutter 纯 Dart Mermaid 渲染库不成熟 | 当前方案合理（复用 JS 生态 mermaid.js）；纯 Dart 替代（如 `dart_mermaid`）不成熟，不建议切换 |
| PDF 中 Mermaid | `pdf_mermaid_renderer.dart` 手写 | 无 | 保留手写 |

### 1.5 Word 导出 —— 手写 OOXML ⚠️ 强烈建议评估生态

| 项 | 当前实现 | 生态替代 | 评估 |
|----|---------|---------|------|
| .docx 生成 | `word_ooxml_builder.dart` 手写 ECMA-376 OOXML（~200 行）+ `word_exporter.dart` | `docx` 包（pub.dev，成熟，支持段落/表格/样式/公式） | **强烈建议评估 `docx` 包**：手写 OOXML 维护成本高（styles/settings/numbering 补齐等），生态包覆盖度更高、兼容性更好（Word/WPS 打开验证） |
| 公式转 OOXML OMML | `word_ooxml_builder.dart` 手写 | `docx` 包内置公式支持 | 同上 |

### 1.6 代码高亮 —— 已用生态 ✅

| 项 | 当前实现 | 生态替代 | 评估 |
|----|---------|---------|------|
| 代码高亮 | `flutter_highlight`（已用） | — | 已用生态，无手写 |

### 1.7 PDF 导出 —— 已用生态 + 手写组合 ✅

| 项 | 当前实现 | 生态替代 | 评估 |
|----|---------|---------|------|
| PDF 基础排版 | `pdf` 包（已用） | — | 生态 |
| 公式 SVG 渲染 | `svg_to_pdf.dart` / `svg_ast.dart` 手写 | `pdf` 包无公式能力 | 保留手写（生态缺失） |
| 页眉页脚 | `pdf_page_decoration.dart` 手写 | `pdf` 包部分支持 | 可简化为生态 API |

### 1.8 富文本渲染（编辑器内）—— 手写 ✅ 建议保留

| 项 | 当前实现 | 生态替代 | 评估 |
|----|---------|---------|------|
| 块渲染器（paragraph/code/quote/table/heading） | `presentation/blocks/*` 手写 | `flutter_markdown` / `markdown_widget` | **建议保留手写**：本项目是**编辑器**（WYSIWYG + IME + 选区同步），不是渲染器；`flutter_markdown` 是只读渲染，无法支撑编辑模型 |

---

## 2. 结论与建议

```text
手写实现盘点（8 项）：
  ✅ 建议保留（有架构理由）  4 项：Parser / Serializer / 富文本编辑器渲染 / SVG 公式
  ✅ 已用生态                2 项：代码高亮 / PDF 基础 + MathJax/Mermaid JS
  ⚠️ 建议评估生态替代        2 项：Word 导出（docx 包）/ 公式渲染（katex_flutter，可选）

最高优先级建议：
  ⚠️ Word 导出改用 `docx` 包 —— 手写 OOXML 维护成本高，生态包成熟
     （需验证：公式 OMML / 表格 / 中文兼容性 / Word 与 WPS 打开）

核心判断：Parser/Serializer/编辑器渲染保留手写是**架构决策**（编辑模型定制），
非"生态不可用"；Word 导出是**唯一明确的生态替代机会**。
```

---

## 3. 生态替代评估表（汇总）

| 功能域 | 当前实现 | 生态替代 | 切换建议 | 原因 |
|--------|---------|---------|---------|------|
| Markdown 解析 | 手写 ~500 行 | `markdown` 包 | ❌ 保留 | 深度定制 + fuzz 已验证 |
| Markdown 序列化 | 手写 | 无生态 | ❌ 保留 | 生态缺失 |
| 编辑器富文本 | 手写 blocks | flutter_markdown | ❌ 保留 | 编辑器非渲染器 |
| 公式渲染 | flutter_math_fork | katex_flutter | ⚠️ 可选 | 当前已满足 |
| Mermaid 渲染 | WebView + JS | 无成熟 Dart 库 | ❌ 保留 | 方案合理 |
| 代码高亮 | flutter_highlight | — | ✅ 已用 | — |
| PDF 导出 | pdf + 手写 SVG | pdf 包 | ✅ 已用 | — |
| **Word 导出** | **手写 OOXML** | **`docx` 包** | **⚠️ 建议切换** | **维护成本高，生态成熟** |
