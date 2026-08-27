# Feature Completion Evidence Matrix — FormulaFix

> **文档性质**：功能完成证据矩阵（Feature Completion Evidence System，只读复盘，零代码改动）  
> **日期**：2026-08-19  
> **版本**：v1.1（v1.0 首版建立三层矩阵；**v1.1 治理收敛**：将"E4/E6 是否为必需"改为每功能属性、拆分 E4-M/E4-P、完成判定结构化（status+原因码）、新增 Evidence Gap Type 列与 Required Evidence Profile 列、INT-A/B/C/D 明确为架构建议并补 INT-B 计划、Word 契约升级 L1-L5、Formula 定为 Release-blocking gap）  
> **作者**：AI Agent 起草，Human Owner 评审决策  
> **本 Phase 目标**：回答一个比"跑了多少测试"更核心的问题——
>
> > **FormulaFix 的每一个产品功能，到底经过了哪些层次的验证？这些证据是否足以宣称"这个功能已经完成"？**
>
> **与 Engineering Baseline 的关系（两者并列，同为 Phase 3.10 产物）**：
>
> - `PHASE3.10-ENGINEERING-BASELINE-v1.md` 回答 **"代码为什么现在应该这样存在"**（历史债务 / 历史决策）。
> - 本文档回答 **"我们有没有充分理由宣称这个功能完成了"**（功能 × 证据层级）。
> - 前者是 **Historical Decision → Engineering Baseline**；本文档是 **Feature Contract → Evidence Matrix → Completion**。
>
> **验证纪律（三源真理模型，与基线 v1.2 一致）**：结论以 Implementation Truth（`file:line` + 真实测试运行）与 Evidence Truth（真机/消费端实测）为准；审计文档仅作线索。凡文档与代码/实测冲突，以代码与实测为准。

---

## 0. 证据等级定义（E0–E8）

每一格证据都标注其达到的层级。层级越高，证明力越强；但**层级高 ≠ 完成**——完成判定取决于"是否达到该功能的 **Required Evidence Profile（最小充分证据集合）**"，而非统一门槛。

| 等级 | 名称                  | 含义                                                  |
| -- | ------------------- | --------------------------------------------------- |
| E0 | Code Exists         | 代码存在                                                |
| E1 | Code Review         | 代码审查 / 架构守门                                         |
| E2 | Unit Test           | 单元测试（纯逻辑 / 窄边界）                                     |
| E3 | Integration Test    | 集成测试（模块/业务链/Runtime/E2E）                            |
| E4 | CLI / Artifact      | CLI-Anything(FFX) 验证 —— **分两子类**（见下注）                  |
| E5 | Simulator Runtime   | 模拟器 / Flutter 运行时                                   |
| E6 | Real Device         | 物理真机（物理 IME / GPU / 存储 / OEM 行为）                    |
| E7 | Consumer            | 消费端工具（WPS / OfficeCLI / pdfinfo / Word Desktop）打开验证 |
| E8 | UX / Golden / Human | Golden 测试 / UI 截图 / 人工 UX 验收                        |

> **E4 子类（v1.1 关键拆分）**：CLI 列必须区分 **E4-M（Model / Artifact CLI）** 与 **E4-P（Production-path CLI）**：
> - **E4-M** = CLI 操作 JSON / 模型 / 工件（如 `ffx project export` 写 `content` 字符串、`ffx analyze` 正则统计）——**不证明产品能力**。
> - **E4-P** = CLI 真正调用生产代码路径（如 `ffx adi` 委托 `adi.dart` 诊断脚本）——**才证明产品路径被使用**。
> 本仓库绝大多数 FFX 命令为 **E4-M**；纯 JSON/model harness **不等价于** 产品完成。这正是你此前总结的：**CLI 能解析 ≠ 产品能力真正完成**。

### 集成测试细分（INT-A/B/C/D）—— 架构建议，非现状

"集成测试"不是单点 ✅。本矩阵将集成测试明确拆为四档，避免"Integration ✅"误导：

| 档         | 含义                                       | 证明力      | 现状 |
| --------- | ---------------------------------------- | -------- | ---- |
| **INT-A** | 模块集成：2+ 内部模块接线，无完整 App                   | 低（仍偏单元侧） | 几乎无 |
| **INT-B** | 业务链集成：功能 → AST → 编辑器状态 → 序列化 → 落盘（纵向切片）  | 中        | 几乎无（经 INT-D 间接覆盖） |
| **INT-C** | Runtime 集成：在 Flutter widget 树内运行，但非完整用户流 | 中高       | 仅主题切换 |
| **INT-D** | 端到端：完整 App 启动 + 用户流模拟                    | 高        | 主流 |

