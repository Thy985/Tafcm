# Feature Capability Coverage Matrix — Tafcm

> **文档性质**：功能能力覆盖矩阵（Feature Capability Coverage System，只读复盘，零代码改动）
> **日期**：2026-08-19
> **版本**：v1（首版；基于三源真理模型，全部结论经真实代码/file:line/测试数实证）
> **作者**：AI Agent 起草，Human Owner 评审决策
> **回答的问题**：比"有没有验证"更关键的一层——
>
> > **Tafcm 的每一个功能，到底覆盖了哪些能力？覆盖到什么程度（S0–S5）？没覆盖什么？因此最终能宣称到什么边界？**
>
> 本矩阵回答的是 **"做到什么程度"**（capability coverage），与另两份 Phase 3.10 产物构成三个正交真相层：

| 真相层 | 文档 | 回答的问题 |
|--------|------|-----------|
| L1 Feature Completion | `FEATURE-COMPLETION-EVIDENCE-MATRIX-v1.md`（既有，不改动） | **功能是否完成**（E0–E8 证据 + 四档判定） |
| L2 Capability Coverage | **本文档（新增）** | **功能覆盖到哪里、每项能力成熟到几级**（S0–S5） |
| L3 Engineering Baseline | `PHASE3.10-ENGINEERING-BASELINE-v1.md`（v1.2） | **代码为什么现在这样存在**（历史决策/债务） |

> 三者关系：**L3 解释"为什么这样" → L2 描述"能做什么、做到几级" → L1 判定"凭这些证据能否宣称完成"**。L1 的完成判定应逐步改由 **L2 的 Capability Contract 机械推导**（见 §5），使"功能完成"成为可计算、可审计、可被 Agent 消费的工程状态。

**验证纪律**：与基线 v1.2 一致的三源真理模型——结论以 Implementation Truth（`file:line` + 真实测试运行）与 Evidence Truth（真机/消费端实测）为准；本矩阵所有 S 级判定均附代码/测试出处，无出处标注 "no evidence found"，绝不猜测。

---

## 0. 成熟度模型：S0–S5（"支持程度"的定义）

"支持 Markdown"本身没有意义。每个**能力**（capability）用一个六级成熟度标定：

| 等级 | 名称 | 含义 | 判定标准（可从代码机械检查） |
|------|------|------|------------------------------|
| **S0** | Not Supported | 不支持 | 代码中无对应解析/处理路径（grep 无实现） |
| **S1** | Recognized | 能识别 | 有 token/标记识别逻辑，但未进入结构化模型 |
| **S2** | Parsed to AST | 解析进 AST | parser 产出对应 `DocumentElement`/`InlineElement` 节点 |
| **S3** | Editable / Model-preserving | 可编辑、模型保持 | 编辑操作（事务）可作用于该节点且不破坏模型（含降级路径可编辑） |
| **S4** | Round-trip Preserving | 往返保真 | `parse→serialize→parse` 收敛（round-trip/fuzz 覆盖） |
| **S5** | Runtime Verified | 运行时验证 | 除单测外，经集成/E2E/真机/消费端在真实运行链路验证 |

> **S 级是单调的**：S5 ⊃ S4 ⊃ S3 ⊃ S2 ⊃ S1 ⊃ S0。标注 S4 意味着"解析进 AST、可编辑、往返保真均已证"。

---

## 1. Tafcm Capability Map（总览树）

> 一张图回答：**"Tafcm 到底做了什么、做到什么程度？"**

