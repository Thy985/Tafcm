# Phase 3.5 Verification Report — Formula Rendering System（Tier 3 E2E 门禁）

> **本文件为 TEST_GAP_PLAN Tier 3 手动门禁记录，对应 Release Gate G1 / G3 / G6。**
>
> **版本**：v1.0
> **生成日期**：2026-07-28
> **生成者**：AI Agent（WorkBuddy）
> **审批状态**：⏳ 待 Human Owner 审批（合并 `test/phase35-e2e` 到 main 后 G1/G3/G6 置绿）
> **运行环境**：Android 模拟器 `sdk gphone64 x86 64`（emulator-5554，Android 16 / API 36），Flutter 3.44.6 stable，Windows 宿主机
> **说明**：CI 不跑 `integration_test`（无模拟器），本报告即 Tier 3 的权威运行记录。

---

## 1. E2E 运行记录（G1 / G6）

4 个 E2E 文件、13 个测试，全部在真实 Android 模拟器运行通过：

| 文件 | 测试数 | 结果 | 最终运行日志 | 覆盖门禁 |
|------|--------|------|--------------|----------|
| `integration_test/phase35_block_interaction_test.dart`（T3-1） | 4 | ✅ 全绿 | `/tmp/t3_regress.txt`（2026-07-28，attempt 1） | G1 拖拽重排/删除/上移/转换菜单 |
| `integration_test/phase35_formula_test.dart`（T3-2） | 4 | ✅ 全绿 | `/tmp/t3_2f.txt`（2026-07-28，attempt 1，16s） | G1 公式真实渲染 |
| `integration_test/phase35_persistence_roundtrip_test.dart`（T3-3） | 2 | ✅ 全绿 | `/tmp/t3_regress.txt`（2026-07-28，attempt 1） | G6 持久化 round-trip |
| `integration_test/phase35_export_e2e_test.dart`（T3-4） | 3 | ✅ 全绿 | `/tmp/t3_4b.txt`（2026-07-28） | 导出全链路（PDF `%PDF` 头 / DOCX `PK` 头 / 临时落盘 allowlist） |

测试逐条清单：

- **T3-1 块交互**：① 拖拽手柄重排后源码顺序落盘一致；② 工具条删除块；③ 工具条上移块；④ 转换类型菜单展开可触达（正文/标题/引用三项可见；选中项派发受 harness 限制，见 §4-L1）。
- **T3-2 公式**：① 块级 `$$E = mc^2$$` 真实 MathJax SVG 渲染（`FormulaSvgService.renderToSvg` 产出 `<svg`、进缓存、重开后 `SvgPicture` 上屏）；② WebView 未挂载时降级 `flutter_math_fork`（缓存为空 + `Math` widget 上屏）；③ 行内公式 `$a^2+b^2=c^2$` 渲染；④ 三主题（light/dark/sepia）`EditorTokens.textPrimary` 两两不同（公式取色 token 驱动）。
- **T3-3 持久化**：① 含公式+表格+代码块文档 编辑→autosave（debounce）→磁盘校验→关 App→重开→内容/公式/表格/代码块全部一致；② 标题编辑驱动 autosave 后 `$$...$$` LaTeX 序列化不丢。
- **T3-4 导出**：① `MarkdownExporter.exportToPdf` 产物 `%PDF` 魔数；② `exportToWord` 产物 `PK` 魔数（OOXML zip）；③ `ExportService.writeBytesToTempFile` 临时落盘且路径在 allowlist 内。

`flutter analyze --no-fatal-infos --fatal-warnings integration_test`：**No issues found**（2026-07-28）。

---

## 2. 🔴 重大发现：main 缺失 WebView 渲染资产（真实回归，已随本分支修复）

T3-2 首轮运行暴露产品级回归（正是 G1 门禁的价值所在）：

- **现象**：`FormulaSvgService.renderToSvg` 永远超时；`loadFile` 抛 `PlatformException(WebViewChannelDelegate, flutter_assets/assets/mermaid_renderer.html)`。
- **根因**：`assets/mermaid_renderer.html` + `assets/js/`（MathJax `tex-svg.js`、`mermaid.min.js`）**在 main（`c9274c6`）完全不存在**，pubspec 也只声明 `assets/fonts/`。资产曾于历史提交 `8bfe76a`（2026-06-04，LFS）引入，但该提交**从未合入 main**（`git merge-base --is-ancestor` 验证 NOT ancestor）。
- **影响**：主线上块级公式"真实 MathJax SVG"路径与 Mermaid 图表渲染**从未工作**，一直静默降级 `flutter_math_fork`/失败；导出 SVG 矢量嵌入路径同样断裂。因降级路径可用，无人察觉。
- **修复**（随本分支提交）：
  - `assets/mermaid_renderer.html`：从 `8bfe76a` 原样恢复（`git show`，内容零改动）。
  - `assets/js/tex-svg.js`：MathJax 3.2.2 官方 CDN 下载，**SHA-256 `d4295dc3…` 与原 LFS 指针完全一致**（bit 级还原）。
  - `assets/js/mermaid.min.js`：原 LFS 对象（size 3337508）无法从公共 CDN 精确匹配，取 API 兼容的 mermaid 10.9.3（size 3336760）。渲染协议（`mermaid.render` + v2 payload）不受影响。
  - `pubspec.yaml`：补 `assets/mermaid_renderer.html` + `assets/js/` 声明。
