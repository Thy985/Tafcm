# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-01（本地 UTC+8）· 触发：workflow_dispatch（每日维护审查）

## Repository Health

Commit: b72df08 fix(agent): E2 确定性观察 + E4 Finding 身份注册表（Reliability Hardening）
Version: v0.1.1
CI: ⚠️ Golden (compare) job 持续失败（历史 4–5 次 merge 均红）；tafcm-maintainer Run #21 in_progress
Tests: ✅ 77 passed, 6 skipped（architecture + export）；formula_extractor_test 29 passed
Build: ✅ Web + Android Debug APK 均成功
Open Issues: 1（#216 待调查）；#215 已 CLOSE（2026-09-01T03:10:19Z）
Open PRs: 0
Branch: experiment/e2-hardening（非 main）

## New Findings

### F-2026-09-01-01

Category: bug
Severity: P2
Confidence: High
Status: NEW

Summary: formula_extractor.dart 相邻公式去重边界错误（`>=` → `>`），导致紧接公式被丢弃
Evidence: `flutter_app/lib/core/parser/formula_extractor.dart:78`（`if (m.start > lastEnd)`，原逻辑应为 `>=`）；commit `120338d` 显式标记"E2-STABILITY 实验注入"
Impact: 相邻公式（前一个公式 end == 后一个公式 start）时第二个公式被错误丢弃；现有测试未覆盖此边界（`test/formula_extractor_test.dart:101` 用 `$a$ $b$` 有空格分隔，不触发）
Recommendation: Watch（实验分支故意注入，用于 E2 Detection Stability 量化；合入 main 前须还原 `>=`）
Related Issue: N/A（实验注入，不建 Issue）

### F-2026-09-01-02

Category: bug
Severity: P1
Confidence: High
Status: UNCHANGED

Summary: SVG→PDF 矢量路径无法渲染真实 MathJax 输出——`svg_to_pdf.dart:246` 对 `<use>` 字形调用 `_drawUnsupported`，画成占位符文本而非真实字形
Evidence: `svg_to_pdf.dart:246`（SvgUse → _drawUnsupported）；`mermaid_renderer.html:8`（fontCache:'global'）；`svg_parser.dart`（defs 丢弃 / use 不解析）
Impact: PDF 走 SVG 路径时公式必然异常 → Issue #216 根因之一
Recommendation: Create Issue（归入 #216 根因，修复方向：解析期实现 `<use href="#id">` → 内联 `<defs>` 对应 `<path>` 的引用解析）
Related Issue: #216

### F-2026-09-01-03

Category: architecture
Severity: P2
Confidence: High
Status: UNCHANGED

Summary: FormulaRenderHost 离屏捕获用 `Opacity(opacity: 0.0)` 包裹 capture 体，需验证是否导致 toImage() 产出全透明 PNG
Evidence: `flutter_app/lib/core/renderer/formula_pdf_renderer.dart:206-208` 注释说明这是有意为之（保留 paint pipeline）；`word_exporter.dart` preRenderAll 100% 走此路径
Impact: 若透明则 Word 公式必现空白；PDF 在 WebView/SVG 失败时也空白
Recommendation: Investigate（#216 首要排查项）→ 真机 PoC 检查导出 PNG alpha 通道
Related Issue: #216

### F-2026-09-01-04

Category: test-gap
Severity: P1
Confidence: High
Status: UNCHANGED

Summary: 导出公式相关验证只断言"不崩溃 / 字节非空 / fallback 文本存在"，无用例检查渲染公式 PNG 非透明 / PDF 有真实字形
Evidence: 全测试目录无 alpha/pixel 断言；`word_export_semantic_fidelity_test.dart:107-108` 明确注释测试环境无渲染器 → widthEmu=0 → 走 fallback
Impact: 导出公式核心卖点回归只能靠人工，已被真实用户（#216）踩中
Recommendation: Watch（补测试建议列入 #216 修复后回归清单）
Related Issue: N/A（测试缺口，随 #216 修复一并补）

### F-2026-09-01-05

Category: regression
Severity: P1
Confidence: High
Status: UNCHANGED

