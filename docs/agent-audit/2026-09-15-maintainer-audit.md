# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-15（本地 UTC+8）· 触发：schedule / workflow_dispatch

## Repository Health

Commit: `2b8ca8c`（chore(agent): daily maintainer audit 2026-09-13 corrected format）
Version: v0.1.1+2（pubspec.yaml）/ ⚠️ kAppVersion 仍为 0.1.0+1（main.dart:24，Issue #238 未修复）
CI: ✅ 主干 CI 全绿（最近成功 run：PR #286 全部 11 项 check pass；❌ 历史 run #3465459/#3467842/#3468148/#3477802 已在后续提交中修复或为 maintainer 自身 CI 故障）
Tests: ✅ 架构测试 81/81 通过（provider_uniqueness_test 已取消 skip，PR #282）；✅ perf ratchet 4/4 通过
Analyze: ✅ flutter_app/lib/ + flutter_app/test/ 0 errors，0 warnings；⚠️ tools/adi/test/import_zip_test.dart 588 个 pre-existing analyze 错误（F-2026-09-05-02，不影响产品）
Build: ✅ apk + web 构建成功
Open PRs: #286（feat: P0-1 搜索接线 + P0-2 编码指定）—— OPEN，MERGEABLE，全部 CI check pass

## Significant Changes Since Last Audit（2026-09-13）

昨日至今（2b8ca8c 相对 2ee0878）仅 1 个 commit：`2b8ca8c chore(agent): daily maintainer audit 2026-09-13 (corrected format)` —— 仅修正上一份 Audit 的格式问题，无产品代码变更。

自 2026-09-12 以来合入的产品 PR：
- #285 docs(positioning): 产品定位收敛（ADR-0033 新增）
- #284 fix(mermaid): 图表随 Dark/Sepia 主题切换渲染
- #283 fix(home): 移除首页空壳搜索按钮
- #282 refactor(providers): 消除 Provider 重复定义（关闭 Issue #266）
- #281 test(architecture): TC-ARCH-6 unskip 3 个 Provider 唯一性测试
- #280 perf(editor): wordCount 增量维护，消除 O(n²)
- #279 fix(editor): 外部 URI 打开文档进入只读查看模式（关闭 Issue #240）
- #277 fix(exporter): 公式导出空白修复（SVG defs/use 内联）

## New Findings

No significant findings.

## Existing Issue Updates

### Issue #238（kAppVersion 漂移）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: `flutter_app/lib/main.dart:24` `const String kAppVersion = '0.1.0+1';` vs `pubspec.yaml:4` `version: 0.1.1+2`，漂移持续未修复。一行修复：将 `'0.1.0+1'` 改为 `'0.1.1+2'`。
Next Step: 建议 Human Owner 审阅 PR #286 时顺手提，或单独一行 PR

### Issue #249（autosave 每次全量序列化）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点验证通过。`editor_screen.dart:88-103` `_scheduleAutosave` 仍为 500ms debounce + 整读整写全文；`AutosaveService`（debounce=1.5s + 指数退避）仅被新 WYSIWYG editor_page.dart 使用，legacy editor_screen.dart 未接入。PR #280 修复了 wordCount O(n²)，未触及此路径。
Next Step: 待 Phase 4 编辑器重构时统一 autosave 路径

### Issue #250（Word 导出串行渲染）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点验证通过。`word_exporter.dart:114-134` Mermaid 渲染为串行 `for` + `await`；公式预渲染 `FormulaPdfRenderer.preRenderAll` 内部用 `_maxConcurrent=4` 分批并发，但 Mermaid 未复用该机制。
Next Step: 待立项优化（Future.wait + _maxConcurrent 控制）

### Issue #263（adb device offline）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: CI #34778022476（2026-09-13 maintainer run）自身也因 Email delivery 步骤失败（非产品 bug）。Android emulator integration job 仍受 adb offline 影响；smoke 测试已通过 10+ 轮。
Next Step: 等待 Human Owner 决策是否切换 runner 类型

### Issue #266（Provider 重复定义）

Status: RESOLVED
Root Cause: Confirmed
New Evidence: PR #282（7f26ac3）已合入，消除了 3 个 Provider 重复定义，删除 2 个死文件。`providers.dart` 现在仅保留 document 相关 Provider，theme/provider 权威定义收敛到 `editor_providers.dart`。TC-ARCH-6 unskip 测试（PR #281）全部通过。
Next Step: 无后续动作

### Issue #234（导出公式可见性测试缺口）

Status: UNCHANGED
Root Cause: Likely
New Evidence: 昨日已记录，今日无新证据。
Next Step: 补测试：导出 PNG 非透明 + 真实 MathJax SVG 渲染校验

### Issue #248（新编辑器导出路径无全局超时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度锚点验证通过。`export_service.dart:524-525` 已有 `_shareTimeout=60s` / `_exportTimeout=120s`，line 589 `bytes = await exporter(markdown).timeout(_exportTimeout)`。Legacy editor_screen.dart 走同一 ExportService 路径，超时已覆盖。Issue 描述可能过时，建议 Human Owner 确认是否关闭。
Next Step: 建议 Human Owner 确认是否关闭为 WontFix

## Ecosystem Findings

### E-2026-09-15-01 — Node.js 20 弃用 deadline 逼近

Topic: GitHub Actions runner 兼容性
Current Solution: `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: true` workaround（ci.yml + tafcm-maintainer.yml 均有设置）
Alternative: 迁移至 Node 22 action
Comparison: Node 22 与 Node 20 在 checkout/setup-node 上有 minor API 差异；当前 CI 全部通过说明 workaround 仍然有效；GitHub 已于 2025-09-19 正式弃用 Node 20，宽限期预计至 2026 年底；迁移成本中等（需验证 flutter 缓存 key 兼容性）
Recommendation: INVESTIGATE
Decision: no

## Pending Decisions

- [ ] Issue #238 kAppVersion 同步（main.dart:24 `'0.1.0+1'` → `'0.1.1+2'`）—— 一行修复，建议顺手提
- [ ] Issue #248 export timeout 是否关闭为 WontFix —— 代码已覆盖，Issue 描述过时
- [ ] PR #286 合并（feat: P0-1 搜索接线 + P0-2 编码指定）—— Human Owner 审阅后执行
- [ ] E-2026-09-15-01 Node.js 22 迁移 —— 建议近期内处理（宽限期到期前）
- [ ] perf_baseline.json 下调（4 项指标显著优于基线）—— 人工确认后更新