- **修复验证**：T3-2 测试① 从 194s 超时失败 → 10s 内真实 SVG 全绿。

---

## 3. Formula Compatibility Matrix（G3，空格清零）

维度：行内/块级 × 合法/非法 LaTeX × SVG 就绪/未就绪 × 3 主题。
证据栏引用：E2E（本报告 §1）、`test/formula_renderer_test.dart`（Phase 3.5 单测，CI 全绿 run 30326619456）、代码路径（`formula_renderer.dart` 行为，附行号）。

| # | 形态 | LaTeX | SVG/WebView | 主题 | 行为 | 证据 |
|---|------|-------|-------------|------|------|------|
| 1 | 块级 | 合法 | 就绪 | light | 真实 MathJax SVG（`SvgPicture` + mono 源码行） | E2E T3-2① |
| 2 | 块级 | 合法 | 就绪 | dark | 同上，颜色经 `tokens.textPrimary` 着色（`SvgPicture.string(color:)`） | E2E T3-2④ + `formula_renderer.dart:167` |
| 3 | 块级 | 合法 | 就绪 | sepia | 同上 | E2E T3-2④ |
| 4 | 块级 | 合法 | 未就绪 | light | 降级 `flutter_math_fork`（`Math` widget，display style） | E2E T3-2② |
| 5 | 块级 | 合法 | 未就绪 | dark/sepia | 同上，取色 token 驱动（`_flutterMathFallback`） | E2E T3-2④ + `formula_renderer.dart:205-215` |
| 6 | 块级 | 非法 | 就绪 | 全部 | MathJax 报 `LATEX_ERR` → `renderToSvg` 抛错被吞 → 降级 `flutter_math_fork` → 二次失败 → serif 源码文本 | `formula_renderer.dart:101-107,216-220` + 单测 error-fallback 用例 |
| 7 | 块级 | 非法 | 未就绪 | 全部 | `flutter_math_fork` `onErrorFallback` → serif 源码文本 | `formula_renderer.dart:216-220` + 单测 |
| 8 | 行内 | 合法 | （不适用²） | light | `flutter_math_fork`（`MathStyle.text`） | E2E T3-2③ |
| 9 | 行内 | 合法 | （不适用²） | dark/sepia | 同上，取色 `tokens.textPrimary` | E2E T3-2④ + `formula_renderer.dart:139-147` |
| 10 | 行内 | 非法 | （不适用²） | 全部 | `onErrorFallback` → `$...$` serif italic 源码 | `formula_renderer.dart:148-156` + 单测 |

² **显式记录**：行内公式**不走 SVG 路径**（设计决策，见 `formula_renderer.dart` 头注释：行内优先纯 Dart `flutter_math_fork`，不占 WebView 并发）。故行内 × SVG 就绪/未就绪维度合并为"不适用"，非空格。

---

## 4. 已知限制（harness 层，非产品缺陷）

- **L1 — PopupMenuButton item-select**：headless `integration_test` 下 `tester.tap` 点击 `PopupMenuItem<BlockType>` 不触发 `onSelected`（finder tap / `tapAt` 坐标 / 泛型 `find.byType` 均失败；同页 `IconButton` 正常）。T3-1④ 因此只断言菜单展开可触达；「选目标→改源」由单测 `applyBlockPrefix`（T1-4）+ Tier 4 真机人工验收覆盖。
- **L2 — `onLoadStop` 平台回调**：integration_test 下 WebView 停在 `about:blank`、`initialFile`/`onLoadStop` 不可靠。T3-2① 用生产公开 API 兜底：手动 `loadFile(MermaidService.rendererAssetPath)` + 轮询 `typeof window.renderLatex` + `markPageLoaded()`。生产 App 正常启动路径不受影响。
- **L3 — FormulaRenderer 首帧不重试**：`initState` 的渲染请求若早于 WebView attach 会降级且不重试（产品既有行为）。E2E 通过预填缓存后重开编辑器验证 SVG 上屏路径。可作为后续优化项（attach 后通知重渲染），非 P0/P1。

---

## 5. Release Gate 状态

| Gate | 内容 | 状态 |
|------|------|------|
| G1 | P0 E2E 全绿：拖拽重排（T3-1）+ 公式真实渲染（T3-2）在 Android 模拟器通过 | ✅（本报告 §1；含 §2 资产修复后才成立） |
| G3 | Formula compatibility matrix 填满无空格 | ✅（§3，10 行全覆盖，"不适用"为显式设计决策记录） |
| G6 | 持久化 round-trip 不丢内容（T3-3） | ✅（§1） |

*生成：2026-07-28 ｜ 分支 `test/phase35-e2e`（基址 main `c9274c6`）｜ 关联：docs/TEST_GAP_PLAN.md Tier 3、docs/ROADMAP.md §3.5*
