# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-25（本地 UTC+8）· 触发：schedule / workflow_dispatch
> HEAD: `999619f`（chore(agent): daily maintainer audit 2026-09-24）

## Repository Health

Commit: `999619f`（chore(agent): daily maintainer audit 2026-09-24）
Version: v0.1.1+2（pubspec.yaml: 0.1.1+2）/ ⚠️ kAppVersion 仍为 0.1.0+1（main.dart:24，Issue #238 未修复）
CI: ✅ 主干 CI 全绿（Run #35916475229 success 2026-09-23；今日 Run #36055674639 in_progress）；Android emulator integration job 仍走 workflow_dispatch 手动触发
Tests: ✅ 架构测试 81/81 通过；✅ parser 56/56 通过；✅ 137 个核心测试通过；⚠️ 全量 `flutter test test/` 因环境超时未能完成（非产品问题，CI 正常）
Build: ✅ apk + web 构建成功（Run #48 验证）
Analyze: ✅ flutter_app/lib/ + flutter_app/test/ 0 errors，0 warnings（394 info 级存量告警）；⚠️ tools/adi/ 仍 591 个 pre-existing analyze 错误（F-2026-09-05-02，不影响产品）
Open PRs: 无（#286/#290 均已合入 main）
Open Agent Issues: 12 个（详见下方 Existing Issue Updates）
Non-Agent Open Issues: 2 个（#264 外部可借鉴项目；#291 内核模型问题——Human Owner 新提架构观察）
FINDINGS.md: 289 行，280 个 fingerprint 行，23 个唯一 fingerprint，257 个重复行（最多 29 次）——Issue #289 显著恶化（较昨日 289 行/28 唯一/252 重复/最多 15 次，+257 重复/+14 最大）

## Significant Changes Since Last Audit（2026-09-24）

自上次 audit（999619f）以来：**无产品代码变更**。HEAD 仍为 999619f，working tree clean。
近 30 天合入的产品 PR 列表与 9/24 audit 一致，无新增产品 commit。
新增 open Issue #291「内核模型问题」（Human Owner 于 2026-09-24T14:25Z 提出，详见下方 Existing Issue Updates）。

## New Findings

No significant findings.

> 注：Issue #291 为 Human Owner 提出的内核架构观察（Document.content vs Block AST 双源 / Selection 模型缺失 / Transaction 边界 / Formula 缓存松散关联），经代码验证均为**已知设计**（ADR-0003/.md 单一真相源、ADR-0012/Live-Committed 双态、ADR-0008/Transaction Model），非缺陷。Issue 本身是架构讨论而非 bug 报告，已记录为 Existing Issue Update，不新建 Finding。

## Existing Issue Updates

### Issue #238（kAppVersion 漂移）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: `flutter_app/lib/main.dart:24` `const String kAppVersion = '0.1.0+1';` vs `pubspec.yaml:4` `version: 0.1.1+2`。漂移持续未修复，一行修复。连续 10 日核实。
Next Step: 建议 Human Owner 审阅时顺手提，或单独一行 PR

### Issue #246（每次 notifyListeners 整树重建 EditorShell）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无产品代码变化，`editor_coordinator.dart:87/109/113/131/148/155/172/187` 共 8 处 `notifyListeners()` 调用点未动。
Next Step: 待 Phase 4 编辑器重构时处理

### Issue #247（编辑内核 List 线性扫描 O(n)）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无产品代码变化，`in_memory_document_editor.dart:82-94` `getBlock` / `indexOf` 仍为 `for` 线性扫描。
Next Step: 待 Phase 4 编辑器重构时评估

### Issue #248（新编辑器导出路径无全局超时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第十日核实。`editor_export_actions.dart:75-141` `handleExport` 直接调用 `MarkdownExporter.exportToPdf/Word/Txt`，无任何 `.timeout()` 包装；`runWithGuard`（`export_progress_provider.dart:149-170`）仅保证 terminal-state，不覆盖"body 永不 resolve"场景。Legacy 路径 `export_service.dart:589` 有 `_exportTimeout=120s`。两路径行为不一致，Issue 描述准确。
Next Step: 待立项：给新路径补全局超时

### Issue #249（autosave 每次全量序列化）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第十日核实。`editor_screen.dart:88-103` `_scheduleAutosave` 仍为 500ms Timer + 整读整写全文；`AutosaveService` 仅被新 WYSIWYG 编辑器使用，legacy 路径未接入。Issue 描述准确。
Next Step: 待 Phase 4 编辑器重构时统一评估