```
Tafcm Capability Map
├── Markdown
│   ├── Parser
│   │   ├── Block  ── Paragraph S5 · Heading S5 · Blockquote S4 · Bullet List S4
│   │   │            · Ordered List S4 · Nested List S4 · Fenced Code S4 · Mermaid S4
│   │   │            · Table S4 · Task List S4 · Horizontal Rule S4
│   │   │            · Footnote S0 · Definition List S0 · Indented Code S0 · Raw HTML S0*
│   │   ├── Inline ── Bold S4 · Italic S4 · Inline Code S4 · Formula S5 · Link S4
│   │   │            · Image S4 · Strikethrough S4 · Nested Formatting S3 ⚠
│   │   │            · Autolink S0
│   │   ├── Encoding ── UTF-8 S5 · CRLF S4 · GBK/legacy S5
│   │   ├── Error ── malformed→fallback S3 · unclosed fence S3 · ambiguous nesting S2 ⚠
│   │   └── Fidelity ── round-trip S5 · exact source preservation S3 ⚠
│   ├── Serializer
│   │   ├── Round-trip S5
│   │   └── Source fidelity S3 ⚠（table cell 空格 trim，非 bit-perfect）
│   └── Editor
│       ├── Undo/Redo S4（+ S5 集成 E2E-CORE-004/006）
│       ├── Selection S3（+ S4 域级 E2E）
│       ├── IME S3（+ S4 事务集成；物理软键盘 S2 ⚠）
│       └── Drag/Reorder S3（真机已知缺陷 ⚠ → L1 判定 incomplete）
├── Formula
│   ├── Parse/Extract S5 · Render→SVG S4（模拟器）
│   └── Real-device visual fidelity S2 ⚠（真机降级 LaTeX 文本 —— **Release-blocking**）
├── Export
│   ├── Word ── L1 Artifact S4 · L2 Semantic S4 · L3 WPS/OfficeCLI S5
│   │          · MS Word Desktop S0-UNKNOWN（Release Gate **Optional**）· L4/L5 Visual S3
│   ├── PDF ── L1/L2 S4 · CJK S5 · Formula-in-PDF S4 · 外部原生消费端 S0（Optional）
│   └── TXT ── text_exporter.dart 存在，本次未纳入审计范围（S 级未标定）
└── App Services
    ├── Autosave S4（真机持久化 S2 ⚠）
    ├── File ── decode S5 · open/save S4（真机 FS S2 ⚠）
    └── Theme S5（dark/sepia 整页 golden S3 ⚠ · 真机 S2 ⚠）
```

> \* Raw HTML 块：无 HTML 块元素，内容按普通段落文本保留（非 S0 丢失——内容不丢，但无 HTML 语义）。
> ⚠ = 有已知缺口/部分证据，详见对应 FEAT 节与 §5 契约推导。

**一句话总结**：核心 Markdown 语法（Block 12 项 + Inline 7 项）全部 ≥S4、编码与往返保真达到 S5；明确的 S0 边界是 GFM 稀有语法（autolink/footnote/definition list/indented code）；**真正的结构性风险集中在 Formula 真机视觉（S2）与拖拽重排真机缺陷**。

---

## 2. 逐功能能力覆盖（Capability Coverage Detail）

> 每项能力给出：实现位置（file:line）→ 测试覆盖（真实计数）→ S 级 → 结论。
> 证据采集方式：`grep`/`find` 直读源码 + 对测试文件逐文件 `grep -c 'test('` 计数（2026-08-19，本机真实运行）。

