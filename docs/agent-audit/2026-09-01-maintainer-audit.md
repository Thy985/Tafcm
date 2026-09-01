# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-01（本地 UTC+8）· 触发：workflow_dispatch（第二次运行，当日）
> 说明：当日首次运行（commit 1ac70eb）Audit 存在格式违规（Status 枚举错误 / 小节标题不正确），本审计以 HEAD b72df08 为基准重新生成合规版本；当日首次运行产生的 6 个 Finding 已合并继承至本文件对应 ID。

## Repository Health

Commit: b72df08 fix(agent): E2 确定性观察 + E4 Finding 身份注册表（Reliability Hardening）
Version: v0.1.1+2
CI: ✅ 最近成功 run 33505869807（6m41s，全部 SUCCESS）；当前 in_progress run 33506769952
Tests: ✅ flutter analyze --no-fatal-infos --fatal-warnings → 0 error / 0 warning；flutter test test/parser/ test/export/ test/architecture/ → 129 passed, 6 skipped；formula_extractor_test.dart → 29 passed
Build: ✅ apk + web 构建成功（基于近期 CI 记录）
Open Issues: 1（#216 导出公式渲染问题，待调查）
Closed Issues: #215 已合入 PR #214（修复 SnackBar 残留）
Open PRs: 0
## New Findings

### F-2026-09-01-01 — PDF export SVG <use> 引用不解析导致公式空白

Category: bug
Severity: P1
Confidence: High
Status: UNCHANGED
Summary: PDF 导出走 SVG 路径时 MathJax <use href="#id"> 字形引用不被解析，画成占位符文本而非真实字形，导致公式在 PDF 中不可见
Evidence: flutter_app/lib/core/renderers/svg_to_pdf.dart:246（SvgUse → _drawUnsupported）；flutter_app/lib/core/renderers/mermaid_renderer.html:8（fontCache:global 使用 <use>）；flutter_app/lib/core/renderers/svg_parser.dart（defs 丢弃 / use 不解析）
Impact: 所有通过 SVG→PDF 路径导出的公式文档必然出现公式空白 —— Issue #216 根因之一
Recommendation: Create Issue
Related Issue: #216

### F-2026-09-01-02 — FormulaRenderHost Opacity(0.0) 可能导致 toImage() 产出全透明 PNG

Category: bug
Severity: P1
Confidence: Medium
Status: UNCHANGED
Summary: formula_pdf_renderer.dart:206-208 用 Opacity(opacity: 0.0) 包裹离屏捕获体（代码注释标明有意保留 paint pipeline），但需验证是否导致 RepaintBoundary.toImage() 产出 alpha=0 的全透明 PNG
Evidence: flutter_app/lib/core/renderers/formula_pdf_renderer.dart:206-208（Opacity(0.0) 包裹 capture 体）；flutter_app/lib/domain/services/exporters/word_exporter.dart preRenderAll 100% 走此路径
Impact: 若透明则 Word 导出公式必现空白；PDF 在 WebView/SVG 失败时 fallback 亦空白 —— Issue #216 另一根因
Recommendation: Investigate
Related Issue: #216
### F-2026-09-01-03 — 导出公式可见性无回归测试

Category: test-gap
Severity: P1
Confidence: High
Status: UNCHANGED
Summary: 导出公式相关测试只断言不崩溃 / 字节非空 / fallback 文本存在，无任何用例检查渲染 PNG 非透明 / PDF 有真实字形；真实用户（#216）已踩中此盲区
Evidence: 全测试目录无 alpha/pixel 断言；flutter_app/test/export/word_export_semantic_fidelity_test.dart:107-108 明确注释测试环境无渲染器 → widthEmu=0 → 走 fallback
Impact: 导出公式核心卖点回归只能靠人工发现，无法阻止类似 #216 的回归
Recommendation: Watch
Related Issue: N/A

### F-2026-09-01-04 — Golden CI 持续失败 + 112 个 failure PNG 入库违反 gitignore