> **v1 实证发现（重要）**：本仓库**几乎没有独立的 INT-A / INT-B / INT-C 专用套件**。绝大多数"集成"直接以 INT-D（E2E）落地；业务链（Parser→AST→State→Serializer→Save）的覆盖是通过 INT-D 持久化往返测试实现的（如 `phase35_persistence_roundtrip_test.dart`），而非独立 INT-B 套件。
>
> **v1.1 定位澄清**：INT-A/B/C/D 是**架构建议（target shape）**，不是当前覆盖事实。当前系统典型问题是 `单元测试 → 直接跳到完整 E2E`，中间缺少窄纵向集成。因此**建议补 INT-B Business Slice 专套**——但**不要为"分类好看"批量制造 100 个集成测试**，只针对**最易跨层出 bug 的链路**：
>
> | ID | Business Slice（纵向切片） | 覆盖的跨层风险 |
> | -- | ------------------------ | ------------ |
> | **INT-B-001** | Markdown → AST → Serialize | 解析/序列化不对称、round-trip 静默丢内容 |
> | **INT-B-002** | Input → LiveState → Transaction → History | IME/Live 状态桥 → 事务 → Undo 链断裂 |
> | **INT-B-003** | Formula → RenderPlan → SVG | 渲染计划 → 实际 SVG 保真漂移 |
> | **INT-B-004** | Document → Word IR → OOXML | AST → Word 中间表示 → 文档保真丢失 |
> | **INT-B-005** | Document → PDF Render Plan → PDF | AST → PDF 计划 → 字节/CJK/公式缺失 |
>
> 这些专套价值高、成本低，应优先于泛化 INT-A/C。

### Required Evidence Profile（每功能最小充分证据集合，v1.1 新增）

**核心原则**：E4 / E6 不是所有功能的统一必需项。每个功能有自己的最小充分证据集合——纯核心库不需要 CLI 证明完成，Undo 不需要消费端，导出功能必须真机+消费端。这把规则从"所有功能都应该有 E4/E6"变成"**每个功能都有自己的最小充分证据集合**"。

| 功能 | Required Evidence Profile | 说明 |
|------|--------------------------|------|
| Markdown 解析 | **E1 + E2 + E3** | 纯核心库，无需 E4/E6/E7 |
| Markdown 序列化 | **E1 + E2 + E3** | 纯核心库，无需 E4/E6/E7 |
| Undo/Redo | **E1 + E2 + E3 + E5 + 关键 E6** | 核心证明=Command→Tx→History→Runtime E2E；真机为关键但非每 PR 必达 |
| Formula 编辑/渲染 | **E1 + E2 + E3 + E5 + E6 + E8**（**Release-blocking**） | 差异化主轴；E6 真机视觉 + E8 golden 为发布硬门槛 |
| Word 导出 | **E1 + E2 + E3 + E5 + E6 + E7** | 导出必须有真机 + 真实消费端 |
| PDF 导出 | **E1 + E2 + E3 + E5 + E6 + E7** | 同 Word |
| 自动保存 | **E1 + E2 + E3 + E5 + E6** | "真机不丢数据"核心契约在 E6 |
| 文件打开/保存 | **E1 + E2 + E3 + E5 + E6** | 物理存储/GBK 在 E6 |
| IME 输入 | **E1 + E2 + E3 + E5 + E6 + E8** | 物理键盘在 E6，UX 在 E8 |
| 拖拽块重排 | **E1 + E2 + E3 + E5 + E6 + E8** | 移动端工具栏/手势在 E6/E8 |
| 主题切换 | **E1 + E2 + E3 + E5 + E6 + E8** | 真机渲染/对比度在 E6/E8 |

---

## 1. 第一层 — Feature Matrix（功能 × 证据层级概览）

> 符号：✅ 已验证（证据充分） · ⚠️ 部分/有条件（边界未覆盖） · ❌ 缺失/未验证（关键证据缺失） · — 不适用 · ⏳ 待验证  
> CLI 列记为 `E4-M✅/E4-P❌` 形式（见 §0 子类定义）。