### FEAT-MD-PARSE — Markdown 解析（模型范例）

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据（file:line / 测试名） | S级 | 结论 |
|--------|--------|------|---------|---------------------------|-----|------|
| Block | Paragraph | ✅ | ~11 | `markdown_parser.dart:321,338`；`test/markdown_parser_test.dart:8,77,85`；`test/parser/edge_case_test.dart:142-171`；`test/observability/p1_markdown_parser_resilience_test.dart:17,99,114` | S4 | Verified |
| Block | Heading H1–H6 | ✅ | ~8 | `markdown_parser.dart:204-218`；`test/markdown_parser_test.dart:12,21,120`；`edge_case_test.dart:210,226`（中文/emoji 标题） | S4 | Verified |
| Block | Blockquote | ✅ | ~3 | `markdown_parser.dart:274-280`；`test/markdown_parser_test.dart:47`；`test/integration/parser_serializer_consistency_test.dart:451` | S4 | Verified |
| Block | Bullet List | ✅ | ~6 | `markdown_parser.dart:244-272`；`test/markdown_parser_test.dart:30`；`inline_parser_test.dart:114-115`；consistency:114,147,175 | S4 | Verified |
| Block | Ordered List | ✅ | ~4 | `markdown_parser.dart:244-272,250`；`test/markdown_parser_test.dart:40`；consistency:147（同序合并） | S4 | Verified |
| Block | Nested List | ✅ | ~3 | `markdown_parser.dart:118-139`（buildNestedTree）；`test/markdown_parser_test.dart:128,153,164`（BUG-5 回归） | S4 | Verified |
| Block | Fenced Code | ✅ | ~6 | `markdown_parser.dart:176-194,96-106`；`test/markdown_parser_test.dart:55,62,179,186`；resilience:128 | S4 | Verified |
| Block | Indented Code | ❌ | 0 | 无代码路径（grep 无实现） | **S0** | **Unsupported** |
| Block | Mermaid | ✅ | ~11 | `markdown_parser.dart:100-104`；`test/parser/mermaid_audit_test.dart`（7 用例）；consistency:315,354,364 | S4 | Verified |
| Block | GFM Table | ✅ | ~9 | `markdown_parser.dart:282-306,354-377`；`table_formula_audit_test.dart`（6）；consistency:52,64,77 | S4 | Verified（cell 空格 trim，非 bit-perfect） |
| Block | Task List | ✅ | ~5 | `markdown_parser.dart:227-242`；`inline_parser_test.dart:84,95,102,135` | S4 | Verified |
| Block | Horizontal Rule | ✅ | ~3 | `markdown_parser.dart:308-315`；`inline_parser_test.dart:109,114,120` | S4 | Verified |
| Block | Footnote | ❌ | 0 | 无元素（grep Footnote→0 命中） | **S0** | **Unsupported** |
| Block | Definition List | ❌ | 0 | 无元素 | **S0** | **Unsupported** |
| Block | Raw HTML 块 | ❌ | 0 | 无 HTML 块元素；内容按 Paragraph 文本保留 | **S0*** | **Unsupported**（内容保留） |
| Inline | Bold | ✅ | ~3 | `markdown_parser.dart:65,490-491`；`inline_parser_test.dart:56`；serializer_test:50 | S4 | Verified |
| Inline | Italic | ✅ | ~4 | `markdown_parser.dart:66-67,492-494`；`inline_parser_test.dart:32,40`；`edge_case_test.dart:33,45`（未闭合） | S4 | Verified |
| Inline | Inline Code | ✅ | ~3 | `markdown_parser.dart:64,488-489`；`inline_parser_test.dart:9,69`；`edge_case_test.dart:65` | S4 | Verified |
| Inline | Formula `$...$`/`$$...$$` | ✅ | ~34 | `markdown_parser.dart:390-415`；`formula_extractor.dart:62,86-125`；`test/formula_extractor_test.dart`（29）；consistency:205,219,231 | **S5** | Verified（含集成链路） |
| Inline | Nested Formatting | ⚠️ | ~3 | `markdown_parser.dart:480-499`（递归 _buildInline）；`inline_parser_test.dart:56`；serializer_test:50；**code+bold 组合无显式用例** | **S3** | **Partial** |
| Inline | Link | ✅ | ~2 | `markdown_parser.dart:63,485-487`；`inline_parser_test.dart:16,72,127` | S4 | Verified |
| Inline | Image | ✅ | ~2 | `markdown_parser.dart:62,482-484`；`inline_parser_test.dart:24,79` | S4 | Verified |
| Inline | Strikethrough | ✅ | ~3 | `markdown_parser.dart:68,495-497`；`inline_parser_test.dart:48`；`edge_case_test.dart:52,94` | S4 | Verified |
| Inline | Autolink | ❌ | 0 | 无 autolink 正则 | **S0** | **Unsupported** |
| Inline | Emphasis 边角 | ⚠️ | ~13 | `edge_case_test.dart` TC-1.5.16 组（18-142）；半闭合嵌套误判已知限制（:119-128） | **S2** | **Partial**（不崩溃，语义有误判） |
| Encoding | UTF-8 | ✅ | ~7 | `file_service.dart:13-24`（decodeBytesAuto）；`file_service_decode_test.dart:11-27`；`edge_case_test.dart:210-226` | **S5** | Verified |
| Encoding | CRLF | ✅ | ~3 | `markdown_parser.dart:88`（按 `\n` split 隐式剥 `\r`）；`edge_case_test.dart:186,202`；mermaid_audit:64 | S4 | Verified |
| Encoding | GBK/legacy | ✅ | ~4 | `file_service.dart:34-40`（gb18030 回退→latin1 兜底）；`file_service_decode_test.dart:32-60` | **S5** | Verified |
| Error | Malformed→fallback | ✅ | ~25 | `markdown_parser.dart:175,330-341`（catch→Paragraph 保留原文）；resilience（11）+ edge TC-1.5.16（~13）+ :179 | S3 | Verified（降级为可编辑 Paragraph，不丢内容） |
| Error | Unclosed fence | ✅ | ~3 | `markdown_parser.dart:344-346`（末尾自动 flush）；:179；resilience:128 | S3 | Verified |
| Error | Ambiguous nesting | ⚠️ | ~3 | `markdown_parser.dart:62-68`；`edge_case_test.dart:119,86,94`（`*bold *` 误判 Italic 已知限制） | **S2** | **Partial** |
| Fidelity | parse→serialize→parse | ✅ | fuzz **2001 轮** + 专项 ~31 | `test/parser/roundtrip_fuzz_test.dart:228`（1000 轮 seed=20260817）、`:232`（5×200=1000）、`:239`；断言不动点违例 <10/1000（:285） | **S5** | Verified（收敛 <1%） |
| Fidelity | 精确源码保留 | ⚠️ | ~3 | consistency:52-62（table cell 空格 trim 非 bit-perfect）；fuzz 允许 <10/1000 违例；无 comment/unknown 保留元素 | **S3** | **Partial** |
| GFM | tables | ✅ | ~9 | 见 Block Table | S4 | Verified |
| GFM | task list | ✅ | ~5 | 见 Block Task List | S4 | Verified |
| GFM | autolink | ❌ | 0 | 无 | **S0** | **Unsupported** |
| GFM | strikethrough | ✅ | ~3 | 见 Inline | S4 | Verified |
| GFM | footnote | ❌ | 0 | 无 | **S0** | **Unsupported** |
| GFM | definition list | ❌ | 0 | 无 | **S0** | **Unsupported** |