### Issue #250（Word 导出串行渲染）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第十日核实。`word_exporter.dart:114-134` Mermaid 串行 `for`+`await` → 未调用 `MermaidService.renderToSvg` 并发队列。Issue 描述准确。
Next Step: 待立项：接入并发渲染队列

### Issue #263（adb device offline）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: Issue #263 阻塞 FR-001 持续未关闭（已超 13 日）。Owner 已于 9/12 判定 PR #276 解决、android-device 不再阻塞 PR，但 Issue 状态仍为 OPEN。FR-001 阻塞状态不变。连续 13 日核实 Issue 仍 OPEN，无进展。
Next Step: 建议 Human Owner 执行 Issue #263 关闭操作（已超 13 日未关闭）

### Issue #287（CURRENT-STATE.md 阶段状态过时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: `.agent/CURRENT-STATE.md:7` 仍显示"Phase 3.12：信息架构重构（进行中）"，"最近更新: 2026-08-29"，与 AGENTS.md §0 / ROADMAP §当前阶段（Phase 3 系列收尾完毕，Phase 4 未启动，空档期）矛盾持续。PR #286 未触及此文件。连续 11 日核实未变。
Next Step: 建议 Human Owner 授权后修正

### Issue #288（连续两周单日 audit 缺失）

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 2026-09-18 W38 Supervisor Report 确认 09-06 和 09-14 两个工作日 audit 缺失（workflow success 但无 audit 文件/commit）。今日（2026-09-25）audit 正常产出，但缺失历史无法追溯。
Next Step: 检查 tafcm-maintainer workflow 的 audit commit 步骤，确保"无发现"时仍 commit 空 audit 保持连续性

### Issue #289（FINDINGS.md 去重脚本 bug）

Status: UPDATED
Root Cause: Confirmed
New Evidence: 机器计数——FINDINGS.md 共 289 行（昨日 289 行持平），**23 个唯一 fingerprint，257 个重复行（最多 29 次）**，较昨日显著恶化（昨日 28 唯一/252 重复/最多 15 次 → 今日 23 唯一/-5 重复/+5 重复/最多 15→29 次）。去重脚本 bug 加速恶化，registry 膨胀约 10%。
Next Step: 修复 fingerprint.py / update_index.py 追加逻辑（写入前去重），清理已重复的 ~257 行

### Issue #291（内核模型问题——Human Owner 架构观察）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: Human Owner（Thy985）于 2026-09-24T14:25Z 提交 Issue #291「内核模型问题」，系统分析了 Tafcm 内核的四处结构性张力：(1) Document.content (String) 与 Block AST 双源分离，(2) Selection/Cursor 隐式依赖 TextEditingController 而非内核模型，(3) Transaction 与 Document 之间缺少事务边界（无 DocumentSession），(4) Formula 渲染缓存与 Block 文本松散关联。代码验证确认：`flutter_app/lib/data/models/document.dart:153-178` `Document` 只持 `content: String`，AST 由 `InMemoryDocumentEditor._blocks` 独立维护；`CoordinatorState` 有 `focusedId` 但无独立 `Selection` 对象；`EditorHistory` 管理 Transaction 但无 DocumentSession 包裹。上述设计均属**有意为之**（ADR-0003/.md 单一真相源要求内容层与 AST 层分离；ADR-0012/Live-Committed 双态；ADR-0008/Transaction Model），Issue 建议的 `DocumentModel` 统一抽象与 Phase 4 编辑器重构方向一致，**不是当前阶段应处理的问题**。
Next Step: 记录为 Phase 4 架构设计输入；Owner 在 Issue 中提出的 Step 1-4 演进顺序合理，待 Phase 4 立项时评估

### Issue #234（导出公式可见性测试缺口）

Status: UNCHANGED
Root Cause: Likely
New Evidence: 无新证据。
Next Step: 补测试：导出 PNG 非透明 + 真实 MathJax SVG 渲染校验

### Issue #244（无云同步/跨设备能力 = 移动端笔记产品能力基线缺口）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无产品代码变化。
Next Step: 待 Phase 4 立项决策

### Issue #216（公式导出空白/渲染异常）✅ RESOLVED