| 功能 | 代码 | 单元 | 集成(INT) | CLI(FFX) | 模拟器 | 真机 | 消费端 | UX | Req.Profile | 完成判定 | Gap Type |
|------|------|------|----------|----------|--------|------|--------|-----|-------------|----------|----------|
| Markdown 解析 | ✅ | ✅50+ | INT-D×2 | E4-M✅/E4-P❌ | ✅ | — | — | ❌ | E1+E2+E3 | **CONDITIONAL** | E4-P / UX(N/A) |
| Markdown 序列化 | ✅ | ✅fuzz1k | INT-D×3 | E4-M✅/E4-P❌ | ✅ | — | — | ❌ | E1+E2+E3 | **CONDITIONAL** | E4-P / UX |
| Undo/Redo | ✅ | ✅×7 | INT-D×3 | E4-M✅/E4-P❌ | ✅ | ❌ | — | ❌ | E1+E2+E3+E5+关键E6 | **CONDITIONAL** | E6 / UX |
| Formula 编辑/渲染 | ✅ | ✅×5 | INT-D×2 | E4-M✅/E4-P❌ | ✅ | ⚠️崩溃级 | — | ⚠️golden模拟器 | E1+E2+E3+E5+**E6+E8**(RB) | **IMPLEMENTED-UNPROVEN** | **E6 / E8 (release-blocking)** |
| Word 导出 | ✅ | ✅×26+ | INT-D×3 | E4-M✅/E4-P❌ | ✅ | ✅E2E-P0-9/10 | ✅WPS+OfficeCLI | ❌ | E1+E2+E3+E5+E6+E7 | **CONDITIONAL** | MS Word(optional) |
| PDF 导出 | ✅ | ✅×28 | INT-D×3 | E4-M❌/E4-P❌ | ✅ | ✅E2E-P0-6/7/8 | ❌ | ❌ | E1+E2+E3+E5+E6+E7 | **CONDITIONAL** | Consumer / Visual |
| 自动保存 | ✅ | ✅×2 | INT-D×3 | E4-M✅/E4-P❌ | ✅ | ❌ | — | ❌ | E1+E2+E3+E5+E6 | **IMPLEMENTED-UNPROVEN** | E6 |
| 文件打开/保存 | ✅ | ✅×8 | INT-D×多 | E4-M✅/E4-P❌ | ✅ | ❌仅发现问题 | — | ❌golden禁用 | E1+E2+E3+E5+E6 | **IMPLEMENTED-UNPROVEN** | E6 / UX |
| IME 输入 | ✅ | ✅×5 | INT-D×1 | E4-M❌/E4-P❌ | ✅ | ⚠️焦点✅物理键❌ | — | ❌ | E1+E2+E3+E5+E6+E8 | **IMPLEMENTED-UNPROVEN** | Physical IME |
| 拖拽块重排 | ✅ | ✅×4 | INT-D×1 | E4-M❌/E4-P❌ | ✅ | ⚠️工具栏缺陷 | — | ❌ | E1+E2+E3+E5+E6+E8 | **INCOMPLETE** | Real-device defect |
| 主题切换 | ✅ | ✅×8+golden | INT-C×3 | E4-M❌/E4-P❌ | ✅ | ❌ | — | ⚠️golden部分禁用 | E1+E2+E3+E5+E6+E8 | **IMPLEMENTED-UNPROVEN** | E6 / E8 |

> **v1.1 总判定**：11 个功能中 **0 个达到 COMPLETE**。差距**不是"统一缺 E4/E6"**，而是**各功能的 Required Evidence Profile 中特定层级未达标**——纯库（Parser/Serializer）本就不需要 E4/E6；导出类缺 E7 消费端；Undo/Autosave/File/IME/Theme 缺 E6 真机；Formula 缺 E6+E8（且为 release-blocking）。无关 E6 的功能（Parser/Serializer）仅是 UX/Golden 待补，不影响"完成"主张。

### 1.1 Evidence Gap 汇总（供 `ffx audit gaps` 机械消费）

```text
BLOCKING（阻断发布）:
  Formula         E6 / E8        # 差异化主轴，真机视觉+golden 缺失 = 发布硬门槛
  Drag/Drop       real-device product defect  # 真机工具栏已知功能缺陷

EVIDENCE GAPS（已知缺口，排期补）:
  Undo            E6
  Autosave        E6
  File            E6 / UX(golden禁用)
  IME             Physical IME keyboard
  Theme           E6 / E8
  PDF             Consumer / Visual（无外部消费端验证原生 PDF）
  Markdown Parse  E4-P / UX（纯库 N/A，仅影响"CLI 可证"主张）
  Markdown Serial E4-P / UX

OPTIONAL（可选，非日常工程硬门槛）:
  Word Desktop    MS Word 兼容性 UNKNOWN —— Release Gate Optional，不阻塞日常循环
```

---

## 2. 第二层 — Evidence Detail（逐功能证据明细）

> 每功能按 Code / Unit / Integration / CLI / Simulator / Real Device / Consumer / UX / Unknown 展开，全部 file:line 或 doc:section 实证。CLI 段显式标注 **E4-M / E4-P**。

### FEAT-MD-PARSE — Markdown 解析
- **Code**：`lib/core/parser/markdown_parser.dart:59` `class MarkdownParser`；`lib/core/parser/formula_extractor.dart:15` `FormulaExtractor`。
- **Unit**：`test/markdown_parser_test.dart`、`inline_parser_test.dart`、`parser/edge_case_test.dart`、`parser/roundtrip_fuzz_test.dart`、`parser/mermaid_audit_test.dart`、`parser/table_formula_audit_test.dart`（约 50+ 用例；BUG-1~6 已修并 fuzz 锁死）。
- **Integration**：INT-D ×2 — `integration_test/e2e/core/e2e_core_005_format_roundtrip_test.dart:22`、`e2e_core_002_paragraph_split_test.dart:3`。
- **CLI**：`ffx analyze file` / `ffx project export` → `tools/ffx-cli/cli_anything/ffx/project.py:262` `_analyze_content` 用正则统计，**未调用**真实 `MarkdownParser`。**E4-M ✅（操作 JSON/正则）/ E4-P ❌（未走真实解析路径）**。
- **Simulator**：✅（上述 unit/integration 在 Flutter 运行时）。
- **Real Device**：—（纯逻辑，物理真机不适用；未做真机验证）。
- **Consumer**：—（非导出）。
- **UX/Golden**：❌ 无 golden / 无 UI 截图。
- **Unknown**：E4-P 真实路径未验证；UX 视觉未验收（对纯库功能为 N/A，不影响完成主张）。

