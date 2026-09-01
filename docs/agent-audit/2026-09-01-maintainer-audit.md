# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-01（本地 UTC+8）· 触发：workflow_dispatch（第二次运行，同日上午首次运行已生成首版）
> 基线 commit：1ac70eb（上午首次 Audit HEAD）· 当前 commit：b72df08（+3 commits 自上午）
> 分支：experiment/e2-hardening

## Repository Health

Commit: b72df08dde71db018b0925d1206bb617ffc49c2b
Version: v0.1.1（README 声明）
CI: ✅ main CI 全绿（6m44s，Analyze/Test/Build 均 success）；Golden (compare) job 已 `if: false` 暂停（不再触发）
Tests: ✅ flutter analyze --no-fatal-infos --fatal-warnings：0 error / 0 warning（390 info）；flutter test test/architecture/ test/parser/ test/export/：129 passed, 6 skipped
Build: ✅ Web + Android Debug APK 均成功
Open Issues: 1（#216 公式导出渲染异常；#215 SnackBar 残留已由 PR #214 修复待关闭）
Open PRs: 0
Branch: experiment/e2-hardening（E2/E4 可靠性硬化实验分支，与 main 有 3 个 commit 差距）

## New Findings

### F-2026-09-01-01

Category: bug
Severity: P1
Confidence: High
Status: UNCHANGED

Summary: SVG→PDF 矢量路径无法渲染真实 MathJax 输出——`svg_to_pdf.dart:178-179` 对 `<use>` 字形调用 `_drawUnsupported`，画成占位符文本而非真实字形。
Evidence: `flutter_app/lib/core/renderers/svg_to_pdf.dart:178-179`（SvgUse → _drawUnsupported）；`flutter_app/lib/core/renderers/svg_parser.dart:285-288`（SvgUse 节点解析完整但渲染端未展开）
Impact: PDF 走 SVG 路径时公式必然异常 → Issue #216 根因之一
Recommendation: 归入 #216 根因调查，修复方向：解析期实现 `<use href="#id">` → 内联 `<defs>` 对应 `<path>` 的引用解析
Related Issue: #216

### F-2026-09-01-02

Category: bug
Severity: P2
Confidence: High
Status: UNCHANGED

Summary: FormulaRenderHost 离屏捕获使用 Positioned(left: -10000, top: -10000) 定位，需验证 RepaintBoundary.toImage() 是否产出有效 PNG（非透明、非零尺寸）。
Evidence: `flutter_app/lib/core/services/formula_pdf_renderer.dart:106-109`（Positioned left/top = -10000）；`formula_pdf_renderer.dart:29-31`（显式 _offscreenCanvasWidth=800 / _offscreenCanvasHeight=200）
Impact: 若 toImage() 异常则 Word 公式必现空白（Word exporter preRenderAll 走此路径）
Recommendation: INVESTIGATE（#216 次要排查项）→ 真机 PoC 检查导出 PNG alpha 通道与像素非零；若异常，修复方向：改为 Visible but off-screen 策略
Related Issue: #216

### F-2026-09-01-03

Category: test-gap
Severity: P1
Confidence: High
Status: UNCHANGED

Summary: 导出公式相关验证只断言"不崩溃 / 字节非空 / fallback 文本存在"，无用例检查渲染公式 PNG 非透明 / PDF 有真实字形。
Evidence: 全测试目录无 alpha/pixel 断言；`word_export_semantic_fidelity_test.dart:107-108` 明确注释测试环境无渲染器 → widthEmu=0 → 走 fallback
Impact: 导出公式核心卖点回归只能靠人工，已被真实用户（#216）踩中
Recommendation: 补两层测试：① PNG alpha 非全透明；② 真实 MathJax `<use>` SVG 渲染断言
Related Issue: N/A（测试缺口，不建 Issue）

### F-2026-09-01-04

Category: architecture
Severity: P2
Confidence: High
Status: UNCHANGED

Summary: 被引用的 ADR-0032 不存在——测试与代码多处引用 `docs/decisions/ADR/0032-export-assembly-finite-guarantee.md`，PR #213/#214 提交信息均称"P0-D（ADR-0032）"，但仓库中无该文件（最新 ADR 为 0031）。
Evidence: `ls docs/decisions/ADR/ | tail -5` → 最新 0031；`grep -r "ADR-0032" flutter_app/` 命中 `formula_density_degrade_test.dart` / `pdf_exporter.dart`（多处分段引用）
Impact: 设计决策无档可查，未来维护者不知"高密度公式降级"的设计意图与边界
Recommendation: 补写 ADR-0032（P0-D 导出组装有限性决策）；顺带核对 ADR 编号序列（0025 出现两次、缺 0026/0027）
Related Issue: N/A（文档缺失，不建 Issue）

### F-2026-09-01-05

Category: regression
Severity: P2
Confidence: High
Status: UNCHANGED

Summary: golden baselines 多次微小像素漂移（cbbd768 / 7548be4 各重生成一次），虽在 .gitignore 语义下 failures/ 已忽略，但 golden/golden/ 基线文件仍在 git 跟踪中。
Evidence: `git diff 1ac70eb..b72df08 --stat` 显示 11 个 golden PNG 大小变化（如 editor_shell_full_page_dark.png: 101135→101071 bytes）；`.gitignore` 仅忽略 `flutter_app/test/golden/failures/`
Impact: golden 基线每次微小变动需重新提交，增加 PR review 噪音
Recommendation: Watch（依赖版本固定后应稳定，待观察是否持续漂移）
Related Issue: N/A

