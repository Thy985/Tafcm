# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-08（本地 UTC+8）· 触发：schedule cron 01:23
> HEAD: f939e5c（与 09-07 同 commit；无新产品代码变更）

## Repository Health

Commit: `f939e5c`（chore(agent): daily maintainer audit 2026-09-07）
Version: v0.1.1+2
CI: ⏳ 本次 maintainer run #34160239395 in_progress（北京时间 04:44 触发）；主 CI #33953543937 failure（adb device offline，Issue #263）
Tests: ✅ 架构守门 75 passed, 6 skipped（provider_uniqueness_test 多项 skip 为已知问题）
Build: ✅ apk + web 构建成功（C-01 第九轮 build 阶段通过）
Golden failures: ✅ 0
flutter analyze lib/: 0 errors, 0 warnings, 33 info-level issues（deprecated_member_use）
Provider 重复定义修复验证: ✅ `sharedPreferencesProvider` / `darkModeProvider` 现仅定义于 `editor_providers.dart`（grep 确认）
缺失 blob: ✅ 已解决（SHA 23a03e19、3298c833 均验证通过）

---

## New Findings

### F-2026-09-08-01

Category: architecture
Severity: P2
Confidence: High
Status: NEW

Summary: `domain/providers/document_provider.dart` 为死代码，仍定义 `documentsProvider` / `currentDocumentProvider`（使用已废弃 `DocumentService`，违反 ADR-0003），与 `providers/providers.dart` 形成 Provider 重复定义冲突

Evidence: `flutter_app/lib/domain/providers/document_provider.dart:9`（`documentsProvider` 定义）、`:14`（`currentDocumentProvider` 定义）、`:5-6`（`DocumentService` 注入）；`flutter_app/lib/core/services/document_service.dart:9-11`（`@Deprecated` 注解："Phase 1 存储统一后由 FileRepository 取代"）；`grep -rn "import.*document_provider" flutter_app/lib/` 返回 0 结果（无 lib/ 代码 import 本文件）；`flutter_app/test/architecture/provider_uniqueness_test.dart:30` skip 消息引用此问题

Impact: 死代码增加维护负担；`documentsProvider` 同名冲突使 TC-ARCH-6 测试无法激活；`DocumentService` 指向旧 JSON 存储路径（`formula_fix_documents.json`），与 ADR-0003 .md 单一真相源相悖，可能误导后续协作者

Recommendation: Investigate
Related Issue: N/A（本次新建）

### F-2026-09-08-02

Category: test-gap
Severity: P3
Confidence: High
Status: NEW

Summary: `provider_uniqueness_test.dart` 中 `sharedPreferencesProvider` / `darkModeProvider` 的 skip 消息已过时——代码侧已由 PR #167-#172（2026-08-25 治理轮）收敛至 `editor_providers.dart` 单一定义，但测试 skip 仍引用"重复定义"旧状态

Evidence: `flutter_app/test/architecture/provider_uniqueness_test.dart:17-19`（`sharedPreferencesProvider` skip: "Known issue: providers/providers.dart 与 editor_providers.dart 重复定义"）；`:22-24`（`darkModeProvider` skip: "Known issue: 同上"）；`grep -rn "sharedPreferencesProvider\s*=" flutter_app/lib/` 仅命中 `editor_providers.dart:7`；`:grep -rn "darkModeProvider\s*=" flutter_app/lib/` 仅命中 `editor_providers.dart:63`

Impact: skip 测试隐藏了真实通过状态，使 TC-ARCH-6 覆盖率被低估；后续开发者可能误以为重复定义问题尚未解决

Recommendation: Investigate
Related Issue: N/A

---

## Existing Issue Updates

### Issue #263

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新代码触及 CI runner 配置；C-01 第 9-10 轮（#261/#262）延续同一故障模式——adb device offline；Issue 已创建但待 Human Owner 决策是否切换 runner 类型或添加 adb logcat dump
Next Step: 等待 Human Owner 决策

### Issue #245

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无新代码触及 `LiveEditingState.wordCount` / `sourceOf` 路径
Next Step: 待 Phase 4

### Issue #216

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新证据
Next Step: 等待产品侧复现补充

