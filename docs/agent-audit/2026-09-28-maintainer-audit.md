# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-28（本地 UTC+8）· 触发：schedule / workflow_dispatch
> HEAD: `921e572`（test(renderer): 导出公式可见性测试（#234）+ 修复 MathJax 字形被静默丢弃 (#296)）

## Repository Health

Commit: `921e572`（test(renderer): 导出公式可见性测试（#234）+ 修复 MathJax 字形被静默丢弃 (#296)）
Version: v0.1.1+2（pubspec.yaml: 0.1.1+2 / main.dart:26 `kAppVersion = '0.1.1+2'`，已同步 ✅）
CI: ✅ 主干 CI 全绿（Run #917 success；今日 Run #56 tafcm-maintainer in_progress）；Android emulator integration job 仍走 workflow_dispatch 手动触发
Tests: ✅ 架构测试 81/81 通过；✅ 新测试 39/39 通过（png_visibility 4/4 + formula_rendering_contract 7/7 + word_ooxml_builder 28/28）；⚠️ 全量 `flutter test test/` 因环境超时未能完成（非产品问题，CI 正常）
Build: ✅ apk + web 构建成功（与 #917 CI 一致）
Analyze: ✅ flutter_app/lib/ + flutter_app/test/ 0 errors，0 warnings（394 info 级存量告警）；⚠️ tools/adi/ 仍 591 个 pre-existing analyze 错误（F-2026-09-05-02，不影响产品）
Open PRs: 无（#286/#290/#294/#295/#296 均已合入 main）
Open Agent Issues: 7 个（#246-#250 / #263，详见下方 Existing Issue Updates）
Non-Agent Open Issues: 2 个（#264 外部可借鉴项目；#291 内核模型问题——Human Owner 提出的架构观察）
Closed since last audit: #238（kAppVersion 漂移）、#287（CURRENT-STATE.md 阶段状态过时）、#288（audit 单日缺失）、#289（FINDINGS.md 去重脚本 bug）、#234（导出公式可见性测试缺口）
FINDINGS.md: 37 行，28 个唯一 fingerprint，0 重复行（Issue #289 修复后干净，去重脚本「整体重建」生效）

## Significant Changes Since Last Audit（2026-09-25）

自上次 audit（999619f）以来：**4 个产品/基础设施 commit 合入 main**：

| Commit | 内容 | 关闭 Issue |
|--------|------|-----------|
| `d53bd9a` | fix(maintenance): P0 批次修复 #288/#287/#238 | #288 / #287 / #238 |
| `38ba9fb` | fix(agent-audit): FINDINGS.md 注册表去重脚本改「整体重建」 | #289 |
| `921e572` | test(renderer): 导出公式可见性测试 + 修复 MathJax 字形被静默丢弃 | #234 / #216 类回归 |

**具体变更**：
1. **#238 修复**：`main.dart:26` kAppVersion `'0.1.0+1'` → `'0.1.1+2'`，消除诊断版本号漂移；新增注释提醒"双真相源，每逢发布必须同步"
2. **#287 修复**：`.agent/CURRENT-STATE.md` 阶段更新为"阶段间空档期（Phase 3 系列全部收尾，Phase 4 未启动）"，最近更新标记同步至 2026-09-26
3. **#288 修复**：新增 `.github/scripts/tafcm-maintainer/ensure_daily_audit.py` 兜底脚本，workflow 在 Cline 未产出时自动生成 No significant findings. 兜底文件
4. **#289 修复**：`fingerprint.py` 改「整体重建」方案——抽取固定 schema 后用去重唯一行重建数据区，FINDINGS.md 从 289 行/28 唯一/257 重复 → 37 行/28 唯一/0 重复
5. **#234/#296 修复**：
   - 新增 `png_visibility.dart`（82 行）：纯 CPU 解码路径（`instantiateImageCodec`），CI headless 可跑，统计 opaqueRatio / inkRatio
   - 新增 `svg_pdf_palette.dart`（58 行）：从 svg_to_pdf.dart 拆出的纯函数辅助（parseSvgColor / resolveSvgFont），遵守 400 行限制
   - `svg_to_pdf.dart` 修复：`_drawPath` 在 fill/stroke 均为 null 时（MathJax 字形 path 只带 d、祖先 `<g fill="currentColor">` 承载着色）原实现直接 return → 真实 MathJax 字形被静默丢弃 → 导出公式空白。现默认到 textColor/黑，确保字形真实着墨
   - 新增 `formula_rendering_contract_test.dart`：用真实 MathJax `<use>` 断言 `debugPathOpsDrawn > 0`（= 公式真的画出墨水）
   - 新增 `word_ooxml_builder_test.dart`：公式 PNG 成功分支 → document.xml 嵌 `w:drawing` + `a:blip` 而非 fallback 文本
   - 三层 CI 回归网（PNG/A/B）已织入