Category: regression
Severity: P2
Confidence: High
Status: UNCHANGED
Summary: Golden (compare) CI job 连续 4–5 次 main/PR merge 均失败；flutter_app/test/golden/failures/ 下 112 个 PNG 突破 gitignore 语义被 git 跟踪
Evidence: Actions runs API 33403769658 / 33398279483 / 33391709227 Golden job failure；git ls-files flutter_app/test/golden/failures/*.png | wc -l → 112
Impact: CI 视觉回归守门失效，golden baseline 无法发挥检测作用
Recommendation: Watch
Related Issue: N/A

### F-2026-09-01-05 — ADR-0032 缺失

Category: architecture
Severity: P2
Confidence: High
Status: UNCHANGED
Summary: 代码中多处引用 ADR-0032（P0-D 导出组装有限性决策），但 docs/decisions/ADR/ 最新为 0031，该文件不存在
Evidence: flutter_app/lib/domain/services/exporters/pdf_exporter.dart:44/52/56/381/428/658 多次引用 ADR-0032；ls docs/decisions/ADR/ | sort | tail -5 → 最新 0031
Impact: 设计决策无档可查，未来维护者不知高密度公式降级的设计意图与边界条件
Recommendation: Create Issue
Related Issue: N/A

### F-2026-09-01-06 — E2 实验注入代码残留（相邻公式去重边界 >= 改为 >）

Category: tech-debt
Severity: P3
Confidence: High
Status: UNCHANGED
Summary: formula_extractor.dart:77-78 留有 E2-STABILITY 实验注入注释及行为变更（>= 改为 >），目的是测试相邻公式去重边界；当前 HEAD 仍带此改动
Evidence: flutter_app/lib/core/parser/formula_extractor.dart:77-78（注释 E2-STABILITY 实验注入 + if (m.start > lastEnd)）；commit 120338d 为确定性缺陷注入实验
Impact: 若此分支实验已结束且不应保留，则此改动会引入相邻公式（start == lastEnd）被错误丢弃的回归；但公式提取现有 29 项测试全部通过（无相邻公式覆盖用例）
Recommendation: Watch
Related Issue: N/A

### F-2026-09-01-07 — Issue #215 修复已合入但 Issue 未关闭

Category: tech-debt
Severity: P3
Confidence: High
Status: RESOLVED
Summary: Issue #215（导出完成后 SnackBar 残留）的修复已随 PR #214 92e6949 合入 main；issue 状态应为 CLOSED 但未更新
Evidence: PR #214 merge commit 92e6949；flutter_app/lib/presentation/screens/editor_export_actions.dart:117 已改 unawaited；flutter_app/lib/presentation/widgets/export_progress_overlay.dart:55-76 已有 dispose 清理
Impact: Issue 堆积，误导维护者认为问题未解决
Recommendation: Close（修复已合入，无需代码改动）
Related Issue: #215（应关闭）
## Existing Issue Updates

### Issue #216

Status: UNCHANGED
Root Cause: Likely
New Evidence: HEAD b72df08 未引入与 #216 相关的新代码变更（最近 5 commit 均为 agent 基础设施改动）；F1（SVG <use> 解析缺失）与 F2（Opacity(0) 透明 PNG 风险）根因假设仍未改变；公式提取器实验注入（F6）与 #216 无关
Next Step: ① 真机 PoC 验证 F2（检查导出 PNG alpha 通道）；② 复现最简文档导出，logcat 采集 SvgPlan/PNG fallback/FormulaQuality 确认 PDF 走的路径；③ 修复后为 F1/F2 各补一条回归测试

### Issue #215

Status: RESOLVED
Root Cause: Confirmed
New Evidence: PR #214（92e6949）已合入 main，修复代码确认；editor_export_actions.dart:117 + export_progress_overlay.dart:55-76 两处修复均在位
Next Step: 关闭 Issue（等待 Owner 确认新包真机复测后手动 close，或 bot 自动 close）

## Ecosystem Findings

### E-2026-09-01-01

Topic: Flutter RepaintBoundary.toImage() + Opacity(0.0) 行为
Current Solution: formula_pdf_renderer.dart:214 用 Opacity(opacity: 0.0) 包裹 capture 体（代码注释说明：保留 paint pipeline）
Alternative: 用 Visibility.hidden 或负坐标 + 固定尺寸容器
Comparison: Opacity(0) 保留 paint pipeline（注释理由），但可能引入 alpha=0 合成；Visibility.hidden 完全跳过 layout/paint，toImage() 可能拿不到 layer
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

- [ ] Issue #216 是否进入下周修复（关联：F-2026-09-01-01 / F-2026-09-01-02；建议：进入，P1 影响真实用户导出）
- [ ] ADR-0032 是否补写 + 修正编号序列缺口 0026/0027（关联：F-2026-09-01-05；建议：补写，设计意图不应无档可查）
- [ ] E2 实验注入代码（formula_extractor.dart:77-78 >= 改为 >）是否清理（关联：F-2026-09-01-06；建议：实验结束即 revert，避免长期留痕引入隐式回归风险）