### FEAT-MD-SERIAL — Markdown 序列化
- **Code**：`lib/core/parser/markdown_serializer.dart:18` `class MarkdownSerializer`；`block_serializer.dart`。
- **Unit**：`test/parser/markdown_serializer_test.dart`、`editing/inline_serializer_test.dart`、`parser/roundtrip_fuzz_test.dart`（1000 轮 + multi-seed 5×200，收敛 <1% 违规）、`editing/block_serializer_test.dart`。
- **Integration**：INT-D ×3 — `e2e_core_005`、`phase35_persistence_roundtrip_test.dart:21`、`e2e_core_001_persistence_test.dart:24`（Parser↔Serializer 对称 + 落盘往返）。
- **CLI**：`ffx project export`（project.py:202-212）仅 `f.write(content)` 写原始串，**未调用** `MarkdownSerializer`、不构造 `DocumentElement`。**E4-M ✅ / E4-P ❌**。
- **Real Device / Consumer / UX**：同 FEAT-MD-PARSE（— / — / ❌）。

### FEAT-UNDO — Undo/Redo
- **Code**：`lib/core/editing/editor_history.dart:43` `EditorHistory`；`lib/core/utils/history_manager.dart:12`；`editor_coordinator.dart:29`。
- **Unit**：`test/editing/editor_history_test.dart`、`undo_redo_block_operations_test.dart`、`undo_redo_fuzz_test.dart`、`undo_redo_round_trip_test.dart`、`transform_undo_redo_cycle_test.dart`、`transaction_rollback_atomicity_test.dart`（×7）。
- **Integration**：INT-D ×3 — `integration_test/phase33_undo_redo_test.dart:33`、`e2e_core_004_transaction_undo_test.dart:23`、`e2e_core_006_typing_coalescing_test.dart:22`（CORE-004 为行为基线）。
- **CLI**：`ffx project undo/redo/snapshot`（project.py:143-172）仅对 `_session["history"]` 中 `content` 字符串快照做 push/pop，**无 Transaction/AST**。**E4-M ✅ / E4-P ❌**。
- **Real Device**：❌（真机问题清单 1~6 未覆盖 undo/redo；无真机 E2E-P0 验证）。
- **UX**：❌ 无 golden / 真机人工验收。
- **Unknown**：E6 真机 Undo 行为未验证（Required Profile 标为"关键 E6"）。

### FEAT-FORMULA — Formula 编辑/渲染（**Release-blocking evidence gap**）
- **Code**：`lib/core/services/formula_svg_service.dart:24` `FormulaSvgService`；`lib/presentation/blocks/formula/formula_block.dart:16`；`lib/presentation/widgets/formula_renderer.dart`（降级）。
- **Unit**：`test/formula_extractor_test.dart`、`formula_render_plan_test.dart`、`svg_parser_test.dart`、`presentation/blocks/formula_block_test.dart`、`presentation/widgets/formula_renderer_fallback_test.dart`（×5）。
- **Integration**：INT-D ×2 — `integration_test/phase35_formula_test.dart:30`（WebView 挂载→SVG→重开命中）、`phase35_persistence_roundtrip_test.dart:21`。
- **CLI**：`ffx project inject formula`（project.py:72）仅字符串拼接 `$$\n latex \n$$`，**未调用** `FormulaSvgService`/真实渲染。**E4-M ✅ / E4-P ❌**。
- **Real Device**：⚠️ **仅崩溃级**——`releases/phase3.5-realdevice-issues.md` 问题4：真机（Xiaomi）PDF/Word 公式降级为原始 LaTeX 文本（Release WebView 可能未挂载）；E2E-P0-8「PDF 公式导出不崩溃」真机 Pass 但公式此时降级为文本。**视觉保真（SVG/矢量）在物理真机未经自动化验证**。
- **Consumer / UX**：— / ⚠️（`test/golden/formula_block_light/dark/sepia_test.dart` 存在，但真机视觉为人工验收待办）。
- **Release-blocking 说明**：Formula 是 FormulaFix 的**核心差异化能力**，其 Required Profile 含 **E6 + E8 且为发布硬门槛**。当前 E6（真机 WebView/GPU/字体/SVG 实际布局）与 E8（真机视觉 golden）均缺失——这与 Word Desktop 的"可选 UNKNOWN"**完全不同等级**：Word 缺的是可选消费端，Formula 缺的是产品核心主张本身。此项**不能因 test 全绿就宣布完成**。