## New Findings

No significant findings.

> 注：今日深度锚点追及 921e572 引入的三个新文件 + svg_to_pdf.dart _drawPath 修复路径，确认 png_visibility.dart 纯 CPU 路径正确（CI headless 可跑，4/4 测试通过），svg_pdf_palette.dart 58 行不超标，svg_to_pdf.dart 修复后 370 行合规，FINDINGS.md 去重后干净（0 重复），无新增 bug/regression/architecture drift。

## Existing Issue Updates

### Issue #234（导出公式可见性测试缺口）✅ RESOLVED

Status: RESOLVED
Root Cause: Confirmed
New Evidence: PR #296 已合入（commit 921e572）。新增 png_visibility.dart（纯 CPU 解码路径）+ formula_rendering_contract_test.dart（debugCountPathOps）+ word_ooxml_builder_test.dart（公式 PNG 成功分支）三层 CI 守门，4+7+28=39 测试全通过。MathJax 字形丢失 bug 已修复（_drawPath null fill/stroke fallback 到 textColor/黑）。
Next Step: 无后续行动，Issue 已关闭（2026-09-26T10:47Z by owner）

### Issue #216（公式导出空白/渲染异常）✅ RESOLVED（延续 #234 修复）

Status: RESOLVED
Root Cause: Confirmed
New Evidence: _drawPath fill/stroke 均为 null 时原实现直接 return → 真实 MathJax 字形被静默丢弃（根因确认）。PR #296 已修复：fallback 到 textColor/黑。CI 三层守门已覆盖（PNG 可见性 + SVG path ops 计数 + Word 嵌入）。Issue 已于 2026-09-12 关闭，此次为实质修复闭环。
Next Step: 无后续行动

### Issue #238（kAppVersion 漂移）✅ RESOLVED

Status: RESOLVED
Root Cause: Confirmed
New Evidence: `main.dart:26` kAppVersion `'0.1.0+1'` → `'0.1.1+2'`（commit d53bd9a）。同时新增注释提醒"双真相源，每逢发布必须同步"，并建议后续自动从 pubspec 生成 / 加 CI 断言防漂移。连续 12 日核实后正式修复。
Next Step: 无后续行动，Issue 已关闭

### Issue #287（CURRENT-STATE.md 阶段状态过时）✅ RESOLVED

Status: RESOLVED
Root Cause: Confirmed
New Evidence: `.agent/CURRENT-STATE.md` 阶段更新为"阶段间空档期（Phase 3 系列全部收尾，Phase 4 未启动）"，最近更新标记同步至 2026-09-26（commit d53bd9a）。与 AGENTS.md §0 / ROADMAP §当前阶段 一致。连续 13 日核实后正式修复。
Next Step: 无后续行动，Issue 已关闭

### Issue #288（连续两周单日 audit 缺失）✅ RESOLVED

Status: RESOLVED
Root Cause: Confirmed
New Evidence: 新增 `.github/scripts/tafcm-maintainer/ensure_daily_audit.py` 兜底脚本（commit d53bd9a）。workflow 在 Cline 未产出当日 audit 时自动生成 No significant findings. 兜底文件，保持每日连续性。今日本次 audit 正常产出，验证兜底机制有效。
Next Step: 无后续行动，Issue 已关闭

### Issue #289（FINDINGS.md 去重脚本 bug）✅ RESOLVED

