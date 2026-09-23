# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-24（本地 UTC+8）· 触发：schedule / workflow_dispatch
> HEAD: `cae3be0`（chore(agent): daily maintainer audit 2026-09-23）

## Repository Health

Commit: `cae3be0`（chore(agent): daily maintainer audit 2026-09-23）
Version: v0.1.1+2（pubspec.yaml: 0.1.1+2）/ ⚠️ kAppVersion 仍为 0.1.0+1（main.dart:24，Issue #238 未修复）
CI: ✅ 主干 CI 全绿（Run #35779093981 success 2026-09-22；今日 Run #35916475229 为本 audit 自身，in_progress）；Android emulator integration job 仍走 workflow_dispatch 手动触发
Tests: ✅ 架构测试 81/81 通过；✅ parser 56/56 通过；✅ storage 17/17 通过（2 skipped）；✅ golden 32/32 通过；✅ router_integration 3/3 通过；✅ encoding_manual_spec 8/8 通过；✅ search_screen 6/6 通过；✅ home_screen_behavior 4/4 通过（昨日 flaky 已恢复稳定，shader 问题自行消解）；合计 207/209 通过（2 skipped）
Build: ✅ apk + web 构建成功（Run #48 验证）
Analyze: ✅ flutter_app/lib/ + flutter_app/test/ 0 errors，0 warnings（394 info 级存量告警）；⚠️ tools/adi/ 仍 591 个 pre-existing analyze 错误（F-2026-09-05-02，不影响产品）
Open PRs: 无（#286/#290 均已合入 main）
Open Agent Issues: 12 个（详见下方 Existing Issue Updates）
Non-Agent Open Issues: 1 个（#264 外部可借鉴项目，非 agent 来源）
FINDINGS.md: 261 行，28 个唯一 fingerprint，224 个重复行（最多 14 次）——Issue #289 仍活跃恶化（较昨日 233 行/25 重复/最多 13 次，+28 行/+2 重复）

## Significant Changes Since Last Audit（2026-09-23）

自上次 audit（cae3be0）以来：**无产品代码变更**。HEAD 仍为 cae3be0，working tree clean。
近 30 天合入的产品 PR 列表与 9/23 audit 一致，无新增产品 commit。
昨日 home_screen_behavior_test flaky（shader Vulkan 缺失，3/4 通过）今日 4/4 通过，已自动恢复。

## New Findings

No significant findings.

> 注：今日深度锚点发现 `file_repository.dart:_readDecoded` 双重 readAsBytes（F-2026-09-19-02 同源）和 `search_screen.dart:_search` 串行 pathFor（F-2026-09-19-01 同源），经 fingerprint.py 判定为旧 Finding 延续（UNCHANGED），不新建。

## Existing Issue Updates

### Issue #238（kAppVersion 漂移）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: `flutter_app/lib/main.dart:24` `const String kAppVersion = '0.1.0+1';` vs `pubspec.yaml:4` `version: 0.1.1+2`。漂移持续未修复，一行修复。连续 9 日核实。
Next Step: 建议 Human Owner 审阅时顺手提，或单独一行 PR

### Issue #246（每次 notifyListeners 整树重建 EditorShell）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无产品代码变化，editor_shell 刷新逻辑未动。
Next Step: 待 Phase 4 编辑器重构时处理

### Issue #247（编辑内核 List 线性扫描 O(n)）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无产品代码变化，编辑内核未动。
Next Step: 待 Phase 4 编辑器重构时评估

### Issue #248（新编辑器导出路径无全局超时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第九日核实。`editor_export_actions.dart:75-141` `handleExport` 直接调用 `MarkdownExporter.exportToPdf/Word/Txt`，无任何 `.timeout()` 包装；`runWithGuard`（`export_progress_provider.dart:149-170`）仅保证 terminal-state（success/fail/exception 均 reset），不覆盖"body 永不 resolve"场景。Legacy 路径 `export_service.dart:589` 有 `_exportTimeout=120s`。两路径行为不一致，Issue 描述准确。
Next Step: 待立项：给新路径补全局超时

### Issue #249（autosave 每次全量序列化）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第九日核实。`editor_screen.dart:88-103` `_scheduleAutosave` 仍为 500ms Timer + 整读整写全文；`AutosaveService`（`autosave_service.dart`，debounce=1.5s + 指数退避）仅被新 WYSIWYG 编辑器使用，legacy 路径未接入。Issue 描述准确。
Next Step: 待 Phase 4 编辑器重构时统一评估

### Issue #250（Word 导出串行渲染）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点第九日核实。`word_exporter.dart:114-134` Mermaid 串行 `for`+`await` → 未调用 `MermaidService.renderToSvg` 并发队列（`_maxConcurrent=4` 实际无效）。Issue 描述准确。
Next Step: 待立项：接入并发渲染队列

### Issue #263（adb device offline）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: Issue #263 阻塞 FR-001 持续未关闭（已超 12 日）。Owner 已于 9/12 判定 PR #276 解决、android-device 不再阻塞 PR，但 Issue 状态仍为 OPEN。Issue 跟踪的 CI 失败模式（round 9-10 adb offline）无新发生记录（近 3 日 CI 正常通过），但 Issue 未执行关闭操作。
Next Step: 建议 Human Owner 执行 Issue #263 关闭操作（已超 12 日未关闭）

