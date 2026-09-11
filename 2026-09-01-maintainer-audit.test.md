# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-01（本地 UTC+8）· 触发：workflow_dispatch（每日维护审查）

## Repository State

Commit: 1ac70eb fix(agent): 兼容 Cline 生成的带描述 Finding 标题 + 补 import sys (#225)
Version: v0.1.1
CI: ⚠️ Golden (compare) job 持续失败（历史 4-5 次 merge 均红）
Tests: ✅ flutter test test/parser/ test/export/ test/architecture/ → 129 passed, 6 skipped
Build: ✅ Web + Android Debug APK 均成功
Open Issues: 2（#215 已修复待关闭 / #216 待调查）
Open PRs: 0

## Findings

### F-2026-09-01-01

Category: bug
Severity: P1
Confidence: High
Status: open

Problem: SVG→PDF 矢量路径无法渲染真实 MathJax 输出——`svg_to_pdf.dart:246` 对 `<use>` 字形调用 `_drawUnsupported`，画成占位符文本而非真实字形。
Evidence: `svg_to_pdf.dart:246`（SvgUse → _drawUnsupported）；`mermaid_renderer.html:8`（fontCache:'global'）；`svg_parser.dart`（defs 丢弃 / use 不解析）
Impact: PDF 走 SVG 路径时公式必然异常 → Issue #216 根因之一
Recommendation: 归入 #216 根因，修复方向：解析期实现 `<use href="#id">` → 内联 `<defs>` 对应 `<path>` 的引用解析
Issue: 关联 Issue #216（未单独建 Issue）

### F-2026-09-01-02

Category: architecture
Severity: P2
Confidence: High
Status: open

Problem: FormulaRenderHost 离屏捕获用 `Opacity(opacity: 0.0)` 包裹 capture 体，需验证是否导致 toImage() 产出全透明 PNG。
Evidence: `formula_pdf_renderer.dart:206-208` 注释说明这是有意为之（保留 paint pipeline）；`word_exporter.dart` preRenderAll 100% 走此路径
Impact: 若透明则 Word 公式必现空白；PDF 在 WebView/SVG 失败时也空白
Recommendation: INVESTIGATE（#216 首要排查项）→ 真机 PoC 检查导出 PNG alpha 通道；若确认透明，修复方向：捕获体改为不透明但不可见的容器
Issue: 关联 Issue #216（未单独建 Issue）

### F-2026-09-01-03

Category: test-gap
Severity: P1
Confidence: High
Status: open

Problem: 导出公式相关验证只断言"不崩溃 / 字节非空 / fallback 文本存在"，无用例检查渲染公式 PNG 非透明 / PDF 有真实字形。
Evidence: 全测试目录无 alpha/pixel 断言；`word_export_semantic_fidelity_test.dart:107-108` 明确注释测试环境无渲染器 → widthEmu=0 → 走 fallback
Impact: 导出公式核心卖点回归只能靠人工，已被真实用户（#216）踩中
Recommendation: 补两层测试：① PNG alpha 非全透明；② 真实 MathJax `<use>` SVG 渲染断言
Issue: N/A（测试缺口，不建 Issue）

### F-2026-09-01-04

Category: regression
Severity: P1
Confidence: High
Status: open

Problem: Golden (compare) CI 持续红，最近 4–5 次 main/PR merge 全部失败；`flutter_app/test/golden/failures/` 有 112 个 git-tracked PNG（突破 gitignore 语义）。
Evidence: Actions runs API `33403769658`/`33398279483`/`33391709227` Golden job failure；`git ls-files flutter_app/test/golden/failures/*.png | wc -l` → 112
Impact: CI 守门失效，视觉回归无法检测
Recommendation: ① 判定 stale baseline vs 真实回归；② 恢复 failures/ 忽略语义（或重建基线）
Issue: N/A（CI 配置问题，不建 Issue）

### F-2026-09-01-05

Category: architecture
Severity: P2
Confidence: High
Status: open

Problem: 被引用的 ADR-0032 不存在——#216 正文引用 `docs/decisions/ADR/0032-export-assembly-finite-guarantee.md`，PR #213/#214 提交信息均称"P0-D（ADR-0032）"，但仓库中无该文件。
Evidence: `ls docs/decisions/ADR/ | tail -5` → 最新 0031；`grep -r "ADR-0032" docs/` → 仅命中 agent-audit 文档
Impact: 设计决策无档可查，未来维护者不知"高密度公式降级"的设计意图与边界
Recommendation: 补写 ADR-0032（P0-D 导出组装有限性决策）+ 修正 ADR 编号（0025 出现两次、缺 0026/0027）
Issue: N/A（文档缺失，不建 Issue）

### F-2026-09-01-06

Category: architecture
Severity: P3
Confidence: High
Status: new

Problem: Issue #215（导出 SnackBar 残留）的修复已合入 main（PR #214 `92e6949`），但 issue 仍 OPEN。
Evidence: PR #214 merge commit `92e6949`；`editor_export_actions.dart:117` 已改 unawaited；`export_progress_overlay.dart:55-76` 已有 dispose 清理
Impact: Issue 堆积，误导维护者认为问题未解决
Recommendation: CLOSE（修复已合入，待真机复测确认后可关闭）
Issue: Issue #215（应关闭）

## Issue Investigations

### Issue #216

Status: investigated
Root Cause: Likely
Evidence: 两独立缺陷叠加：(1) F1（主嫌疑）PDF 走 SVG 路径时 MathJax `<use>` 字形被画成占位符文本 → 公式不可见；(2) F2（次嫌疑）Word 走 PNG 路径，若 `Opacity(0)` 导致 toImage() 产出全透明 PNG → 公式空白
Recommendation: ① 真机 PoC 验证 F2（检查导出 PNG alpha）；② 复现最简文档导出，logcat 采集 SvgPlan/PNG fallback/FormulaQuality 确认 PDF 走的路径；③ 修复后为 F1/F2 各补一条回归测试
Investigation: 无深度调查文档（问题已足够明确，直接修复即可）

### Issue #215

Status: resolved
Root Cause: Confirmed
Evidence: PR #214 已修复（`editor_export_actions.dart:117` unawaited + `export_progress_overlay.dart:55-76` dispose 清理）
Recommendation: 确认新包真机复测后关闭
Investigation: N/A

## Ecosystem Watch

### E-2026-09-01-01

Topic: Flutter RepaintBoundary.toImage() + Opacity 行为
Current Solution: formula_pdf_renderer.dart:214 用 Opacity(opacity: 0.0) 包裹 capture 体
Alternative: 用 Visibility.hidden 或负坐标 + 固定尺寸容器
Comparison: Opacity(0) 保留 paint pipeline（代码注释理由），但可能引入 alpha=0 合成；Visibility.hidden 完全跳过 layout/paint，toImage() 可能拿不到 layer
Recommendation: INVESTIGATE

### E-2026-09-01-02

Topic: MathJax SVG <use> 引用解析
Current Solution: 自研 svg_parser.dart + svg_to_pdf.dart（~760 行），丢弃 <defs> / 不解析 <use>
Alternative: 解析期展开 <use href="#id"> → 内联 <defs> 对应 <path>
Comparison: 当前简单但 MathJax 公式必然异常；展开 <use> 工程量中等但能根治 F1
Recommendation: KEEP

## Architecture

1. 公式渲染三路并行（最高优先技术债）：同一 LaTeX 在编辑器（flutter_math_fork）、PDF（MathJax SVG）、Word（offscreen flutter_math_fork PNG）三处渲染，输出不一致且维护面×3。
2. ADR-0032 缺失（F5）：导出质量降级决策未留档。
3. golden failures/ 混入版本库（F4）：生成产物突破 gitignore 语义。

## Test Gaps

按价值排序：
1. 导出公式"可见性"断言：PNG alpha 非全透明 + 真实 MathJax `<use>` SVG 渲染断言（防 F1/F2 回归，也防 #216 复发）。最值得补。
2. 真实 MathJax 输出 fixture：用 tex-svg.js 实际产出的 SVG（<defs>+<use>）替换当前伪造内联 path 的用例。
3. CI golden 基线校准：判定 stale baseline vs 真实回归，并恢复 failures/ 忽略语义。

## Recommended Actions

1. Investigate #216 根因并修复公式导出空白 —— 真机 PoC 验证 F2（Opacity(0) 透明 PNG）为第一排查项，同时修复 F1（SVG `<use>` 引用解析）；修复后补"公式可见性"回归测试。这是用户直接踩中的 P1。
2. 关闭 Issue #215（修复已合入 PR #214，待真机复测确认）+ 补写 ADR-0032（P0-D 导出组装有限性决策）。
3. 恢复 main CI 绿色 —— 处理 Golden (compare) 持续失败（重建基线 or 修回归），并清理 112 个被强制入库的 golden failure PNG。