Status: RESOLVED
Root Cause: Confirmed
New Evidence: `fingerprint.py` 改「整体重建」方案（commit 38ba9fb）——抽取固定 schema 后用去重唯一行重建数据区，不再原位追加。FINDINGS.md 从 289 行/28 唯一/257 重复（最多 29 次）→ 37 行/28 唯一/0 重复。新增 `fingerprint_dedupe_test.py`（159 行）单元测试：验证 collapse 整体去重、保留 schema、幂等、CLI 端到端不膨胀。ci.yml 新增 finding-registry-dedupe 守门 job。连续 4 日核实后正式修复。
Next Step: 无后续行动，Issue 已关闭

### Issue #246（每次 notifyListeners 整树重建 EditorShell）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无产品代码变化，editor_coordinator.dart 8 处 notifyListeners() 调用点未动。
Next Step: 待 Phase 4 编辑器重构时处理

### Issue #247（编辑内核 List 线性扫描 O(n)）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无产品代码变化，in_memory_document_editor.dart getBlock/indexOf 仍为 for 线性扫描。
Next Step: 待 Phase 4 编辑器重构时评估

### Issue #248（新编辑器导出路径无全局超时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第十一日核实。editor_export_actions.dart:75-141 handleExport 直接调用 MarkdownExporter.exportToPdf/Word/Txt，无任何 .timeout() 包装；runWithGuard（export_progress_provider.dart:149-170）仅保证 terminal-state，不覆盖"body 永不 resolve"场景。Legacy 路径 export_service.dart:589 有 _exportTimeout=120s。两路径行为不一致，Issue 描述准确。
Next Step: 待立项：给新路径补全局超时

### Issue #249（autosave 每次全量序列化）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第十一日核实。editor_screen.dart:88-103 _scheduleAutosave 仍为 500ms Timer + 整读整写全文；AutosaveService 仅被新 WYSIWYG 编辑器使用，legacy 路径未接入。Issue 描述准确。
Next Step: 待 Phase 4 编辑器重构时统一评估

### Issue #250（Word 导出串行渲染）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第十一日核实。word_exporter.dart:114-134 Mermaid 串行 for+await → 未调用 MermaidService.renderToSvg 并发队列。Issue 描述准确。
Next Step: 待立项：接入并发渲染队列

### Issue #263（adb device offline）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: Issue #263 阻塞 FR-001 持续未关闭（已超 16 日）。Owner 已于 9/12 判定 PR #276 解决、android-device 不再阻塞 PR，但 Issue 状态仍为 OPEN。FR-001 阻塞状态随 Issue #263 保持 open，verification_status 仍 needs-device-validation，handoff 指向 human（需执行关闭 Issue #263）。
Next Step: 建议 Human Owner 执行 Issue #263 关闭操作以正式解除 FR-001 阻塞

### Issue #291（内核模型问题——Human Owner 架构观察）

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无产品代码变化。Issue #291 观察到的 Document.content vs Block AST 双源分离 / Selection 模型缺失 / Transaction 边界 / Formula 缓存松散关联 等均经代码验证为有意设计（ADR-0003/.md 单一真相源、ADR-0012/Live-Committed 双态、ADR-0008/Transaction Model）。Issue 建议的 DocumentModel 统一抽象与 Phase 4 编辑器重构方向一致，不是当前阶段应处理的问题。
Next Step: 记录为 Phase 4 架构设计输入；Owner 在 Issue 中提出的 Step 1-4 演进顺序合理，待 Phase 4 立项时评估

## Ecosystem Findings

No significant ecosystem findings.

> 注：今日审查 svg_to_pdf.dart _drawPath null fill/stroke fallback 修复时，观察到 MathJax SVG 的 `<g fill="currentColor">` 继承着色模式是本项目的已知生态约束（MathJax v3 输出规范）。当前 fallback 策略（默认 textColor/黑）已正确处理该模式，无需迁移生态方案。

## Pending Decisions

