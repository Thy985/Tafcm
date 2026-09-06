# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-07（本地 UTC+8）· 触发：schedule cron 01:23

## Repository Health

Commit: `1cbc7c2`（C-01 第九轮，与 09-05 同 commit；无新产品代码变更）
Version: v0.1.1+2
CI: ⚠️ C-01 第九轮 CI #33953543937 failure（adb device offline）；tafcm-maintainer #33986176031 success（audit）+ failure（email 投递失败，已知 recurring）
Tests: ✅ 149 passed, 6 skipped（parser + architecture + error 子集）；全量预计 1700+ 用例
Build: ✅ apk + web 构建成功（C-01 第九轮 build 阶段通过）
Golden failures: ✅ 0（ee76180 已清除，test/golden/failures/ 空目录）
flutter analyze lib/: 33 info-level issues（deprecated_member_use），0 errors，0 warnings
Missing blobs: ✅ 已解决（SHA 23a03e19、3298c833 均 git cat-file -e 验证通过）

---

## New Findings

### F-2026-09-07-01

Category: tech-debt
Severity: P2
Confidence: High
Status: NEW

Summary: C-01 第 9-10 轮仍 fail——adb device offline，emulator 启动后约 44 秒内离线
Evidence: CI run #33953543937（C-01第九轮 on main，push，2026-09-05T07:53:40Z）；`adb -s emulator-5554 shell getprop sys.boot_completed` → `adb: device offline`；build 成功（BEXIT=0）后 44 秒内 emulator 离线
Impact: Phase 3 E2E integration tests 无法在 CI 自动运行；C-01 frontier FR-001 阻塞
Recommendation: Create Issue #263；建议 CI 中添加 adb logcat dump；考虑 ubuntu-latest with KVM 或真机替代方案
Related Issue: #263

### F-2026-09-07-02

Category: architecture
Severity: P3
Confidence: High
Status: RESOLVED

Summary: ADR-0032（audit-frontier incremental）缺失 — 现已合入 main
Evidence: PR #241（44aa8e5，2026-09-03），docs/decisions/ADR/0032-audit-frontier-incremental.md 已存在
Impact: 无（ADR 已补）
Recommendation: 标记 F-2026-09-01-05 为 RESOLVED；更新 FINDINGS.md registry
Related Issue: N/A

---

## Existing Issue Updates

### Issue #233

Status: RESOLVED
Root Cause: Confirmed
New Evidence: ee76180（PR #236，2026-09-02）根治：移除 112 个 golden failures PNG + Guard 放行；test/golden/failures/ 现空（0 文件）；CI golden compare job 已通过（2026-09-05 起）；本 agent 已关闭该 Issue
Next Step: Issue 已关闭

### Issue #263

Status: UPDATED
Root Cause: Hypothesis
New Evidence: CI #33953543937、CI #33950879887 均报 `adb: device offline`；build 成功但 drive 阶段失败；与之前 C-01 轮次（5/7）失败模式相同；本 agent 已创建 Issue #263
Next Step: 等待 Human Owner 决策：是否切换 runner 类型 / 添加 adb logcat dump / 接受 ADR-0022 降级

### Issue #245

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 深度追查确认：`LiveEditingState.wordCount` 对每个 block id 调用 `sourceOf(id)`，`sourceOf` 内部 `getBlock(id)` 线性扫描 `_blocks` List → O(n²)；每次按键触发 `notifyListeners()` → `isDirty` getter 同样 O(n²)；editor_status_bar.dart:68 展示 wordCount 加剧刷新频率
Next Step: 待 Phase 4

### Issue #216

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新代码触及 formula/mermaid renderer 渲染路径
Next Step: 等待产品侧复现补充

---

## Ecosystem Findings

### E-2026-09-07-01

Topic: GitHub Actions Node.js 20 弃用
Current Solution: actions/cache@v4, actions/checkout@v4, actions/setup-java@v4, actions/upload-artifact@v4 均在 Node.js 20 上运行
Alternative: 升级到支持 Node.js 24 的 action 版本，或设置 FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true
Comparison: Node.js 20 将于 2026-09-16 被 runner 移除（距今日 9 天）；当前 action v4 系列部分仍兼容 Node.js 20
Recommendation: INVESTIGATE
Decision: no

---

## Pending Decisions

