# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-19（本地 UTC+8）· 触发：schedule / workflow_dispatch
> HEAD: `b0270f0`（docs(supervision): 2026-W38 周度监督报告 #290）

## Repository Health

Commit: `b0270f0`（docs(supervision): 2026-W38 周度监督报告）
Version: v0.1.1+2（pubspec.yaml: 0.1.1+2）/ ⚠️ kAppVersion 仍为 0.1.0+1（main.dart:24，Issue #238 未修复）
CI: ✅ 主干 CI 全绿（Run #35345273563 success PR #286；Run #35346361283 success PR #290；Run #35387631667 in_progress 为本 audit 自身）；Android emulator integration job 仍走 workflow_dispatch 手动触发（PR #276 处置结论）
Tests: ✅ 架构测试 81/81 通过；✅ search_screen_test 6/6 通过（新增）；✅ encoding_manual_spec_test 8/8 通过（新增）；✅ crud_flow + storage_repository 18/18 通过；✅ parser 56/56 通过
Build: ✅ apk + web 构建成功（Run #35345273563 验证）
Analyze: ✅ flutter_app/lib/ + flutter_app/test/ 0 errors，0 warnings（394 info 级存量告警）；⚠️ tools/adi/ 仍 591 个 pre-existing analyze 错误（F-2026-09-05-02，不影响产品）
Open PRs: 无（#286/#290 均已合入 main）
Open Agent Issues: 12 个（详见下方 Existing Issue Updates）

## Significant Changes Since Last Audit（2026-09-18）

自上次 audit（f7952c7）以来：

**产品变更（PR #286，2026-09-18 合入）**：
- P0-1 全局搜索接线：新增 SearchScreen（`search_screen.dart` 254 行）、DocumentRepository.searchDocuments 端口、路由 `/search`、首页搜索按钮恢复
- P0-2 编码手动指定与声明保持：TextEncoding 白名单枚举、front-matter encoding 声明（读写）、atomicWrite 重构为 atomicWriteBytes + String 薄封装、loadFromPath 加可选 encoding 参数
- 文档收敛：ADR-0031 状态同步 + ADR-0033 新增、外部参照文档与代码对齐

**监督报告（PR #290，2026-09-18 合入）**：
- W38 Supervisor Report：指出 FINDINGS.md 去重 bug（Issue #289）、audit 缺失（Issue #288）、Issue #263 归因修正未吸收

**无产品代码回归**：所有新增测试通过，arch 测试 81/81 通过，analyze 零 error/warning。

## New Findings

### F-2026-09-19-01 — search_screen `_search` 串行 documentPathFor 调用

Category: tech-debt
Severity: P3
Confidence: High
Status: NEW

Summary: search_screen.dart `_search` 方法对每个搜索结果串行调用 `await repo.documentPathFor(d.id)`，N 条结果即 N 次顺序 IO，未使用 Future.wait 并行化。

Evidence:
- `flutter_app/lib/presentation/screens/search_screen.dart:61-90`，`_search` 方法内 `for (final d in docs)` 循环中逐行 `await repo.documentPathFor(d.id)`
- 与 `file_repository.dart:300-310` `searchDocuments` 返回的 Document 列表规模正相关
- 测试 6/6 通过（未覆盖性能场景）

Impact: 文档数量较大时（如 >50 篇），搜索响应时间随结果数线性增长（N × pathFor IO 延迟）。当前规模下不阻断功能，但属可预见的性能退化点。

Recommendation: Watch
Related Issue: N/A（P3 技术债，不值得单独建 Issue；与 Issue #247 编辑内核 O(n) 同类低优先级优化）

### F-2026-09-19-02 — file_repository searchDocuments 全量加载

Category: tech-debt
Severity: P3
Confidence: High
Status: NEW

Summary: file_repository.dart `searchDocuments` 调用 `_readAll()` 加载全部文档到内存后过滤，O(n) 全量 IO + 内存占用，大文档库场景下性能退化。

Evidence:
- `flutter_app/lib/core/services/file_repository.dart:300-310` `searchDocuments` 实现：`final entries = await _readAll(); return entries.where(...).map(...).toList()`
- `_readAll()`（第 110-126 行）遍历 documents 目录全部 .md 文件并逐一反序列化
- 与 `listDocuments()` 共用同一实现，无索引优化

Impact: 文档数量大时搜索延迟显著（全量文件 IO + 解析），与 Issue #247（编辑内核 O(n)）同类架构级限制。当前阶段空档期，不紧急。

Recommendation: Watch
Related Issue: N/A（P3 技术债，Phase 4 编辑器重构时统一评估）

## Existing Issue Updates

### Issue #238（kAppVersion 漂移）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无新证据。`flutter_app/lib/main.dart:24` `const String kAppVersion = '0.1.0+1';` vs `pubspec.yaml:4` `version: 0.1.1+2`。一行修复。
Next Step: 建议 Human Owner 审阅时顺手提，或单独一行 PR

### Issue #246（每次 notifyListeners 整树重建 EditorShell）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: PR #286 未涉及 editor_shell 刷新逻辑，代码无变化。
Next Step: 待 Phase 4 编辑器重构时处理