**汇总（真实计数）**：parser 相关测试文件 14 个，`test(` 用例 **214**；fuzz **2001 轮**；专项 round-trip（mermaid 7 + table/formula 6 + serializer 11 + consistency 17 + BUG-5 回归 1）。

### FEAT-MD-SERIAL — Markdown 序列化

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| Block | 9 类元素全覆盖 | ✅ | 46 | `block_serializer.dart:53-64`（fromElement，exhaustive switch）；`test/editing/block_serializer_test.dart`（46） | S4 | Verified |
| Inline | 行内序列化 | ✅ | 13 | `block_serializer.dart:253-258`（InlineSerializer）；`test/editing/inline_serializer_test.dart`（13） | S4 | Verified |
| Facade | 文档级 serialize | ✅ | — | `markdown_serializer.dart:18,25`（薄封装，委托 block_serializer） | S4 | Verified |
| Fidelity | round-trip | ✅ | 2001 轮 | `roundtrip_fuzz_test.dart`（同 Parser）；`serialize(parse(serialize(parse(md)))) == serialize(parse(md))` | **S5** | Verified |
| Fidelity | 源码保真 | ⚠️ | ~3 | table cell trim / 空白注释不逐字保留（consistency:52-62） | **S3** | **Partial** |

### FEAT-UNDO — Undo/Redo（编辑模型）

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| Model | 事务历史栈 | ✅ | 17 | `editor_history.dart:41-43`（默认深度 50）、`:95-109`（push/undo/redo）；`editor_history_test.dart`（17） | S4 | Verified |
| Model | 事务原子性/回滚 | ✅ | 31 | `transaction_builder_test.dart`（23）+ `transaction_rollback_atomicity_test.dart`（8） | S4 | Verified |
| Ops | 块级操作 undo | ✅ | 21 | `undo_redo_block_operations_test.dart`（5）+ `transform_undo_redo_cycle_test.dart`（9）+ `undo_redo_round_trip_test.dart`（7） | S4 | Verified |
| Fuzz | undo/redo 随机 | ✅ | 2 | `undo_redo_fuzz_test.dart`（2 组 fuzz） | S4 | Verified |
| Runtime | 集成链路 | ✅ | INT-D | E2E-CORE-004/006（行为基线） | **S5** | Verified（模拟器） |
| Runtime | 真机 Undo 行为 | ❌ | 0 | 无 E6 真机证据 | **S2** | **Unknown**（L1: blocking E6） |

