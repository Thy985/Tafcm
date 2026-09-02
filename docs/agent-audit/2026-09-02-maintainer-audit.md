# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-02（本地 UTC+8）· 触发：workflow_dispatch（每日维护审查）
> HEAD: 4456e1c · 分支：fix/maintainer-guard-golden-failures（与 main 同步）

## Repository Health

Commit: 4456e1ca9fd4494f8107a729998eaed6d9dd7c88
Version: v0.1.1
CI: ⚠️ 主 CI（ci.yml）✅ 全绿（run 33517495156：Analyze/Test/Golden/Build 均 pass）；Maintainer schedule（run 33596732071）❌ 失败——report.json 未生成（Agent 基础设施问题，非产品 bug）；当前 fix 分支 run（33612728831）in_progress
Tests: ✅ 129 passed, 6 skipped（parser/export/architecture）；✅ 29 golden tests passed（基线已重生成）
Build: ✅ CI 显示 Android Debug APK + Web 构建均成功（run 33517495156）
Open Issues: 3（#216 / #233 / #234，均为 source:agent）
Open PRs: 0
Product Code Changes Since Yesterday: 0（仅 golden baseline PNG 更新 + agent 基础设施变更）

## New Findings

### F-2026-09-02-01

Category: regression
Severity: P1
Confidence: High
Status: UPDATED

Summary: Golden (compare) CI 持续失败 + 112 个 golden failure PNG 被 git 跟踪（F-2026-09-01-04 续）

Evidence: flutter_app/test/golden/failures/ 仍有 112 个 git-tracked PNG；本地 flutter test test/golden/ → 29 passed（基线重生成后通过）；main CI run 33517495156 Golden (compare) = success；.gitignore 第 53 行已声明忽略该目录（但仍被 git add -f 强制入库）

Impact: CI 视觉回归守门已恢复绿；但 112 个生成产物仍混入版本库，违反 gitignore 语义，仓库卫生退化