- [ ] Issue #263 是否进入下周修复？（关联：F-2026-09-07-01；建议：进入，阻塞 E2E 自动化）
- [ ] PR #253（Agent Capability Registry）是否进入审核流程？（关联：N/A；建议：走 normal code review）
- [ ] C-01 实验是否继续投入？（关联：F-2026-09-07-01；建议：暂停，等待 #263 决策）

---

## Depth Anchor — 当日深读记录

### 深读 1：Export Pipeline 并发渲染机制

**追踪路径**：
```
export_service.dart:runExport()
  → formula_pdf_renderer.dart:renderFormulas()
    → formula_svg_service.dart:renderToSvg()     # _maxConcurrent=4, _waiting/_active 队列
    → mermaid_service.dart:renderToSvg()          # _maxConcurrent=4, _waiting/_active 队列
  → formula_pdf_renderer.dart:generatePdf()       # _maxConcurrent=4 并发公式渲染
  → word_exporter.dart / pdf_exporter.dart        # 串行写入
```

**关键发现**：
- `FormulaSvgService._dispatchWaiting()` 实现正确（D4 修复，PR-2）：排队只入 `_waiting`，派发时才入 `_active`，避免 active 膨胀导致 while 条件永久不满足
- `MermaidService` 同样实现 `_maxConcurrent=4` + `_waiting`/`_active` 队列
- `FormulaPdfRenderer._maxConcurrent=4` 控制 PDF 导出时的并发公式渲染数
- **Issue #250 根因**：`_maxConcurrent=4` 对大文档（>50 公式）不够用，但代码逻辑本身无 bug
- WebView 崩溃恢复机制存在于 `MermaidService`（`rendererStateSnapshot` + `_crashRecovery`），但 `formula_svg_service.dart` 无对等保护

### 深读 2：Autosave / Serialization 一致性

**追踪路径**：
```
editor_page.dart:_initAutosave()
  → AutosaveService(_source, _save, debounce=1.5s)
    → DirtyStateSource.dirtyChanges stream（脏状态翻转触发）
    → debounce timer（1.5s 后调用 _save 回调）
    → document_provider.dart:_save()             # 整文档 serialize → File.writeAsString
    → DirtyStateSource.markSaved()                # 重置脏标记
```

**关键发现**：
- `AutosaveService` 设计良好（ADR-0013）：`_inflight` future 保证并发保存串行化，失败指数退避重试
- `LiveEditingState.isDirty` 和 `wordCount` 均为 O(n) 遍历，每次 `notifyListeners()` 触发 → Issue #245 #249 根因
- `_save` 回调是整文档序列化（非增量），大文档（>500 block）保存延迟可能 >1s
- **Issue #249 根因确认**：autosave 每次都整读整写，应优化为增量序列化

---

## C-01 Experiment Status Summary

| 轮次 | PR | 状态 | 关键改动 | CI 结果 |
|------|----|----|---------|---------|
| 1 | #254 | ✅ MERGED | 新增 Android emulator job | —（首跑） |
| 2 | #255 | ✅ MERGED | 修复多 integration 文件单次调用 | timeout + bad window |
| 3 | #256 | ✅ MERGED | 加 working-directory: flutter_app | ✅ SUCCESS（#840） |
| 4 | #257 | ✅ MERGED | 40min timeout + 更多 smoke 用例 | ✅（PR Code Review 通过） |
| 5 | #258 | ✅ MERGED | flutter test 进程 hang 修复（timeout 300s） | adb device offline |
| 7 | #260 | ✅ MERGED | script 压成单行（android-emulator-runner 按行拆分） | adb device offline |
| 9 | #261 | ✅ MERGED | x86_64-only APK（解决大 APK 安装 Broken pipe） | adb device offline |
| 10 | #262 | ✅ MERGED | drive 超时时 dump 日志定位卡点 | adb device offline |

**结论**：第 3 轮（#256）曾通过，但第 5/7/9/10 轮均因 `adb: device offline` 失败。
代码变更未触及 emulator 启动/连接逻辑，根因在 CI runner 基础设施层。

**Depth progress**: N+1（smoke 链路曾通）→ blocked（adb device offline，基础设施问题）
**Next depth target**: 等待 #263 决策（是否切换 runner 类型 / 添加诊断 dump）
