# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-12（本地 UTC+8）· 触发：schedule / workflow_dispatch

## Repository Health

Commit: `d7aefd3`（PR #271 — Test/system upgrade wave1，含 PR #270/#269）
Version: v0.1.1（pubspec.yaml）
CI: ⚠️ 部分绿（Analyze ✅ / Test ✅ / Golden ✅ / Build-android ✅ / Build-web ✅；Android 模拟器集成 ❌ — adb device offline 同 #263）
Tests: ✅ 1883 passed，~18 skipped（`flutter test` 全量）；`flutter analyze --no-fatal-infos --fatal-warnings flutter_app/lib/` = 0 errors，0 warnings
Build: ✅ apk + web 构建成功

## New Findings

### F-2026-09-12-01 — TXT 导出 BoldElement 静默丢失

Category: bug
Severity: P2
Confidence: High
Status: NEW

Summary: `text_exporter.dart::_inlineToText` 缺少 `BoldElement` 分支，导致纯文本导出中所有加粗内容被完全丢弃（而非保留文字）。斜体/删除线正常递归 children，LinkElement/InlineCodeElement 正常保留。属于"退化白名单"之外的意外回归。

Evidence:
- `flutter_app/lib/domain/services/exporters/text_exporter.dart:151-170` — `_inlineToText` switch 无 BoldElement 分支
- `flutter_app/test/export/export_semantic_snapshot_test.dart:157-159` — 测试注释明确标注："加粗：**当前 TXT 导出丢失全部内容**（`_inlineToText` 无 BoldElement 分支）——这是 U9 抓到的真实缺陷，已上报，待独立修复 PR 后把 bold 计数移入恒等断言。"
- U9 测试当前将 bold 计数排除在恒等断言之外（降级白名单），说明作者已知并主动绕开

Impact: 用户导出 TXT 时加粗格式完全丢失（内容为空），其他导出格式（HTML/PDF/Word）不受影响（均有对应分支）

Recommendation: 补一行 `else if (c is BoldElement) { buf.write(_inlineToText(c.children)); }`，与 ItalicElement/StrikethroughElement 对称；同时把 U9 的白名单移除并加入恒等断言。关联 Issue 待建。

Related Issue: N/A（测试注释说"已上报"但未在当前 open issues 中找到匹配项，建议 Human Owner 确认后创建）

## Existing Issue Updates

### Issue #263（adb device offline）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: CI #34610604923（2026-09-11 14:31）再次复现：adb exit code 1 连续 10+ 次，Android Device Integration (emulator) job 以 exit code 124 超时失败。Test / Golden / Build 三个 job 全部通过（1883+ tests）。与 PR #269/#270/#271 无关，纯基础设施问题。
Next Step: 等待 Human Owner 决策是否切换 runner 类型或添加 adb logcat dump

### Issue #265 / #266（Provider 重复定义 + skip 消息过时）

Status: UNCHANGED
Root Cause: Likely
New Evidence: 本次 wave1 无新增 Provider，重复定义未扩大；architecture test skip 数量维持 ~6 个（同 9/11）
Next Step: 与 domain/providers/ 死代码清理一并处理（见 Pending Decisions）

## Ecosystem Findings

### E-2026-09-12-01 — Node.js 20 弃用 deadline 临近

Topic: GitHub Actions runner 兼容性
Current Solution: `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: true` workaround（ci.yml）
Deadline: 2026-09-16（4 天后）
Alternative: 迁移至 Node 22 action
Comparison: Node 22 与 Node 20 在 checkout/setup-node 上有 minor API 差异，需验证 flutter 缓存 key 兼容性
Recommendation: INVESTIGATE
Decision: no

### E-2026-09-12-02 — ADR-0032 Export Assembly Finite Guarantee（Proposed 状态）

Topic: 导出死循环防护架构
Current Solution: 无（ADR-0032 为新提案，尚未实施）
Alternative: 维持现状（pdf.addPage 无限循环风险未解除）
Comparison: ADR-0032 提出 watchdog 机制限制 pdf.addPage 调用次数，从架构层保障导出终态性
Recommendation: KEEP
Decision: no
Related Issue: N/A（ADR 类决策，不创建 Issue）

## Pending Decisions

- [ ] F-2026-09-12-01（TXT BoldElement 丢失）是否进入下周修复？（关联：text_exporter.dart:151；建议：进入，P2，一行修复）
- [ ] #263 adb device offline 是否继续投入？（关联：FR-001；建议：暂停人工投入，等待 runner 基础设施自愈或 owner 决策）
- [ ] E-2026-09-12-01（Node.js 20 弃用）主 CI workaround 是否需要提前替换？（建议：5 天内验证 Node 22 兼容性）
- [ ] domain/providers/ 死代码 + Provider 重复定义清理优先级？（关联：F-2026-09-08-01 / F-2026-09-10-02；建议：P2，空档期一并清理）
- [ ] ADR-0032 是否推进至 Accepted？（关联：E-2026-09-12-02；建议：接受，导出有限性保证属 Phase 3 收尾关键保障）