### FEAT-WORD — Word 导出（DOCX）
- **Code**：`lib/domain/services/exporters/word_exporter.dart:24` `WordExporter`；`word_ooxml_builder.dart:45`。
- **Unit**：`test/word_export_audit_test.dart`（CAP-WORD-001~016）、`word_export_semantic_fidelity_test.dart`（023/024/025）、`word_export_zip_integrity_test.dart`（018/018b）、`word_ooxml_builder_test.dart`（×26）。
- **Integration**：INT-D ×3 — `integration_test/cap_word_017_export_test.dart:22`（emulator-5554，PK magic+落盘）、`phase35_export_e2e_test.dart:42`、`phase35_p0_export_test.dart:7`。
- **CLI**：`ffx analyze audit <docx>` → `docx_qa.py:30` `audit_docx` 解包校验**既有** .docx 工件（ZIP/OOXML/语义 + 可选 WPS/OfficeCLI 探测），**不生成** docx、未 import Dart `WordExporter`。**E4-M ✅（工件校验）/ E4-P ❌（非真实导出路径）**。
- **Real Device**：✅ `releases/phase3.5-realdevice-issues.md` §"P0 修复验证结果" **E2E-P0-9 / E2E-P0-10**：真机 Xiaomi 24117RK2CC 验证「Word PK 头 + >4KB」「含中文 >2KB」Pass。
- **Consumer**：✅ **已验证**——WPS 12.1（`wpscli word2pdf` → success，89KB，无 repair/corruption；`wpscli pdf2txt` 文本提取成功）；OfficeCLI iOfficeAI（`officecli view screenshot` → shot_1.png、`view issues` 结构化问题）。❌ **LibreOffice/soffice**：代码已实现（CAP-WORD-C）但本机未装 → NOT verified。❌ **Microsoft Word Desktop**：UNKNOWN（**Release Gate Optional，非日常工程硬门槛**）。
- **UX**：❌ 无 App 层 Word 专属 golden；消费端截图属消费侧视觉审阅。
- **Completion Contract（L1–L5 分层，v1.1 升级）**：
  - **L1 Artifact Integrity** — DOCX 字节有效（PK magic、合法 OOXML/ZIP、size>4KB）✅
  - **L2 Semantic Fidelity** — 标题/表格/公式/行内抽取与源文档一致 ✅（`word_export_semantic_fidelity_test`）
  - **L3 Real Consumer** — WPS `word2pdf` success + `pdf2txt` 文本提取成功 ✅
  - **L4 Render Capture** — OfficeCLI `view screenshot` 捕获渲染图 ✅
  - **L5 Visual Review** — 人工审阅截图（无 corruption/错位）✅（消费端侧）
  - **MS Word Desktop = Release Gate Optional**：UNKNOWN 但不阻塞日常工程循环。

### FEAT-PDF — PDF 导出
- **Code**：`lib/domain/services/exporters/pdf_exporter.dart:28` `PdfExporter`；`lib/core/renderers/svg_to_pdf.dart`。
- **Unit**：`test/svg_to_pdf_integration_test.dart`、`export_integration_test.dart`（×28）。
- **Integration**：INT-D ×3 — `phase35_export_e2e_test.dart:35`（`%PDF` 头字节 + 真实文件复核）、`phase35_p0_export_test.dart:7`、`phase34_export_progress_test.dart:4`。
- **CLI**：❌ **无 PDF 导出子命令**（`grep -iE "pdf" ffx_cli.py` 无结果）。**E4-M ❌ / E4-P ❌**。
- **Real Device**：✅ `releases/phase3.5-realdevice-issues.md` **E2E-P0-6/7/8** 真机 Xiaomi 验证「%PDF 头 + >15KB（CJK 嵌入）」「含 /FontFile2 或 /FontFile3」「PDF 公式导出不崩溃」Pass（日志 `CJK font loaded successfully`）。
- **Consumer**：❌ **无外部消费端工具验证原生 PDF**（`pdfinfo`/`pdf2txt` 仅用于 WPS 转出的 PDF，非 App 原生 PDF；Adobe/Acrobat、LibreOffice 打开均未验证）。
- **UX**：❌ 无 golden / 无消费端截图；真机「PDF 阅读器打开检查」属人工验收（发现问题4 乱码）。
- **Unknown**：无外部消费端验证原生 PDF；公式-in-PDF 保真依赖 WebView（真机降级）。