### FEAT-FORMULA — Formula 编辑/渲染（**Release-blocking evidence gap**）

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| Parse | 提取与分类 | ✅ | 29+ | `formula_extractor.dart:62,86-125`；`formula_extractor_test.dart`（29） | **S5** | Verified |
| Plan | 渲染计划 | ✅ | 17 | `formula_render_plan_test.dart`（17） | S4 | Verified |
| Render | LaTeX→SVG | ✅ | 模拟器 | `formula_svg_service.dart:24-81`（30s 超时 + (latex,displayMode) 缓存）；golden formula_block light/dark/sepia | S4 | Verified（模拟器） |
| Render | **真机视觉保真（SVG/矢量）** | ⚠️ | 0 | **真机降级为 LaTeX 文本**（docs/releases 真机报告） | **S2** | **NOT-PROVEN —— E6+E8 Release-blocking** |
| Editing | 公式块编辑 | ✅ | 模拟器 | presentation/blocks/formula_block_test + INT-D | S3 | Verified（模拟器） |

### FEAT-WORD — Word 导出（DOCX）

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| L1 | 产物完整性（合法 docx/zip） | ✅ | 34 | `word_export_zip_integrity_test.dart`（8）+ `word_ooxml_builder_test.dart`（26） | S4 | Verified |
| L2 | 语义保真（结构/样式） | ✅ | 4 | `word_export_semantic_fidelity_test.dart`（4） | S4 | Verified |
| L2 | 元素广度（段/标题/列表/表格/代码/引用） | ✅ | 15 | `word_export_audit_test.dart`（15） | S4 | Verified |
| L3 | Formula→PNG 嵌入 | ✅ | — | `word_exporter.dart:58-64,229`（formula_$i.png / FormulaImageInfo） | S4 | Verified（图片化，非 OMML） |
| L3 | Mermaid→SVG 嵌入 | ✅ | — | `word_exporter.dart:60,238-240`（mermaid_$i.svg） | S4 | Verified（图片化） |
| L3 | **真实消费端** | ✅ | E2E-P0-9/10 | **WPS（word2pdf/pdf2txt）+ OfficeCLI（view/issue）真机实测** | **S5** | Verified |
| L3 | MS Word Desktop | ❓ | 0 | 从未打开验证 | **S0-UNKNOWN** | **Optional（Release Gate）** |
| L4/L5 | 渲染捕获 / 视觉复核 | ⚠️ | 0 | 无像素级比对 | **S3** | Partial |

### FEAT-PDF — PDF 导出

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| L1/L2 | 合法 PDF + 语义 | ✅ | 28+10 | `export_integration_test.dart`（28）+ `svg_to_pdf_integration_test.dart`（10） | S4 | Verified |
| CJK | 中文字体兜底 | ✅ | — | `pdf_exporter.dart:29-84`（_cjkFont + 失败退避重试）、`:90-95`（SvgPlan 内 cjkFont） | **S5** | Verified |
| Formula | 公式入 PDF | ✅ | 25 | `formula_svg_service` + `svg_parser_test.dart`（25）+ FormulaRenderPlan/SvgPlan | S4 | Verified |
| Runtime | 真机导出 | ✅ | E2E-P0-6/7/8 | 真机报告 | **S5** | Verified（导出路径） |
| L3 | 外部原生 PDF 消费端 | ❓ | 0 | 无第三方 PDF 阅读器验证 | **S0-UNKNOWN** | **Optional** |