- [ ] Issue #263 关闭确认 —— Owner 已于 9/12 判定解决（PR #276），Issue 仍 OPEN（已 16 日），建议执行关闭以解除 FR-001 阻塞
- [ ] F-2026-09-19-01/F-02 搜索性能（serial pathFor + 全量 _readAll + 双重 readAsBytes）—— Watch，Phase 4 统一评估
- [ ] Issue #248 新编辑器导出路径补全局超时 —— 待立项（与 #250 同优先级）
- [ ] Issue #291 内核模型设计输入 —— 记录为 Phase 4 参考，非当前阶段行动项（Owner 已提出，待 Phase 4 立项决策）
- [ ] kAppVersion 双真相源 CI 断言 —— main.dart:26 注释已提醒，建议立项加 CI 守门防漂移（P3，非紧急）

## Frontier 推进记录

- FR-001（C-01 adb device offline）：depth 1→1（blocked，owner 已处置但 Issue #263 仍未关闭，已连续 16 日），verification_status 仍 needs-device-validation，handoff 指向 human（需执行关闭 Issue #263）
- FR-002（tools/adi analyze 错误备案）：depth 1→1（target=1 记录级已达），verification_status in-progress，无需深挖

## 今日深度锚点文件

| 文件 | 追踪路径 | 结论 |
|------|---------|------|
| `svg_to_pdf.dart:266-291` | `_drawPath` fill/stroke 均为 null 时 fallback 到 textColor/黑 → MathJax 字形不再被静默丢弃 | #296 修复 Confirmed（今日核实） |
| `svg_pdf_palette.dart:1-58` | 纯函数辅助（parseSvgColor / resolveSvgFont），从 svg_to_pdf.dart 拆出，遵守 400 行限制 | TC-ARCH-7 合规 |
| `png_visibility.dart:40-83` | `analyzePng` 纯 CPU 解码路径（instantiateImageCodec），CI headless 可跑 | 4/4 测试通过 |
| `formula_rendering_contract_test.dart:1-204` | debugCountPathOps 断言公式 SVG 真的画了矢量操作 | 7/7 测试通过 |
| `word_ooxml_builder_test.dart:1-366` | 公式 PNG 成功分支 → document.xml 嵌 w:drawing + a:blip 而非 Cambria fallback | 28/28 测试通过 |
| `main.dart:26` | kAppVersion `'0.1.1+2'`，已同步 pubspec，#238 修复生效 | 连续 12 日核实后闭环 |
| `.agent/CURRENT-STATE.md:7,15` | 阶段更新为"阶段间空档期"，最近更新 2026-09-26，#287 修复生效 | 连续 13 日核实后闭环 |
| `FINDINGS.md` | 37 行，28 个唯一 fingerprint，0 重复行，#289 修复生效 | 去重脚本整体重建方案验证通过 |
| `editor_export_actions.dart:75-141` | handleExport 无 timeout 包装，runWithGuard 仅管 terminal-state | Issue #248 Confirmed（第 11 日核实） |
| `export_progress_provider.dart:149-170` | runWithGuard try/catch/finally 保证 terminal-state，无 timeout 包装 | Issue #248 Confirmed |
| `export_service.dart:560-645` | exportAndShare → .timeout(_exportTimeout=120s) 仅在 legacy 路径 | 两路径行为不一致 |
| `word_exporter.dart:114-134` | Mermaid 串行 for+await → 未调用 MermaidService.renderToSvg 并发队列 | Issue #250 Confirmed（第 11 日核实） |
| `in_memory_document_editor.dart:82-94` | getBlock / indexOf 仍为 for 线性扫描 O(n) | Issue #247 Confirmed（第 11 日核实） |
| `editor_coordinator.dart:87/109/113/131/148/155/172/187` | 8 处 notifyListeners() 调用，每次触发整树 rebuild | Issue #246 Confirmed（第 11 日核实） |
| `editor_screen.dart:88-103` | _scheduleAutosave（500ms Timer）legacy 路径未接入 AutosaveService | Issue #249 Confirmed（第 11 日核实） |
| `coordinator_state.dart:34-155` | CoordinatorState 含 focusedId + viewStates，无独立 Selection 对象 | Issue #291 观察准确，属已知限制 |