### Issue #287（CURRENT-STATE.md 阶段状态过时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: `.agent/CURRENT-STATE.md:7` 仍显示"Phase 3.12：信息架构重构（进行中）"，"最近更新: 2026-08-29"，与 AGENTS.md §0 / ROADMAP §当前阶段 矛盾持续。PR #286 未触及此文件。连续 10 日核实未变。
Next Step: 建议 Human Owner 授权后修正

### Issue #288（连续两周单日 audit 缺失）

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 2026-09-18 W38 Supervisor Report 确认 09-06 和 09-14 两个工作日 audit 缺失（workflow success 但无 audit 文件/commit）。今日（2026-09-24）audit 正常产出，但缺失历史无法追溯。
Next Step: 检查 tafcm-maintainer workflow 的 audit commit 步骤，确保"无发现"时仍 commit 空 audit 保持连续性

### Issue #289（FINDINGS.md 去重脚本 bug）

Status: UPDATED
Root Cause: Confirmed
New Evidence: 机器计数——FINDINGS.md 共 261 行，**28 个唯一 fingerprint，224 个重复行（最多 14 次）**，较昨日（233 行/25 重复/最多 13 次）继续轻微恶化（+28 行/+2 重复/最多 14 次）。去重脚本 bug 仍在，registry 未修复。
Next Step: 修复 fingerprint.py / update_index.py 追加逻辑（写入前去重），清理已重复的 ~205 行

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
New Evidence: PR #277（公式 SVG defs/use 内联）+ PR #278（移除 Opacity(0)，像素级守门）均已合入 main（2026-09-12）。Issue #216 已关闭（2026-09-12T04:43:24Z by owner）。证据：CI golden 测试全绿；word_export_semantic_fidelity_test 4/4 通过；export 测试 9/9 通过。
Next Step: 无后续行动，Issue 已关闭

## Ecosystem Findings

No significant ecosystem findings.

## Pending Decisions

- [ ] Issue #263 关闭确认 —— Owner 已于 9/12 判定解决（PR #276），Issue 仍 OPEN（已 12 日），建议执行关闭
- [ ] Issue #238 kAppVersion 同步（main.dart:24 `'0.1.0+1'` → `'0.1.1+2'`）—— 一行修复
- [ ] Issue #287 CURRENT-STATE.md 阶段状态更新 —— 建议 Human Owner 授权后修正
- [ ] Issue #288 audit 缺失根因 —— 检查 workflow commit 步骤
- [ ] Issue #289 FINDINGS.md 去重修复（261 行/224 重复/最多 14 次，持续轻微恶化）—— 修复脚本 + 清理重复行
- [ ] F-2026-09-19-01/F-02 搜索性能（serial pathFor + 全量 _readAll + 双重 readAsBytes）—— Watch，Phase 4 统一评估
- [ ] Issue #248 新编辑器导出路径补全局超时 —— 待立项（与 #250 同优先级）

## Frontier 推进记录

- FR-001（C-01 adb device offline）：depth 1→1（blocked，owner 已处置但 Issue #263 仍未关闭，已连续 12 日），verification_status 仍 needs-device-validation，handoff 指向 human（需执行关闭 Issue #263）
- FR-002（tools/adi analyze 错误备案）：depth 1→1（target=1 记录级已达），verification_status in-progress，无需深挖

## 今日深度锚点文件

| 文件 | 追踪路径 | 结论 |
|------|---------|------|
| `editor_export_actions.dart:75-141` | `handleExport` → `MarkdownExporter.exportToXxx` 无 timeout → `runWithGuard` 仅管 state 不管 timeout | Issue #248 Confirmed（第 9 日核实） |
| `export_progress_provider.dart:149-170` | `runWithGuard` try/catch/finally 保证 terminal-state，无 timeout 包装 | Issue #248 Confirmed |
| `export_service.dart:560-645` | `exportAndShare` → `.timeout(_exportTimeout=120s)` 仅在 legacy 路径 | 两路径行为不一致 |
| `word_exporter.dart:114-134` | Mermaid 串行 `for`+`await` → 未调用 `MermaidService.renderToSvg` 并发队列 | Issue #250 Confirmed（第 9 日核实） |
| `file_repository.dart:91-108` | `_readDecoded` 对同一 File 调用 `readAsBytes` 两次 → 冗余 I/O（fingerprint cea73c2918 命中 F-2026-09-19-02，UNCHANGED） | F-2026-09-19-02 UNCHANGED |
| `search_screen.dart:61-90` | `_search` 循环内串行 `await documentPathFor` → 可并发（fingerprint eec8bdc4 命中 F-2026-09-19-01，UNCHANGED） | F-2026-09-19-01 UNCHANGED |
| `main.dart:24` | `const String kAppVersion = '0.1.0+1'` vs pubspec `0.1.1+2` | Issue #238 Confirmed（第 9 日） |
| `FINDINGS.md` | 261 行，28 个唯一 fingerprint，224 个重复行（最多 14 次），较昨日继续轻微恶化 | Issue #289 UPDATED（+28 行/+2 重复） |
| `.agent/CURRENT-STATE.md:7,15` | 仍显示"Phase 3.12（进行中）"/"最近更新: 2026-08-29" | Issue #287 Confirmed（第 10 日） |
| `home_screen_behavior_test.dart` | 昨日 flaky（shader Vulkan 缺失，3/4 通过）→ 今日 4/4 通过，自动恢复 | F-2026-09-23-01 RESOLVED |