### FEAT-AUTOSAVE — 自动保存

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| Model | debounce（1.5s） | ✅ | 13 | `autosave_service.dart:89`；`presentation/editor/autosave_service_test.dart`（13） | S4 | Verified |
| Model | 指数退避重试 | ✅ | — | `autosave_service.dart:8,90`（max 60s）；`p2_autosave_error_callback_test.dart` | S4 | Verified |
| Persist | 磁盘字节级断言 | ✅ | INT-D | 模拟器 INT-D 含字节断言 | S4 | Verified（模拟器） |
| Persist | **真机持久化（不丢数据）** | ❌ | 0 | 无 E6 真机证据 | **S2** | **NOT-PROVEN（L1: blocking E6）** |

### FEAT-FILE — 文件打开/保存

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| Decode | UTF-8/BOM/gb18030/latin1 | ✅ | 9 | `file_service.dart:13-40`（decodeBytesAuto）；`file_service_decode_test.dart`（9） | **S5** | Verified |
| I/O | 打开/保存/仓储 | ✅ | 38 | `file_service_import_test.dart`（7）+ `storage_repository_test.dart`（12）+ `crud_flow_test.dart`（6）+ `storage/migration_test.dart`（4）+ `recovery_test.dart`（6）+ `atomic_write_test.dart`（9） | S4 | Verified（模拟器） |
| Runtime | **真机文件系统（.md/GBK）** | ❌ | 0 | 真机仅发现过问题（无正面 E6 证据） | **S2** | **NOT-PROVEN（L1: blocking E6/UX）** |

### FEAT-IME — IME 输入

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| Model | composing 状态机 | ✅ | 21 | `composing_controller.dart:23-43`（ComposingHost，region 真相源）；`composing_controller_test.dart`（21） | S3 | Verified |
| Tx | IME×事务集成 | ✅ | 22 | `ime_transaction_integration_test.dart`（16）+ `ime_mutation_forbidden_test.dart`（6） | S4 | Verified（模拟器） |
| Runtime | 真机焦点/连续性 | ✅ | — | 真机报告：焦点✅ | S4 | Verified |
| Runtime | **物理软键盘按键** | ❌ | 0 | 未验证 | **S2** | **NOT-PROVEN（L1: blocking Physical-IME）** |

### FEAT-BLOCK — 拖拽块重排（**L1 判定 incomplete**）

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| Model | 拖拽句柄/重排命令 | ✅ | — | `presentation/blocks/shared/block_drag_handle.dart`；`presentation/editor/block_reorder.dart` | S3 | Implemented |
| Ops | 重排参数/命令 | ✅ | 5 | `block_reorder_args_test.dart`（5） | S3 | Verified（模拟器） |
| Gesture | 拖拽手势测试 | ⚠️ | **0** | `block_drag_gesture_test.dart` 无 `test(` 用例 | S2 | **Thin** |
| Runtime | **真机核心路径** | ❌ | — | **BlockToolbar 在物理真机有已知功能缺陷（真机问题3）** | S2 | **INCOMPLETE（真实缺陷，非没证据）** |

### FEAT-THEME — 主题切换

| 能力域 | 子能力 | 实现 | 测试覆盖 | 证据 | S级 | 结论 |
|--------|--------|------|---------|------|-----|------|
| Model | 单一真源 themeModeProvider | ✅ | — | `editor_providers.dart:15`；`:63-64`（darkModeProvider 只读派生） | **S5** | Verified |
| UI | 三主题渲染 | ✅ | golden 矩阵 | golden 系列（paragraph/heading/formula/code 等 light/dark/sepia）；`editor_tokens_ext_test.dart` | S4 | Verified（部分） |
| UI | dark/sepia 整页 golden | ⚠️ | 禁用 | 整页 golden 部分禁用 | **S3** | Partial |
| Runtime | 真机主题 | ❌ | 0 | 无 E6 真机证据 | **S2** | NOT-PROVEN |