Summary: Golden (compare) CI 持续红，最近 4–5 次 main/PR merge 全部失败；`flutter_app/test/golden/failures/` 有 112 个 git-tracked PNG（突破 gitignore 语义）
Evidence: Actions runs API `33403769658`/`33398279483`/`33391709227` Golden job failure；`git ls-files flutter_app/test/golden/failures/*.png | wc -l` → 112
Impact: CI 守门失效，视觉回归无法检测
Recommendation: Investigate（① 判定 stale baseline vs 真实回归；② 恢复 failures/ 忽略语义或重建基线）
Related Issue: N/A（CI 配置问题，不建 Issue）

### F-2026-09-01-06

Category: architecture
Severity: P2
Confidence: High
Status: UNCHANGED

Summary: 被引用的 ADR-0032 不存在——#216 正文引用 `docs/decisions/ADR/0032-export-assembly-finite-guarantee.md`，PR #213/#214 提交信息均称"P0-D（ADR-0032）"，但仓库中无该文件
Evidence: `ls docs/decisions/ADR/ | tail -5` → 最新 0031；`grep -r "ADR-0032" docs/` → 仅命中 agent-audit 文档；`pdf_exporter.dart:44/52/56/381/428/658` 多处注释引用 ADR-0032
Impact: 设计决策无档可查，未来维护者不知"高密度公式降级"的设计意图与边界
Recommendation: Create Issue（补写 ADR-0032 + 修正 ADR 编号间隙 0026/0027）
Related Issue: N/A（文档缺失，建议随 #216 修复一并处理）

### F-2026-09-01-07

Category: tech-debt
Severity: P3
Confidence: High
Status: RESOLVED

Summary: Issue #215（导出 SnackBar 残留）修复已合入 main 且 Issue 已关闭
Evidence: PR #214 merge commit `92e6949`；`editor_export_actions.dart:117` 已改 unawaited；`export_progress_overlay.dart:55-76` 已有 dispose 清理；`gh issue view 215` → state=CLOSED, closedAt=2026-09-01T03:10:19Z
Impact: 无（已修复）
Recommendation: Ignore（闭环）
Related Issue: #215（已关闭）

## Existing Issue Updates

### Issue #215

Status: RESOLVED
Root Cause: Confirmed
New Evidence: `gh issue view 215` 确认 state=CLOSED（2026-09-01T03:10:19Z）；PR #214 `92e6949` 已合入 main
Next Step: 无需进一步操作

### Issue #216

Status: UNCHANGED
Root Cause: Likely
New Evidence: 无新增证据；确认 ADR-0032 确实不存在（代码中 6 处注释引用，文档目录无此文件）；F1（SVG `<use>`）与 F2（Opacity PNG 透明）两路径根因仍为主要嫌疑
Next Step: ① 真机 PoC 验证 F2（检查导出 PNG alpha）；② logcat 采集 SvgPlan/PNG fallback/FormulaQuality 确认 PDF 实际走的路径；③ 修复后补"公式可见性"回归测试

## Ecosystem Findings

### E-2026-09-01-01

Topic: Flutter RepaintBoundary.toImage() + Opacity 行为
Current Solution: formula_pdf_renderer.dart:214 用 Opacity(opacity: 0.0) 包裹 capture 体
Alternative: 用 Visibility.hidden 或负坐标 + 固定尺寸容器
Comparison: Opacity(0) 保留 paint pipeline（代码注释理由），但可能引入 alpha=0 合成；Visibility.hidden 完全跳过 layout/paint，toImage() 可能拿不到 layer
Recommendation: INVESTIGATE
Decision: no

### E-2026-09-01-02

Topic: MathJax SVG <use> 引用解析
Current Solution: 自研 svg_parser.dart + svg_to_pdf.dart（~760 行），丢弃 <defs> / 不解析 <use>
Alternative: 解析期展开 <use href="#id"> → 内联 <defs> 对应 <path>
Comparison: 当前简单但 MathJax 公式必然异常；展开 <use> 工程量中等但能根治 F1
Recommendation: KEEP
Decision: no

## Pending Decisions

- [ ] Issue #216 修复优先级：是否进入下周 P0 修复队列（关联：F-2026-09-01-02/03；建议：进入，用户直接踩中）
- [ ] ADR-0032 补写责任人与时限：是否由 Agent 起草 + Owner 签字（关联：F-2026-09-01-06；建议：Agent 起草，Owner 签字）
- [ ] E2 实验分支 formula_extractor.dart 还原：`>=` → `>` 是否在主实验闭环后还原（关联：F-2026-09-01-01；建议：E2 量化完成后还原，合入 main 前必须还原）