### FEAT-AUTOSAVE — 自动保存
- **Code**：`lib/presentation/editor/autosave_service.dart:68` `AutosaveService`（1.5s 防抖、并发串行、指数退避）；`dirty_state_source.dart`。
- **Unit**：`test/presentation/editor/autosave_service_test.dart`、`observability/p2_autosave_error_callback_test.dart`。
- **Integration**：INT-D ×3 — `phase34_autosave_disk_test.dart:17`（**直接读磁盘字节断言**含新文本不含旧文本）、`phase34_autosave_test.dart:16`、`phase34_persistence_test.dart:21`。
- **CLI**：`ffx project save`（project.py:132 `_atomic_write`）写 JSON，**无**防抖/失败退避/脏标记/真实 `AutosaveService`。**E4-M ✅ / E4-P ❌**。
- **Real Device**：❌（真机问题清单未涉及；persistence/autosave 归模拟器 integration 域，未做真机验证）。
- **UX**：❌ 无 golden / 真机人工验收。
- **Unknown**：E6 物理存储持久化未验证——"真机不丢数据"是 autosave 的核心契约（Required Profile 含 E6）。

### FEAT-FILE — 文件打开/保存
- **Code**：`lib/core/services/file_service.dart:43` `FileService`；`document_service.dart:12`；`file_repository.dart:37`；`editor_screen.dart:151` `_saveToFile`。
- **Unit**：`test/file_service_decode_test.dart`、`file_service_import_test.dart`、`storage/atomic_write_test.dart`、`storage/recovery_test.dart`、`storage_repository_test.dart`、`architecture/file_access_test.dart` 等（×8）。
- **Integration**：INT-D ×多 — `phase34_file_tree_open_test.dart:23`、`phase34_file_tree_test.dart:6`、`phase34_persistence_test.dart:21`、`e2e_core_001_persistence_test.dart:24`、`phase35_persistence_roundtrip_test.dart:21`。
- **CLI**：`ffx project create/save/export`（project.py:12/132/202）写 JSON / `.md` 字符串，**未调用** `FileService`/`DocumentRepository`/`Document` 模型。**E4-M ✅ / E4-P ❌**。
- **Real Device**：❌ **仅发现问题未验证通过**——`releases/phase3.5-realdevice-issues.md` 问题2（文件树打开返回失效）在真机 Xiaomi 发现，但 P1 未进 E2E-P0；`CLI-ANYTHING-VERIFICATION-STATUS.md` §3.1 明确「真机文件系统（.md 打开/保存/GBK）⏳ 仅单元测试覆盖 `decodeBytesAuto`，真机未验证」。
- **UX**：❌ `test/golden/file_manager_test.dart` 的 `matchesGoldenFile` **已被注释禁用**（潜伏 golden，回归盲区）。

### FEAT-IME — IME 输入
- **Code**：`lib/core/editing/composing_controller.dart:74` `ComposingController`（commit 不丢字/cancel 回滚）；`composing_state.dart`；`blocks/input/input_handler.dart:45`。
- **Unit**：`test/editing/composing_controller_test.dart`、`composing_state_test.dart`、`ime_mutation_forbidden_test.dart`、`integration/ime_transaction_integration_test.dart`、`observability/p0_ime_composing_event_test.dart`（×5，含 IME 组合态 99 项 Batch 2）。
- **Integration**：INT-D ×1 — `integration_test/cap_ime_composing_test.dart:24`（`TestTextInput.updateEditingValue` 注入 composing 范围，模拟拼音组合；**无法触发真实 Android 软键盘**）。
- **CLI**：❌ 无 IME 子命令。**E4-M ❌ / E4-P ❌**。
- **Real Device**：⚠️ **焦点/连续性维度已验证**——`releases/phase3.5-realdevice-issues.md` 问题1（新块进编辑态）、问题5（回车 IME 中断）为真机发现；E2E-P0-1~5 真机 Xiaomi 验证 focusOn/新块编辑态/回车连续性 Pass（日志 `[focusOn] created missing viewState`）。**但物理软键盘按键本身 ❌ NOT verified**（`CLI-ANYTHING-VERIFICATION-STATUS.md` §3.1：「真实 Android 软键盘 IME 按键，tester 无法模拟，需人工验收」）。
- **UX**：❌ 模拟器 composing 已测；真机软键盘输入留人工验收。
- **Unknown**：Physical IME keyboard（Required Profile 含 E6+E8 的关键缺口）。

