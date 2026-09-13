# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-13（本地 UTC+8）· 触发：schedule / workflow_dispatch

## Repository Health

Commit: `2ee0878`（chore(agent): daily maintainer audit 2026-09-13）
Version: v0.1.1（pubspec.yaml: 0.1.1+2；⚠️ kAppVersion 仍为 0.1.0+1，Issue #238 未修复）
CI: ✅ 全绿（main 主干连续 3 次 success；当前 Maintainer run #34778022476 in progress）
Tests: ✅ 架构测试 81/81 通过；✅ perf ratchet 4/4 通过（全部显著优于基线）
Analyze: ✅ 0 errors，0 warnings（flutter_app/lib/ + flutter_app/test/）
Build: ✅ apk + web 构建成功（昨日验证，今日无代码变更）

## Significant Changes Since Last Audit（2026-09-12）

昨日至今（2ee0878 相对 d7aefd3）共合入 12 个 PR，以下按影响分类：

### 已关闭的 Issues（PR 合入后自动关闭）

| Issue | 标题 | 关闭 PR |
|-------|------|---------|
| #273 | TXT 导出 BoldElement 静默丢失 | #272 Wave2+3 |
| #266 | Provider 重复定义 | #282 |
| #265 | skip 消息过时 | #281 |
| #240 | 外部 URI 打开文档静默丢内容 | #279 |

### 性能显著改善（perf ratchet 全部 < 70% baseline）

| 指标 | 基线 | 今日中位数 |
|------|------|----------|
| parser_parse_1000_lines | 38.12ms | 24.00ms |
| block_toelement_typical | 0.071ms | 0.04ms |
| fulldoc_parse_1000_blocks | 220.0ms | 46.00ms |
| list_documents_1000_files | 1731.72ms | 967.50ms |

主要贡献：PR #280（wordCount 增量维护，消除按键 O(n²)）+ PR #274（perf ratchet 门禁上线）。

### 待合并 PR

- **#286** feat: P0-1 全局搜索接线 + P0-2 编码手动指定与声明保持 — OPEN，MERGEABLE

## New Findings

No significant findings.

## Existing Issue Updates

### Issue #249（autosave 每次全量序列化）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: `editor_screen.dart:88-103` 有私有 `_scheduleAutosave` 方法，500ms debounce 后调用 `fileRepository.writeDocument(path, title, content)` 完整序列化全文。`AutosaveService`（`autosave_service.dart`）已存在并供 `editor_page.dart`（新 WYSIWYG 编辑器）使用（debounce=1.5s + 指数退避重试），但 legacy `editor_screen.dart` 未接入。PR #280 修复了 wordCount O(n²)，但未触及 `_scheduleAutosave` 路径。
Next Step: 待 Phase 4 编辑器重构时统一 autosave 路径，或显式将 `editor_screen.dart` 的 `_scheduleAutosave` 迁移到 `AutosaveService`

### Issue #250（Word 导出串行渲染）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: depth anchor 已验证。`word_exporter.dart:152-163` Mermaid 渲染为串行 `for` + `await`；`word_exporter.dart:93-101` 公式预渲染调 `FormulaPdfRenderer.preRenderAll`，内部用 `_maxConcurrent=4` 分批并发。结论：公式并发，Mermaid 串行。
Next Step: 待立项优化（改为 Future.wait + _maxConcurrent 控制）

### Issue #248（新编辑器导出路径无全局超时）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: depth anchor 已验证。`export_service.dart:524-525` 已有 `static const _shareTimeout = Duration(seconds: 60); static const _exportTimeout = Duration(seconds: 120);`，line 589 `bytes = await exporter(markdown).timeout(_exportTimeout)`。Issue 描述与代码不符，可能为历史遗留。
Next Step: 建议 Human Owner 确认是否关闭为 WontFix 或补充细节

### Issue #263（adb device offline）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 昨日已记录，今日无新证据；CI 主干全绿（Test/Analyze/Build 均过），仅 Android 模拟器集成 job 受影响。
Next Step: 等待 Human Owner 决策是否切换 runner 类型或添加 adb logcat dump

### Issue #238（kAppVersion 漂移）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: `flutter_app/lib/main.dart:24` `const String kAppVersion = '0.1.0+1';` vs `pubspec.yaml:4` `version: 0.1.1+2`，漂移持续。
Next Step: 一行修复，建议顺手提

### Issue #234（导出公式可见性测试缺口）

Status: UNCHANGED
Root Cause: Likely
New Evidence: 昨日已记录，今日无新证据。
Next Step: 补测试：导出 PNG 非透明 + 真实 MathJax SVG 渲染校验

### Issue #264（外部可借鉴和参考的项目）

Status: UNCHANGED
Root Cause: Unknown
New Evidence: 2026-09-09 创建，今日首次观察。非阻塞项。
Next Step: 归档或关闭，非紧急

## Ecosystem Findings

### E-2026-09-13-01 — Node.js 20 弃用 deadline 已过

Topic: GitHub Actions runner 兼容性
Current Solution: `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: true` workaround（ci.yml）
Alternative: 迁移至 Node 22 action
Comparison: Node 22 与 Node 20 在 checkout/setup-node 上有 minor API 差异，需验证 flutter 缓存 key 兼容性；当前 CI 全部通过说明 workaround 仍然有效
Recommendation: INVESTIGATE
Decision: no

## Pending Decisions

- [ ] PR #286 合并（feat: P0-1 搜索接线 + P0-2 编码指定）—— Human Owner 审阅后执行
- [ ] #249 autosave 路径统一（legacy editor_screen → AutosaveService）—— 待 Phase 4
- [ ] #250 Word 导出 Mermaid 串行渲染优化 —— 待立项
- [ ] #248 export timeout 是否关闭为 WontFix —— Human Owner 确认
- [ ] #238 kAppVersion 同步 —— 一行修复，建议顺手提
- [ ] E-2026-09-13-01 Node.js 22 迁移 —— 建议近期处理
- [ ] perf_baseline.json 下调（4 项指标显著优于基线）—— 人工确认后更新