### Issue #247（编辑内核 List 线性扫描 O(n)）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: PR #286 未涉及编辑内核，代码无变化。今日新增 F-2026-09-19-02 同属全量加载类架构限制。
Next Step: 待 Phase 4 编辑器重构时评估

### Issue #248（新编辑器导出路径无全局超时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: PR #286 未涉及导出链路，代码无变化。
Next Step: 待立项：给新路径补全局超时

### Issue #249（autosave 每次全量序列化）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: PR #286 未涉及 autosave，代码无变化。
Next Step: 待 Phase 4 编辑器重构时统一 autosave 路径

### Issue #250（Word 导出串行渲染）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: PR #286 未涉及导出，代码无变化。
Next Step: 待立项优化（Future.wait + _maxConcurrent 控制）

### Issue #263（C-01 android emulator 集成测试阻塞）

Status: UPDATED
Root Cause: Confirmed
New Evidence: Owner 于 2026-09-12 在 Issue 评论中给出处置结论："android-device 不再阻塞 PR，本 issue 的'多轮 adb offline 复发'随手动巡检模式消解。PR #276 合并后可关闭。" PR #276 已合入（2026-09-12）。Issue 状态仍为 OPEN，属未执行关闭操作。
Next Step: 建议 Human Owner 或 CI workflow 自动关闭 Issue #263

### Issue #287（CURRENT-STATE.md 阶段状态过时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: `.agent/CURRENT-STATE.md:7` 仍显示"Phase 3.12：信息架构重构（进行中）"，"最近更新: 2026-08-29"，与 AGENTS.md §0 / ROADMAP §当前阶段 矛盾持续。PR #286 未触及此文件。
Next Step: 建议 Human Owner 授权后修正

### Issue #234（导出公式可见性测试缺口）

Status: UNCHANGED
Root Cause: Likely
New Evidence: 无新证据。
Next Step: 补测试：导出 PNG 非透明 + 真实 MathJax SVG 渲染校验

### Issue #288（连续两周单日 audit 缺失）

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 2026-09-18 W38 Supervisor Report 确认 09-06 和 09-14 两个工作日 audit 缺失（workflow success 但无 audit 文件/commit）。今日（2026-09-19）audit 正常产出，但缺失历史无法追溯。
Next Step: 检查 tafcm-maintainer workflow 的 audit commit 步骤，确保"无发现"时仍 commit 空 audit 保持连续性

### Issue #289（FINDINGS.md 去重脚本 bug）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 机器计数：FINDINGS.md 共 199 行，24 个 fingerprint 重复（最多 12 次），registry 严重膨胀。W38 Supervisor Report 定性为 CRITICAL。今日未修复。
Next Step: 修复 fingerprint.py / update_index.py 追加逻辑（写入前去重），清理已重复的 140+ 行

## Ecosystem Findings

No significant ecosystem findings.

## Pending Decisions

- [ ] Issue #263 关闭确认 —— Owner 已于 9/12 判定解决（PR #276），Issue 仍 OPEN，建议执行关闭
- [ ] Issue #238 kAppVersion 同步（main.dart:24 `'0.1.0+1'` → `'0.1.1+2'`）—— 一行修复
- [ ] Issue #287 CURRENT-STATE.md 阶段状态更新 —— 建议 Human Owner 授权后修正
- [ ] Issue #288 audit 缺失根因 —— 检查 workflow commit 步骤
- [ ] Issue #289 FINDINGS.md 去重修复 —— 修复脚本 + 清理重复行
- [ ] F-2026-09-19-01/F-02 搜索性能（serial pathFor + 全量 _readAll）—— Watch，Phase 4 统一评估

## Frontier 推进记录

- FR-001（C-01 adb device offline）：depth 1→1（blocked，owner 已处置但 Issue 未关闭），verification_status 仍 needs-device-validation，handoff 指向 human（需执行关闭）
- FR-002（tools/adi analyze 错误备案）：depth 1→1（target=1 记录级已达），verification_status in-progress，无需深挖

## 今日深度锚点文件

| 文件 | 追踪路径 | 结论 |
|------|---------|------|
| `search_screen.dart:61-90` | `_search` → 串行 `await repo.documentPathFor(d.id)` for 循环 | F-2026-09-19-01 Watch |
| `file_repository.dart:300-310` | `searchDocuments` → `_readAll()` 全量加载后过滤 | F-2026-09-19-02 Watch |
| `file_repository.dart:110-126` | `_readAll` → 遍历目录 + 逐文件 `_readDecoded` | #247 同类架构限制 |
| `file_repository.dart:170-202` | `writeDocument` → P0-2 encoding 声明保持逻辑 | ✅ 正确，测试 8/8 通过 |
| `atomic_write.dart:37-63` | `atomicWrite` → String 版（utf8 薄封装） | ✅ TC-ARCH-7 合规（102 行） |
| `editor_export_actions.dart:84-141` | `handleExport` → 无 timeout → `runWithGuard` 仅管 state | Issue #248 Confirmed 延续 |