### FEAT-BLOCK — 拖拽块重排（**INCOMPLETE：真实产品路径已知功能缺陷**）
- **Code**：`lib/presentation/blocks/shared/block_drag_handle.dart:15` `BlockDragHandle`（`ReorderableDragStartListener`）；`editor_coordinator.dart:29`（moveBlock）；`ReorderableListView` 在 EditorShell。
- **Unit**：`test/presentation/blocks/shared/block_drag_gesture_test.dart`、`editor/block_reorder_args_test.dart`、`blocks/shared/block_interaction_test.dart`、`editor/editor_coordinator_test.dart`（×4）。
- **Integration**：INT-D ×1 — `integration_test/phase35_block_interaction_test.dart:17`（长按 `BlockDragHandle` → `gesture.moveBy` → 断言块顺序变更）。
- **CLI**：❌ 无拖拽/重排子命令。**E4-M ❌ / E4-P ❌**。
- **Real Device**：⚠️ **发现问题，无通过验证**——`releases/phase3.5-realdevice-issues.md` 问题3：真机 Xiaomi「块右上角无作用菜单栏（BlockToolbar 上移/下移/删除）」，根因为桌面 hover 范式误植移动端、单块时全禁用。修复方向为移动端长按+多块才显示，但**无真机 E2E-P0 项验证 drag/reorder 通过**（P0 仅覆盖 focusOn 与导出 CJK）。
- **UX**：❌ 无 golden；真机人工验收发现问题3（工具栏遮挡）；手势拖拽仅模拟器 widget 层。
- **判定说明**：此处**不是"没测试"，而是"真实产品路径存在已知功能缺陷"**——这正是 `INCOMPLETE` 应使用的典型场景，与"IMPLEMENTED/NOT PROVEN（没证据）"必须区分，防止未来 Agent 把"功能真有问题"和"只是没证"混为一谈。

### FEAT-THEME — 主题切换
- **Code**：`lib/providers/editor_providers.dart:15` `themeModeProvider` / `:21` `ThemeModeNotifier`；`lib/presentation/theme/app_theme.dart:10` `enum AppThemeMode`；`main.dart:156` 注入。
- **Unit**：`test/architecture/phase34_theme_arch_test.dart`、`presentation/theme/editor_tokens_ext_test.dart`、`golden/formula_block_dark/sepia_test.dart`、`paragraph_dark/light_test.dart` 等（×8 + golden 矩阵）。
- **Integration**：INT-C ×3 — `phase34_theme_test.dart:33`（`_ThemeHarness` 最小镜像 main.dart 接线，非完整 EditorPage）、`phase34_theme_block_test.dart:4`、`phase33_theme_test.dart`。**本功能无 INT-D（无完整 App 用户流 E2E）。**
- **CLI**：❌ 无主题子命令。**E4-M ❌ / E4-P ❌**。
- **Real Device**：❌ 未专门验证；`releases/phase3.5-realdevice-issues.md` 问题6（代码块高亮主题不随 app 切换，dark/sepia 对比度）为真机相关发现，但主题切换本身无真机通过验证。
- **UX**：⚠️ Golden 矩阵存在（14 个 golden 文件），但 `UI_STATUS.md` §3 注明 **dark/sepia 整页无 golden 守护**（回归盲区），`home_screen` 整页无 golden。
- **Unknown**：E6 真机渲染/对比度 + E8 整页 golden 禁用。

---

## 3. 第三层 — Completion Decision（完成判定：判定 + 原因码）

> **四档语义（与结构化 `completion_status` 对齐）**：
> - **complete** — 达到该功能 Required Evidence Profile，无重大 Unknown。
> - **conditional** — 核心可靠，但存在明确未覆盖边界（如可选消费端）。
> - **implemented_unproven** — 代码完成、测试存在，但 Required Profile 中关键证据（真机/消费端/UX）缺失。
> - **incomplete** — 功能本身或核心路径仍存在已知缺陷（非"没证据"）。
>
> **Agent 消费约定**：每功能除人类理由外，给出机器可读的 `completion_status` + `blocking_unknowns` + `next_evidence`，使 `ffx audit` 可直接生成下一步动作，无需重读全文。