### F-2026-09-01-06

Category: architecture
Severity: P3
Confidence: High
Status: UNCHANGED

Summary: Issue #215（导出 SnackBar 残留）的修复已合入 main（PR #214 `92e6949`），issue 仍 OPEN（早于本次审查看，已在上午 Audit 记录）。
Evidence: PR #214 merge commit `92e6949`；`editor_export_actions.dart:117` 已改 unawaited；`export_progress_overlay.dart:55-76` 已有 dispose 清理
Impact: Issue 堆积，误导维护者认为问题未解决
Recommendation: CLOSE（修复已合入，待真机复测确认后可关闭）
Related Issue: #215（应关闭）

### F-2026-09-01-07

Category: bug
Severity: P1
Confidence: High
Status: NEW

Summary: formula_extractor.dart 相邻公式去重逻辑存在确定性回归——`start > lastEnd` 应改为 `start >= lastEnd`，导致相邻公式（前一个 end == 后一个 start）被错误丢弃。
Evidence: `flutter_app/lib/core/parser/formula_extractor.dart:78`（`if (m.start > lastEnd)`，上方注释明确标注"E2-STABILITY 实验注入"）；`formula_extractor.dart:75`（`int lastEnd = -1`）；commit `120338d` 明确为 E2 实验注入点
Impact: 文档中出现相邻公式（如 `$a$` 后紧跟 `$b$`）时第二个及后续相邻公式丢失，影响 parser 正确性
Recommendation: Create Issue（或归属 E2 实验分支自行清理）——若实验分支保留，应在实验结束后 revert；若合并到 main 前必须修复
Related Issue: N/A（实验分支注入，暂不跨分支建 Issue；合并前必须修复）

### F-2026-09-01-08

Category: tech-debt
Severity: P3
Confidence: High
Status: NEW

Summary: ADI CLI 工具（`tools/adi/`）引用未声明依赖——`crypto` / `archive` / `test` 包在 pubspec.yaml 中不存在，导致 `flutter analyze` 报告 uri_does_not_exist 错误。
Evidence: `flutter analyze --no-fatal-infos --fatal-warnings` 输出：`tools/adi/adi.dart:18:8` crypto 不存在；`tools/adi/import_zip.dart:18-19:8` crypto/archive 不存在；`tools/adi/test/causality_test.dart:12:8` test 包不存在
Impact: CLI 工具无法在当前 Flutter 环境下静态分析通过；不影响主 App 构建，但影响 ADI 工具链可用性
Recommendation: Watch（tools/adi 为独立 CLI，可能需要独立 pubspec 或 dependency_overrides；短期不影响产品）
Related Issue: N/A

## Existing Issue Updates

### Issue #216

Status: UNCHANGED
Root Cause: Likely
New Evidence: 本日为第二次运行，未发现新证据；F1（SVG `<use>` 引用解析缺失）和 F2（离屏 RenderHost 可见性）仍为最高置信根因候选
Next Step: 真机 PoC 验证 F2（PNG alpha 通道）+ 复现最简文档导出 logcat 采集

### Issue #215

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无——修复已合入 PR #214（`92e6949`），保持已修复状态（由 Human Owner 关闭）
Next Step: 等待 Owner 手动关闭；或在本轮审核中直接建议关闭（见 F-06）

## Ecosystem Findings

### E-2026-09-01-01

Topic: Flutter RepaintBoundary.toImage() + Offscreen 定位策略
Current Solution: formula_pdf_renderer.dart:106-109 用 Positioned(left: -10000, top: -10000) + 固定 800×200 Container 包裹 RepaintBoundary
Alternative: Visibility.hidden / Opacity(0.0) / 负坐标 + 固定尺寸容器
Comparison: Positioned(-10000) 避免 layout 干扰但依赖 RepaintBoundary 在无屏幕区域仍可渲染；Visibility.hidden 可能完全跳过 paint → toImage() 拿不到 layer；Opacity(0) 保留 paint 但有 alpha=0 风险
Recommendation: INVESTIGATE
Decision: no

### E-2026-09-01-02

Topic: MathJax SVG `<use>` 引用解析
Current Solution: 自研 svg_parser.dart + svg_to_pdf.dart（~760 行），解析 `<use>` 为 SvgUse 节点但在渲染时调用 `_drawUnsupported` 画占位符
Alternative: 解析期展开 `<use href="#id">` → 内联 `<defs>` 对应 `<path>`
Comparison: 当前简单但 MathJax 公式必然异常（F1）；展开 `<use>` 工程量中等但能根治 F1
Recommendation: KEEP
Decision: no

## Pending Decisions

- [ ] Issue #215 是否由 Human Owner 手动关闭？（修复已合入 PR #214，关联：F-2026-09-01-06）
- [ ] E2-stability 实验分支（experiment/e2-hardening）中的 formula_extractor.dart 回归（`start > lastEnd`，commit `120338d`）是否在合并前修复？（关联：F-2026-09-01-07）
- [ ] ADR-0032 补写优先级：是否安排专项补写 P0-D 导出组装有限性决策文档？（关联：F-2026-09-01-04）