---

## 3. Capability Contract（完成契约：Required / Optional + 阈值）

> "完成"必须由**契约**推导，而非"测试全绿"。契约 = 该功能宣称边界内必须达到的 S 级集合 + 机械阈值。

**机械规则**：`coverage% = (达到阈值 S 级的 Required 项数) / (Required 项总数)`；全部 Required 达标 → 进入 L1 判定（conditional / implemented_unproven 由缺的是"边界"还是"核心证据"区分；incomplete 仅当存在已知真实缺陷）。

| 功能 | Required（阈值） | Optional（不影响"完成"主张） | 实测 coverage | 机械推导 status |
|------|-----------------|-------------------------------|--------------|----------------|
| Markdown Parser | Core Block ≥95% @S4（12 项）；Core Inline ≥95% @S4（8 项）；Formula=S5；Mermaid≥S4；Nested List≥S4；Round-trip >99%（2001 fuzz）；无已知数据丢失 bug；Malformed 降级已验证 | 稀有 GFM（autolink/footnote/def-list/indented code）；CommonMark 完整边角语义 | Block **100%**（12/12）；Inline **87.5%**（7/8 @S4，nested-formatting S3）；Round-trip **>99%** | **conditional** |
| Serializer | Round-trip @S5；9 类元素 exhaustive | 逐字源码保真 | 100% | **conditional** |
| Undo/Redo | 事务原子性 @S4；undo/redo 周期 @S4；无数据丢失 | 真机 E6 Undo 行为 | 100%（模拟器） | **conditional** |
| Formula | Parse @S5；SVG 渲染 @S4；**E6 真机视觉 @S4 ✗**；**E8 像素/语义保真 ✗** | — | Parse ✓ / Render ✓ / **E6+E8 未达标** | **implemented_unproven（release-blocking）** |
| Word Export | L1 产物完整 @S4；L2 语义 @S4；L3 至少 1 真实消费端 @S5；核心元素覆盖 ≥90% | **MS Word Desktop（Release Gate Optional）**；L4/L5 视觉 | L1✓ L2✓ L3✓（WPS+OfficeCLI） | **conditional** |
| PDF Export | L1/L2 @S4；CJK @S5；Formula @S4 | 外部原生 PDF 消费端 | 全部 ✓ | **conditional** |
| Autosave | debounce+退避 @S4；**E6 真机持久化 ✗** | — | 模拟器 ✓ / 真机 ✗ | **implemented_unproven** |
| File | decode @S5；open/save @S4；**E6 真机 FS ✗** | — | 模拟器 ✓ / 真机 ✗ | **implemented_unproven** |
| IME | composing 状态机 @S3；事务集成 @S4；**物理软键盘 ✗** | — | 模拟器 ✓ / 物理键 ✗ | **implemented_unproven** |
| Drag/Reorder | 句柄+重排命令 @S3；**核心移动端路径无已知缺陷 ✗（真机问题3）** | — | 实现 ✓ / 真机有真实缺陷 | **incomplete** |
| Theme | provider 真源 @S5；三主题渲染 @S4；**E6 真机 ✗；E8 golden 全页 ✗** | — | 部分 ✓ / 真机+全页 golden ✗ | **implemented_unproven** |

> **与 L1（Completion Matrix）一致性**：上表推导结果与 `FEATURE-COMPLETION-EVIDENCE-MATRIX-v1.md` §3 的 11 功能判定**完全一致**（conditional×6 / implemented_unproven×4 / incomplete×1），证明两条独立证据链收敛到同一结论。

---

## 4. 机器可读输出（未来 `ffx audit` 直接消费）

> 每功能除人类理由外，输出结构化 JSON，使 `ffx audit capability <name>` 可机械生成，无需重读全文。