| 功能 | status | blocking_unknowns | next_evidence | 人类理由（Actual Evidence → Contract → Sufficient?） |
|------|--------|-------------------|---------------| ------------------------------------------------ |
| Markdown 解析 | conditional | [E4-P, UX] | [UX-golden] | Unit(50+)+fuzz+E2E(INT-D) 全绿，round-trip 契约达成；E4-P/UX 对纯库为 N/A，不影响完成主张。 |
| Markdown 序列化 | conditional | [E4-P, UX] | [UX-golden] | round-trip fuzz 1000 轮收敛 <1% 违规，INT-D 往返全绿；E4-P/UX 对纯库为 N/A。 |
| Undo/Redo | conditional | [E6, UX] | [E6-real-device] | Command→Tx→History 单测 ×7 + E2E-CORE-004/006 INT-D 全绿（行为基线）；缺 E6 真机 Undo 行为。 |
| Formula 编辑/渲染 | **implemented_unproven** | [**E6**, **E8**] | [E6, E8] | 模拟器单元+INT-D 全绿，但**物理真机视觉保真（SVG/矢量）未验证**（真机降级为 LaTeX 文本）。**E6+E8 为 Release-blocking**。 |
| Word 导出 | conditional | [MS-Word-Desktop] | [optional] | 单元 ×26 + INT-D + 真机 E2E-P0-9/10 + **消费端 WPS/OfficeCLI**；边界 MS Word Desktop = Release Gate Optional。 |
| PDF 导出 | conditional | [Consumer, Visual] | [E7-native-pdf] | 单元 ×28 + INT-D + 真机 E2E-P0-6/7/8；缺外部消费端验证原生 PDF。 |
| 自动保存 | implemented_unproven | [E6] | [E6-real-device] | 模拟器 INT-D 含磁盘字节断言 + 单元全绿；**物理真机持久化未验证**（"真机不丢数据"核心契约在 E6）。 |
| 文件打开/保存 | implemented_unproven | [E6, UX] | [E6-real-device, UX-golden] | 模拟器 INT-D + 单元 ×8 全绿；**物理真机文件系统（.md/GBK）未验证**，golden 被禁用。 |
| IME 输入 | implemented_unproven | [Physical-IME] | [E6-physical-keyboard] | 模拟器 composing INT-D + 单元 ×5；真机焦点/连续性通过，但**物理软键盘按键 NOT verified**。 |
| 拖拽块重排 | **incomplete** | [real-device-defect] | [fix+verify-real-device] | 模拟器可工作，但**核心移动端路径（BlockToolbar）在物理真机有已知功能缺陷（问题3）**。 |
| 主题切换 | implemented_unproven | [E6, E8] | [E6-real-device, E8-golden] | 模拟器 INT-C×3 + 单元 + golden 矩阵；dark/sepia 整页 golden 禁用，物理真机未验证。 |

**机器可读范例（Formula —— 未来 `ffx audit` 直接消费）**：

```json
{
  "feature": "FEAT-FORMULA",
  "status": "implemented_unproven",
  "blocking_unknowns": ["real_device_visual_fidelity", "real_device_golden"],
  "next_evidence": ["E6", "E8"],
  "release_blocking": true
}
```

---

## 4. 系统性结论（Feature Completion Evidence System）

```
                 FormulaFix
                     │
           ┌─────────┴─────────┐
           ↓                   ↓
      Feature Contract     Historical Decision
           ↓                   ↓
      Evidence Matrix      Engineering Baseline
     (本文档)              (PHASE3.10-BASELINE)
           ↓
   Code / Unit / Integration(INT-A/B/C/D)
       / CLI(E4-M/E4-P) / Simulator / Device / Consumer / UX
           ↓
        Completion Decision
```

1. **核心纪律**：`测试通过 ≠ 功能完成`。本报告用 Required Evidence Profile + 9 维证据 + 完成契约 + 四档判定（含原因码），把"完成"从主观感受变成可审计、可计算的链路。
2. **真正的系统性问题不是"测试不够"，而是"各功能的充分证据集合尚未标准化"**：v1.1 已为 11 个功能分别定义 **Required Evidence Profile**（纯库无需 E4/E6；导出必须有 E6+E7；Formula 必须有 E6+E8 且为 release-blocking）。差距是"特定层级未达标"，而非"统一缺 E4/E6"。**E4 必须拆 E4-M/E4-P**——FFX 全量操作 JSON/model，几乎无 E4-P，故 **CLI 绿 ≠ 产品验证**。
3. **集成测试结构问题**：INT-A/B/C 专用套件缺失，集成几乎等于 E2E。已规划 **INT-B Business Slice（INT-B-001~005）** 针对最易跨层出 bug 的链路，**不为分类好看批量造测试**。
4. **最强证据链**：Word 导出（模拟器+真机+WPS/OfficeCLI 消费端，L1–L5 全达成），MS Word Desktop 仍为 UNKNOWN 但属 **Release Gate Optional**，不阻塞日常循环。
5. **最危险缺口 = Release-blocking**：Formula 视觉保真（产品差异化主轴）在物理真机未验证（E6+E8 缺失），与 Word Desktop 的"可选 UNKNOWN"**等级完全不同**——前者阻断发布，后者可选。IME 物理键盘、Autosave/File 物理存储、Block 重排真机工具栏均属"实现但未证"或"真实缺陷"。
6. **下一步建议（非本文档范围）**：将本矩阵每功能的 `blocking_unknowns` 转为 roadmap 条目，按 Required Profile 补证；优先补 E6（真机）与 E4-P（FFX 真实路径）。使"完成判定"从 conditional/implemented_unproven 向 complete 收敛。
7. **终局愿景**：让 `ffx audit` 自动读取本矩阵 —— `Feature → Required Evidence Profile → Actual Evidence → Missing Evidence → Completion Status → Next Action`。"功能完成"将不再是某人主观判断，而成为**可计算、可审计、可被 Agent 消费的工程状态**。

---

*本文件为 FormulaFix Feature Completion Evidence Matrix v1.1。与 `PHASE3.10-ENGINEERING-BASELINE-v1.md` 并列，同为 Phase 3.10 核心产物。新功能经 Owner 评审后按 FEAT-xxx 追加证据明细，不覆盖历史判定。*