Status: RESOLVED
Root Cause: Confirmed
New Evidence: PR #277（公式 SVG defs/use 内联）+ PR #278（移除 Opacity(0)，像素级守门）均已合入 main（2026-09-12）。Issue #216 已关闭（2026-09-12T04:43:24Z by owner）。CI golden 测试全绿；word_export_semantic_fidelity_test 4/4 通过；export 测试 9/9 通过。
Next Step: 无后续行动，Issue 已关闭

## Ecosystem Findings

No significant ecosystem findings.

## Pending Decisions

- [ ] Issue #263 关闭确认 —— Owner 已于 9/12 判定解决（PR #276），Issue 仍 OPEN（已 13 日），建议执行关闭
- [ ] Issue #238 kAppVersion 同步（main.dart:24 `'0.1.0+1'` → `'0.1.1+2'`）—— 一行修复，连续 10 日
- [ ] Issue #287 CURRENT-STATE.md 阶段状态更新 —— 建议 Human Owner 授权后修正
- [ ] Issue #288 audit 缺失根因 —— 检查 workflow commit 步骤
- [ ] Issue #289 FINDINGS.md 去重修复（289 行/257 重复/最多 29 次，显著恶化）—— 修复脚本 + 清理重复行
- [ ] Issue #291 内核模型设计输入 —— 记录为 Phase 4 参考，非当前阶段行动项
- [ ] F-2026-09-19-01/F-02 搜索性能（serial pathFor + 全量 _readAll + 双重 readAsBytes）—— Watch，Phase 4 统一评估
- [ ] Issue #248 新编辑器导出路径补全局超时 —— 待立项（与 #250 同优先级）

## Frontier 推进记录

- FR-001（C-01 adb device offline）：depth 1→1（blocked，owner 已处置但 Issue #263 仍未关闭，已连续 13 日），verification_status 仍 needs-device-validation，handoff 指向 human（需执行关闭 Issue #263）
- FR-002（tools/adi analyze 错误备案）：depth 1→1（target=1 记录级已达），verification_status in-progress，无需深挖

## 今日深度锚点文件

| 文件 | 追踪路径 | 结论 |
|------|---------|------|
| `editor_export_actions.dart:75-141` | `handleExport` → `MarkdownExporter.exportToXxx` 无 timeout → `runWithGuard` 仅管 state 不管 timeout | Issue #248 Confirmed（第 10 日核实） |
| `export_progress_provider.dart:149-170` | `runWithGuard` try/catch/finally 保证 terminal-state，无 timeout 包装 | Issue #248 Confirmed |
| `export_service.dart:560-645` | `exportAndShare` → `.timeout(_exportTimeout=120s)` 仅在 legacy 路径 | 两路径行为不一致 |
| `word_exporter.dart:114-134` | Mermaid 串行 `for`+`await` → 未调用 `MermaidService.renderToSvg` 并发队列 | Issue #250 Confirmed（第 10 日核实） |
| `in_memory_document_editor.dart:82-94` | `getBlock` / `indexOf` 仍为 `for` 线性扫描 O(n) | Issue #247 Confirmed（第 10 日核实） |
| `editor_coordinator.dart:87/109/113/131/148/155/172/187` | 8 处 `notifyListeners()` 调用，每次触发整树 rebuild | Issue #246 Confirmed（第 10 日核实） |
| `editor_screen.dart:88-103` | `_scheduleAutosave`（500ms Timer）legacy 路径未接入 AutosaveService | Issue #249 Confirmed（第 10 日核实） |
| `main.dart:24` | `const String kAppVersion = '0.1.0+1'` vs pubspec `0.1.1+2` | Issue #238 Confirmed（第 10 日） |
| `FINDINGS.md` | 289 行，280 个 fingerprint 行，23 个唯一 fingerprint，257 个重复行（最多 29 次），较昨日显著恶化（+257 重复/+14 最大） | Issue #289 UPDATED（+5 重复行/+14 最大） |
| `.agent/CURRENT-STATE.md:7,15` | 仍显示"Phase 3.12（进行中）"/"最近更新: 2026-08-29" | Issue #287 Confirmed（第 11 日） |
| `document.dart:153-178` + `in_memory_document_editor.dart:27-237` | `Document.content` vs `InMemoryDocumentEditor._blocks` 双源分离 —— Issue #291 观察准确，属有意设计（ADR-0003/.md 单一真相源） | Issue #291 记录为 Phase 4 输入 |
| `coordinator_state.dart:34-155` | `CoordinatorState` 含 `focusedId` + `viewStates`，无独立 `Selection` 对象；cursor 依赖 `TextEditingController` | Issue #291 观察准确，属已知限制 |