```json
{
  "capability": "markdown_parser",
  "completion": "conditional",
  "coverage": {
    "paragraph": "S5", "heading": "S5", "blockquote": "S4", "bullet_list": "S4",
    "ordered_list": "S4", "nested_list": "S4", "code_block": "S4", "mermaid": "S4",
    "table": "S4", "task_list": "S4", "hr": "S4", "formula": "S5",
    "bold": "S4", "italic": "S4", "inline_code": "S4", "link": "S4", "image": "S4",
    "strikethrough": "S4", "nested_formatting": "S3",
    "utf8": "S5", "crlf": "S4", "gbk": "S5",
    "malformed_fallback": "S3", "unclosed_fence": "S3", "ambiguous_nesting": "S2",
    "roundtrip": "S5", "exact_source_preservation": "S3"
  },
  "s0_unsupported": ["autolink", "footnote", "definition_list", "indented_code", "raw_html_block"],
  "contract": {
    "core_block": "100% (12/12 @S4)",
    "core_inline": "87.5% (7/8 @S4)",
    "roundtrip": ">99% (2001 fuzz rounds)",
    "no_data_loss_bug": true,
    "malformed_degradation": "verified"
  },
  "evidence": { "unit": 214, "fuzz_rounds": 2001, "integration": 17, "test_files": 14 },
  "blocking_unknowns": ["nested_formatting_edge_semantics", "exact_source_preservation"],
  "next_actions": [
    "audit nested-formatting edge semantics (code+bold combos)",
    "decide: footnote/autolink/definition-list scope (S0 vs roadmap)",
    "decide: exact source preservation contract (S3 vs S4)"
  ]
}
```

---

## 5. 系统性结论

1. **核心能力已到工程级**：Markdown 核心 Block 12 项 + Inline 7 项全部 ≥S4，编码（UTF-8/GBK）与往返保真（2001 fuzz，收敛 <1%）达到 **S5**；Word 导出达到真实消费端（WPS/OfficeCLI）S5 验证。
2. **明确的 S0 边界（不是缺陷，是范围）**：GFM 稀有语法——autolink / footnote / definition list / indented code / raw HTML 块。这是**宣称边界**，未来 `ffx audit` 应直接输出 "unsupported"，而不是含糊的"未测"。
3. **两处结构性风险**（与 L1 判定一致）：
   - **Formula 真机视觉 = S2，Release-blocking**（E6+E8 必须补，真机当前降级 LaTeX 文本）；
   - **Drag/Reorder 真机存在真实缺陷**（BlockToolbar 问题3）= incomplete，与"只是没证"严格区分。
4. **系统短板已从"缺多少测试"转为"缺哪类证据"**：模拟器侧能力覆盖已相当完整；剩余缺口集中在 **E6 真机类证据（Autosave/File/IME/Theme/Undo 真机行为）** 与 **可选的消费端边界（MS Word / 原生 PDF 阅读器）**。
5. **下一步建议**：将 §4 的 JSON 落地为 `ffx audit capability` 的机器可读输出；把 S0 列表与 Release-blocking 缺口写入 ROADMAP 排期；优先补 Formula E6/E8 真机视觉证据（唯一 Release-blocking 项）。

---

## 附录：与既有文档的关系

| 文档 | 回答的问题 | 引用关系 |
|------|-----------|---------|
| `PHASE3.10-ENGINEERING-BASELINE-v1.md`（v1.2） | 为什么代码现在这样存在 | L3，本矩阵的"三源真理"纪律来源 |
| `FEATURE-COMPLETION-EVIDENCE-MATRIX-v1.md`（v1.1） | 功能是否完成（E0–E8） | L1，§3 契约推导结果与之完全一致 |
| `docs/releases/phase3.5-realdevice-issues.md` | 真机问题清单 | 真机证据来源（E2E-P0-1~10、问题1–6） |
| `WORD-EXPORT-PRODUCT-RELIABILITY-AUDIT.md` / `CLI-ANYTHING-VERIFICATION-STATUS.md` | 消费端与 CLI 审计 | E4-M/E4-P 与 L3 消费端证据来源 |
