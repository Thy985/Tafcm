# Phase 3.10 — Tafcm vs Typora 类产品差距分析

> **文档性质**：能力差距分析（Analysis-only，零代码改动）
> **日期**：2026-08-19
> **依据**：`flutter_app/lib` 真实代码逐条核对（25 项能力矩阵，file:line 实证），非审计文档推导
> **对比对象**：Typora（macOS/Windows/Linux 桌面端 WYSIWYG Markdown 编辑器）及同类（Obsidian 编辑态、MarkText、iA Writer）
> **配套文档**：`PHASE3.10-ENGINEERING-BASELINE-v1.md`（工程债基线）

---

## 0. 一句话结论

Tafcm 在**「数学富文本编辑器」这一差异化主轴**上已具备 Typora 级骨架（真 WYSIWYG、数学公式、Mermaid、表格、本地 .md 单一真相源、自动保存）；但在 **「写作流舒适性功能」**（打字机/焦点暗化/快捷键/选区气泡/图片拖放）与 **「格式与导出广度」**（自定义 CSS、源码视图、多导出格式、脚注交叉引用）上明显落后——属于**「专业数学编辑器雏形」而非「完整 Markdown 写作器」**。

> ⚠️ 定位差异：Typora 是**桌面端通用写作器**；Tafcm 是**移动端优先的数学写作器**。因此部分差距是**产品定位差异（合理）**，部分是**真实功能缺失（应补）**。本分析区分二者。

---

## 1. 能力矩阵（25 项，代码实证）

| # | 能力 | Typora | Tafcm | 代码证据 | 判定 |
|---|------|-------|-----------|---------|------|
| 1 | 真 WYSIWYG / 无编辑-预览切换 | ✓ | **PRESENT** | `live_editing_state.dart:1-13`（ADR-0012 双态） | 已持平 |
| 2 | 大纲/目录侧栏 | ✓ | **PRESENT** | `panels/toc_panel.dart:1,40`；`editor_shell.dart:210` drawer | 已持平 |
| 3 | 焦点模式（暗化其他段落） | ✓ | **PARTIAL** | `editor_shell.dart:110,132` `_toggleFocus` | 仅隐藏 chrome，**非逐段暗化** |
| 4 | 打字机模式（当前行居中） | ✓ | **ABSENT** | grep `typewriter/打字机/typingMode` → 0 命中 | 真实缺失（移 Phase 4） |
| 5 | 字数/字符统计 | ✓ | **PRESENT** | `editor_status_bar.dart:68`；`live_editing_state.dart:46` wordCount | 已持平 |
| 6 | 代码块语法高亮 | ✓ | **PRESENT\*** | `code_block.dart:14,177`（github/atom-one-dark） | 已持平，但**不随主题切换**（DEBT-011） |
| 7 | 数学（行内+块级） | ✓ | **PRESENT** | `formula_renderer.dart:1,42`；MathJax SVG + flutter_math_fork | **差异化主轴，已持平/更优** |
| 8 | 表格「单元格内联编辑」 | ✓ | **ABSENT** | `table_block.dart:13` "不实现可视化拖拽编辑"；edit 态=Markdown 源码 TextField | 真实缺失（仅 render+源码） |
| 9 | Mermaid/图表 | ✓ | **PRESENT** | `mermaid_block.dart:1,10`；`mermaid_service.dart` | 已持平 |
| 10 | 图片：插入/拖放/粘贴 | ✓ | **PARTIAL** | `markdown_toolbar.dart:204,243`；`asset_service.dart` | 工具栏选图有；**拖放/粘贴进正文 ABSENT** |
| 11 | 自动配对（括号/引号） | ✓ | **PRESENT** | `auto_pair_rules.dart:26,49`；`input_handler.dart:71` | 已持平 |
| 12 | 列表/引用回车续行 | ✓ | **PRESENT** | `auto_continue_rules.dart:29`；`input_handler.dart:92` | 已持平 |
| 13 | 多主题 | ✓（数十+社区） | **PARTIAL** | `app_theme.dart:10` `enum AppThemeMode {light, dark, sepia}` | 仅 3 套内置 |
| 14 | 自定义 CSS / 用户主题导入 | ✓ | **ABSENT** | grep `customCss/userCss/injectCss` → 0 命中 | 真实缺失 |
| 15 | 源码/原始 Markdown 视图切换 | ✓ | **ABSENT** | grep `sourceMode/rawMarkdown/源码` → 无全局开关 | 真实缺失 |
| 16 | 物理键盘快捷键（桌面） | ✓ | **ABSENT** | 仅 `buttons.dart:128-129` SingleActivator（按钮激活） | 真实缺失（移 Phase 4） |
| 17 | 选区浮动工具条/格式气泡 | ✓ | **ABSENT** | grep `SelectionMenu/FloatingMenu/OverlayEntry` → 0 命中 | 真实缺失（3.4.10 未启动） |
| 18 | 脚注/引用 | ✓ | **ABSENT** | grep `footnote/FootnoteElement` → 0 命中 | 真实缺失 |
| 19 | 交叉引用/链接到标题 | ✓ | **ABSENT** | grep `crossRef/link.*heading` → 0 命中 | 真实缺失 |
| 20 | Front matter (YAML) | ✓ | **PRESENT** | `front_matter_parser.dart:1,6`；`file_repository.dart:57,121` | 最小集 id/createdAt/updatedAt |
| 21 | 导出格式 | ✓（PDF/HTML/ePub/Word/RTF/TeX/图片） | **PARTIAL** | `export_service.dart:1,454` `enum ExportFormat {pdf, docx, txt}` | 仅 PDF/Word/TXT |
| 22 | 本地 .md 单一真相源 | ✓ | **PRESENT** | `block_editor.dart:49`（对齐 ADR-0003）；`editor_providers.dart:77` | **差异化主轴，已持平** |
| 23 | 自动保存 | ✓ | **PRESENT** | `autosave_service.dart:1,68`；`editor_page.dart:246` | 已持平 |
| 24 | 字号缩放/Zoom | ✓ | **PRESENT** | `editor_shell.dart:109,128-131,296` `TextScaler.linear(_zoomScale)` | 已持平 |
| 25 | 阅读宽度控制 (max-width) | ✓ | **PRESENT** | `workspace.dart:5,26` `kMaxPageWidth=720` | 固定 720，无可调 |