---

## Ecosystem Findings

### E-2026-09-08-01

Topic: GitHub Actions Node.js 20 弃用
Current Solution: `tafcm-maintainer.yml` 已使用 `actions/setup-node@v4` + `node-version: 22`；主 CI (`ci.yml`) 主要 job 跑 Flutter/Java/Gradle 任务（不直接依赖 Node.js action runtime）
Alternative: 检查 `actions/cache@v4` / `actions/checkout@v4` 等内置 action 的 Node.js 版本需求
Comparison: Node.js 20 将于 2026-09-16 被 runner 移除（距今日约 8 天）；`tafcm-maintainer.yml` 已迁移至 Node 22；主 CI 的 Node.js action 均在 v4 系列，兼容性待验证
Recommendation: INVESTIGATE
Decision: no

---

## Pending Decisions

- [ ] Issue #263 是否进入下周修复？（关联：F-2026-09-07-01；建议：进入，阻塞 E2E 自动化）
- [ ] C-01 实验是否继续投入？（关联：F-2026-09-07-01；建议：暂停，等待 #263 决策）
- [ ] `domain/providers/document_provider.dart` 死代码清理优先级？（关联：F-2026-09-08-01；建议：低优先级 P2，可在空档期一并清理）

---

## Depth Anchor — 当日深读记录

### 深读 1：AutosaveService 事务与并发保护

**追踪路径**：
```
editor_page.dart:_initAutosave()
  → AutosaveService(_source, _save, debounce=1.5s)
    → DirtyStateSource.dirtyChanges stream（脏状态翻转触发）
    → _schedule() / _scheduleRetry()（Timer 调度）
    → _fire() → _inflight guard（并发保存串行化）
    → _saveOnce() → _save() 回调 → document_provider.dart:_save()
      → File.writeAsString（整文档序列化）
      → DirtyStateSource.markSaved()（重置脏标记）
```

**关键发现**：
- `AutosaveService` 设计良好（ADR-0013）：`_inflight` future 保证并发保存串行化
- 失败指数退避重试（`_scheduleRetry()`，封顶 60s）避免磁盘满时风暴
- `save` 回调在起始同步捕获文档快照（避免写盘期间实时编辑被覆盖）
- 写盘完成后检查 `_source.isDirty` 判断写盘期间是否有新编辑（不误 markSaved）
- **Issue #249 根因延续**：整文档序列化，大文档（>500 block）保存延迟可能 >1s

### 深读 2：Export Pipeline 并发渲染机制（续 09-07）

**追踪路径**：
```
export_service.dart:runExport()
  → formula_pdf_renderer.dart:renderFormulas()
    → formula_svg_service.dart:renderToSvg()     # _maxConcurrent=4, _waiting/_active 队列
      → _dispatchWaiting()                        # D3 状态机：waiting→active→complete
      → _consecutiveTimeouts 连续超时保护（阈值 3）
    → mermaid_service.dart:renderToSvg()          # 共享同一 WebView 实例
  → formula_pdf_renderer.dart:generatePdf()       # _maxConcurrent=4 并发公式渲染
  → word_exporter.dart / pdf_exporter.dart        # 串行写入
```

**关键发现**：
- `FormulaSvgService._consecutiveTimeouts` 正确实现（PR-C）：成功渲染时重置为 0，连续 3 次超时才触发 `MermaidService.resetRenderer()`（避免单公式超时级联清空整批）
- WebView 崩溃恢复机制存在于 `MermaidService`（`rendererStateSnapshot` + `_crashRecovery`），但 `formula_svg_service.dart` 无对等保护（依赖共享 WebView）
- `MermaidService._controller` 静态 singleton 与 `FormulaSvgService` 共享同一 WebView——单点故障风险

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

**结论**：第 3 轮（#256）曾通过，但第 5/7/9/10 轮均因 `adb: device offline` 失败。代码变更未触及 emulator 启动/连接逻辑，根因在 CI runner 基础设施层。

**Depth progress**: N+1（smoke 链路曾通）→ blocked（adb device offline，基础设施问题）
**Next depth target**: 等待 #263 决策（是否切换 runner 类型 / 添加诊断 dump）