Recommendation: 执行 git rm --cached flutter_app/test/golden/failures/* 清掉入库记录；确认 .gitignore 规则生效；关闭 #233

Related Issue: #233

### F-2026-09-02-02

Category: tech-debt
Severity: P3
Confidence: High
Status: NEW

Summary: Maintainer Agent schedule run 报告文件未生成（report.json missing）

Evidence: run 33596732071 log：`FAIL: report.json 不存在: .tmp/tafcm-maintainer/report.json`；Audit 文件本身生成成功（Audit = SUCCESS），但邮件分发阶段失败（Email = FAILED）；Cline 输出到 .tmp/ 子目录但 generate_report.py 未找到输入

Impact: 邮件摘要无法发送，维护者收不到状态变化通知；Audit 文件本身入库正常，不影响事实账本

Recommendation: Watch（不建 Issue）—— Agent 基础设施的偶发问题，已有一次类似修复历史（PR #230 validator 容错）；若复现频率升高再升级

Related Issue: N/A

### F-2026-09-01-01

Category: bug
Severity: P1
Confidence: High
Status: UNCHANGED

Summary: SVG→PDF 矢量路径无法渲染真实 MathJax 输出——svg_to_pdf.dart:246 对 <use> 字形调用 _drawUnsupported

Evidence: svg_to_pdf.dart:246；mermaid_renderer.html:8（fontCache:'global'）；agent-investigations/issue-216-formula-export-blank.md

Impact: PDF 走 SVG 路径时公式必然异常 → Issue #216 根因之一

Recommendation: 归入 #216 修复

Related Issue: #216

### F-2026-09-01-02

Category: bug
Severity: P1
Confidence: Medium
Status: UNCHANGED

Summary: FormulaRenderHost 离屏捕获用 Opacity(opacity: 0.0) 包裹，疑似导致 toImage() 产出全透明 PNG

Evidence: formula_pdf_renderer.dart:206-208；word_exporter.dart preRenderAll 100% 走此路径

Impact: 若透明则 Word 公式必现空白；PDF 在 WebView/SVG 失败时也空白

Recommendation: 真机 PoC 验证 alpha 通道；若确认透明则改用 Visibility.hidden 或负坐标容器

Related Issue: #216

### F-2026-09-01-03

Category: test-gap
Severity: P1
Confidence: High
Status: UNCHANGED

Summary: 导出公式验证无 PNG alpha 非透明 / 真实 MathJax SVG 渲染断言

Evidence: word_export_semantic_fidelity_test.dart:107-108（注释说明测试环境无渲染器 → fallback）；全测试目录无 pixel/alpha 断言

Impact: 导出公式核心卖点回归只能靠人工，已被 #216 真实用户踩中

Recommendation: 补两层测试：① PNG alpha 非全透明；② 真实 MathJax <use> SVG 渲染断言

Related Issue: #234

### F-2026-09-01-04

Category: regression
Severity: P1
Confidence: High
Status: UPDATED

Summary: Golden CI 持续失败 + 112 个 failures PNG 被入库（见 F-2026-09-02-01）

Evidence: 见 F-2026-09-02-01

Impact: 见 F-2026-09-02-01

Recommendation: 见 F-2026-09-02-01

Related Issue: #233

### F-2026-09-01-05

Category: architecture
Severity: P2
Confidence: High
Status: UNCHANGED

Summary: 被引用的 ADR-0032 不存在——导出质量降级决策未留档

Evidence: ls docs/decisions/ADR/ | tail -5 → 最新 0031；grep -r "ADR-0032" docs/ → 仅命中 agent-audit 文档

Impact: 设计决策无档可查，未来维护者不知"高密度公式降级"的设计意图与边界

Recommendation: 补写 ADR-0032（P0-D 导出组装有限性决策）+ 修正 ADR 编号 gaps（0026/0027 缺失）

Related Issue: N/A

### F-2026-09-01-06

Category: architecture
Severity: P3
Confidence: High
Status: RESOLVED

Summary: Issue #215（导出 SnackBar 残留）修复已合入且 issue 已关闭

Evidence: PR #214 merge commit 92e6949；gh issue view 215 → state=CLOSED, closedAt=2026-09-01T03:10:19Z

Impact: Issue 堆积清理，无产品影响

Recommendation: 无需进一步操作

Related Issue: #215（已关闭）

## Existing Issue Updates

### Issue #216

Status: UNCHANGED
Root Cause: Likely
New Evidence: 无新证据。Doubao Supervisor 深度调查文档已写入 docs/agent-investigations/issue-216-formula-export-blank.md，确认两独立缺陷叠加（SVG <use> 解析缺失 + PNG Opacity(0) 疑似全透明）。
Next Step: 真机 PoC 验证 F-2026-09-01-02（PNG alpha 通道）为第一排查项；修复 F-2026-09-01-01（SVG <use> 引用解析）

### Issue #233

Status: UPDATED
Root Cause: Confirmed
New Evidence: golden 基线已于 2026-09-01 重生成（cbbd768）+ 渲染依赖已固定版本（af6a61e）；本地 flutter test test/golden/ 29 passed；main CI run 33517495156 Golden (compare) = success。但 flutter_app/test/golden/failures/ 仍有 112 个 git-tracked PNG 未被清理。
Next Step: 执行 git rm --cached flutter_app/test/golden/failures/* 恢复 gitignore 语义；确认后关闭 #233

### Issue #234

Status: UNCHANGED
Root Cause: Unknown
New Evidence: 无新证据。测试缺口确认存在。
Next Step: 补 PNG alpha 非透明断言 + 真实 MathJax SVG 渲染断言

### Issue #215

Status: RESOLVED
Root Cause: Confirmed
New Evidence: issue 已于 2026-09-01T03:10:19Z 关闭（PR #214 修复已合入）
Next Step: 无需操作

## Ecosystem Findings

No significant ecosystem findings.

## Pending Decisions

- [ ] 清理 112 个 git-tracked golden failure PNG（`git rm --cached flutter_app/test/golden/failures/*`）——关联：F-2026-09-02-01 / #233；建议：执行后关闭 #233
- [ ] Merge fix/maintainer-guard-golden-failures 到 main（Guard 放行 golden failures 目录，防止 schedule run 被拦截）——关联：F-2026-09-02-02；建议：合并后验证 schedule run 变绿
- [ ] #216 真机 PoC 验证 PNG alpha 通道（F-2026-09-01-02）——关联：F-2026-09-01-02 / #216；建议：优先于 SVG <use> 修复（PNG 路径更简单，可快速确认/排除一个根因）
- [ ] 补写 ADR-0032（P0-D 导出组装有限性决策）——关联：F-2026-09-01-05；建议：低优先级，有空闲时补