---

## 2. 已与 Typora 持平的能力（实做，非占位）

真 WYSIWYG（块级双态）、大纲侧栏、数学公式（行内+块级，MathJax+降级）、Mermaid 图表、自动配对与回车续行、三主题、Front matter、PDF/Word/TXT 导出、本地 .md 单一真相源、自动保存、字号缩放、阅读宽度约束、字数统计。

> 这些应归入 Baseline v1 的 **Core Stable**——已是Tafcm 的实做到位功能。

---

## 3. 最大缺口（差距显著）

### 3.1 文本级交互增强（写作流舒适度）—— 多为真实缺失
- **打字机模式**（#4）：完全未实现。
- **选区浮动格式条**（#17，原 3.4.10）：未启动，依赖 Overlay+TextSelection+光标坐标+滚动同步。
- **桌面物理快捷键**（#16，原 3.4.5/3.4.6）：移 Phase 4。
- **图片拖放/粘贴进正文**（#10）：仅工具栏选图 + 资产导入，缺拖放/粘贴。
- **焦点模式暗化**（#3）：仅隐藏 chrome，非 Typora 式逐段暗化。

### 3.2 高级块编辑
- **表格可视化单元格编辑**（#8）：仅「渲染 + 源码 TextField」双态，无可视化单元格编辑/拖拽列宽。这是与 Typora 表格体验差距最大的单点。

### 3.3 文档结构高级特性 —— 全部 ABSENT
- 脚注（#18）、交叉引用（#19）、源码视图切换（#15）、自定义 CSS（#14）。
- 其中**源码视图切换**对「任意来源 .md 即开即看」定位其实有价值（高级用户排障），值得优先评估。

### 3.4 导出广度（#21）—— 远不及 Typora
- 缺 HTML / ePub / RTF / TeX / 图片导出。
- HTML 导出对「便携分享」「网页发布」是高频需求，**建议优先补**（与现有 Markdown serializer 复用度高）。

### 3.5 平台广度（定位差异，非缺陷）
- Typora 桌面三端 + beta；Tafcm 当前 Android 单端，桌面/Web 在 Phase 4。
- 这是**移动优先定位的必然代价**，不是技术债，但影响「完整写作器」定位的达成。

---

## 4. 差距分类：合理定位 vs 真实缺失

| 类别 | 项 | 处置 |
|------|----|----|
| **合理定位差异**（不修） | 仅 Android 单端、固定阅读宽度、固定 3 主题 | 接受，Phase 4 再扩 |
| **真实缺失·高 ROI**（优先补） | 源码视图切换、HTML 导出、表格单元格编辑、图片拖放粘贴 | 进 roadmap P1 |
| **真实缺失·体验打磨**（排期） | 打字机、选区气泡、桌面快捷键、焦点暗化、自定义 CSS | Phase 4 写作流专项 |
| **真实缺失·文档结构**（评估） | 脚注、交叉引用 | 视产品定位决定 |

---

## 5. 给产品路线的建议（衔接 Baseline v1）

1. **不要为了"接近 Typora"而失去差异化**：数学富文本（#7）+ 本地 .md（#22）已是 Typora 没有的移动端级能力，应作为首屏叙事核心（呼应 ADR-0036 方向）。
2. **优先补"低成本高感知"两项**：HTML 导出（复用 serializer）、源码视图切换（高级用户排障）——二者都不触碰 Core Stable，风险低。
3. **表格单元格编辑**是单点最大体验债，建议在 Block Runtime 下一阶段专项（非 Phase 4 才做）。
4. **打字机/快捷键/选区气泡**归 Phase 4 桌面写作流专项，与移动端优先级解耦。
5. 本差距分析中的**真实缺失项**应作为新 Debt 条目追加进 `PHASE3.10-ENGINEERING-BASELINE-v1.md` 的 Refactor Needed / Missing Completion 分区，带 file:line 实证。

---

## 6. 验证口径

- 全部 25 项经 `flutter_app/lib` 代码 grep / 读取核实，file:line 见矩阵。
- 真理来源是代码；凡代码与审计文档冲突以代码为准。
- 本分析为 Phase 3.10 配套，不产生代码改动。

---

*本文件为 Tafcm vs Typora 差距分析（v1.0，代码实证）。*
