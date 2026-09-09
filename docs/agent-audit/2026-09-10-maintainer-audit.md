# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-10（本地 UTC+8）· 触发：schedule cron 01:23
> HEAD: 2b1d7dd（chore(agent): daily maintainer audit 2026-09-09）

## Repository Health

Commit: `2b1d7dd`（chore(agent): daily maintainer audit 2026-09-09）
Version: v0.1.1+2（pubspec: 0.1.1+2；kAppVersion 硬编码 0.1.0+1 → Issue #238）
CI: ⏳ 本次 maintainer run #34397597774 in_progress（北京时间 03:51 触发）；主 CI 无近期 push；Issue #263 跟踪 adb device offline 阻塞 C-01 E2E
Tests: ✅ 架构守门 75 passed, 6 skipped（provider_uniqueness_test 6 skip 均为过时消息）；parser+error 子集 74 passed
Build: ✅ apk + web 构建成功（C-01 第九轮 build 阶段通过）
Golden failures: ✅ 0
flutter analyze lib/: 0 errors, 0 warnings, 33 info-level issues（deprecated_member_use + prefer_const_constructors 等）
flutter analyze tools/: 587 errors（tools/adi/test/import_zip_test.dart 被 Flutter 分析器解析，属已知配置问题，不在 lib/ 内）
无新产品代码变更（自 09-05 C-01 PR #261/#262 合入后，仅 audit 文档提交）
Provider 重复定义现状（本次新核查）：
- ✅ sharedPreferencesProvider：仅定义于 editor_providers.dart:7（治理轮已修复）
- ✅ darkModeProvider：仅定义于 editor_providers.dart:63（治理轮已修复）
- ✅ previewModeProvider：仅定义于 editor_providers.dart:67（治理轮已修复）
- ❌ documentsProvider：重复定义（providers.dart:12 + domain/providers/document_provider.dart:9）
- ❌ isExportingProvider：三重重复（editor_providers.dart:69 + domain/providers/editor_provider.dart:11 + providers.dart:89）
- ❌ editorContentProvider：重复定义（editor_providers.dart:71 + providers.dart:92）

---

## New Findings

### F-2026-09-10-01

Category: test-gap
Severity: P2
Confidence: High
Status: NEW

Summary: `provider_uniqueness_test.dart` 6 个 skip 中有 3 条已过时——sharedPreferencesProvider/darkModeProvider/previewModeProvider 三 Provider 已于 2026-08-25 治理轮收敛至 editor_providers.dart 单一定义，但测试 skip 仍写「Known issue: 两文件重复定义」

Evidence: `flutter_app/test/architecture/provider_uniqueness_test.dart:19`（sharedPreferencesProvider skip 消息）、`:24`（darkModeProvider skip）、`:41`（previewModeProvider skip）；grep 确认这三个 Provider 现仅存在于 editor_providers.dart（行 7/63/67）；但 documentsProvider/isExportingProvider/editorContentProvider 仍有重复，对应 skip 消息属实

Impact: 3 个已修复的 TC-ARCH-6 测试被静默跳过，覆盖率被低估；后续开发者运行该测试可能误以为重复定义 bug 仍未解决

Recommendation: Create Issue
Related Issue: N/A（本次新建，与 F-2026-09-10-02 关联但独立）

### F-2026-09-10-02

Category: architecture
Severity: P2
Confidence: High
Status: NEW

Summary: 3 个 Provider 仍存在重复定义（TC-ARCH-6 守门失败），违反 ADR-0002 §3.2 + AGENTS.md §6.1 #2

Evidence:
- `documentsProvider`: `flutter_app/lib/providers/providers.dart:12` + `flutter_app/lib/domain/providers/document_provider.dart:9`
- `isExportingProvider`: `flutter_app/lib/providers/editor_providers.dart:69` + `flutter_app/lib/domain/providers/editor_provider.dart:11` + `flutter_app/lib/providers/providers.dart:89`
- `editorContentProvider`: `flutter_app/lib/providers/editor_providers.dart:71` + `flutter_app/lib/providers/providers.dart:92`

Impact: TC-ARCH-6 守门测试因 skip 无法捕获；同名 Provider 最后定义优先语义依赖 Flutter 内部行为，不保证跨版本稳定；违反 AGENTS.md §6.1 #2 铁律

Recommendation: Create Issue
Related Issue: N/A（本次新建）

---

## Existing Issue Updates

### Issue #263

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新代码触及 CI runner 配置；C-01 第 9-10 轮（#261/#262）延续同一故障模式——adb device offline；主 CI 近期无新 push，Issue 仍开放待 Human Owner 决策
Next Step: 等待 Human Owner 决策

### Issue #245

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无新代码触及 LiveEditingState.wordCount / InMemoryDocumentEditor O(n²) 路径
Next Step: 待 Phase 4

### Issue #216

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新代码触及 formula/mermaid renderer 渲染路径
Next Step: 等待产品侧复现补充

---

## Ecosystem Findings

### E-2026-09-10-01

Topic: GitHub Actions Node.js 20 退役
Current Solution: tafcm-maintainer.yml 已使用 actions/setup-node@v4 + node-version: 22（已就绪）；主 CI 通过 ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION 过渡期兼容
Alternative: 待 subosito/flutter-action 发布 Node 24 原生支持后移除环境变量 workaround
Comparison: Node.js 20 已于 2026-09-16 正式退役；maintainer workflow 已迁移至 Node 22 不受影响
Recommendation: INVESTIGATE
Decision: no

---

## Pending Decisions

- [ ] Issue #263 是否进入下周修复？（关联：F-2026-09-07-01；建议：进入，阻塞 E2E 自动化）
- [ ] C-01 实验是否继续投入？（关联：F-2026-09-07-01；建议：暂停，等待 #263 决策）
- [ ] domain/providers/document_provider.dart 死代码 + documentsProvider 重复定义清理优先级？（关联：F-2026-09-08-01 / F-2026-09-10-02；建议：P2，空档期一并处理）
- [ ] provider_uniqueness_test.dart 过时 skip 消息是否更新？（关联：F-2026-09-10-01；建议：P2，同步 F-2026-09-10-02 修复一并处理）

---

## Depth Anchor — 当日深读记录

### 深读 1：Provider 重复定义全量核查（F-2026-09-10-01/02 根因追查）

追踪路径：
```
flutter_app/test/architecture/provider_uniqueness_test.dart
  → _grepLib(RegExp) 扫描 lib/ 下所有 .dart 文件
    → 匹配模式: <ProviderName>\s*=
    → 发现: 6 个 test case 全部 skip（已知问题）
      → 实际 grep 结果（本日核查）：
        sharedPreferencesProvider: 1 hit (editor_providers.dart:7) ✅
        darkModeProvider: 1 hit (editor_providers.dart:63) ✅
        previewModeProvider: 1 hit (editor_providers.dart:67) ✅
        documentsProvider: 2 hits (providers.dart:12 + document_provider.dart:9) ❌
        isExportingProvider: 3 hits (editor_providers.dart:69 + editor_provider.dart:11 + providers.dart:89) ❌
        editorContentProvider: 2 hits (editor_providers.dart:71 + providers.dart:92) ❌
```

关键发现：
- 2026-08-25 治理轮（PR #167-#172）修复了 sharedPreferencesProvider / darkModeProvider 重复定义，但未更新 provider_uniqueness_test.dart 的 skip 消息
- previewModeProvider 同样在治理轮中从 providers.dart 移除，skip 消息未更新
- documentsProvider / isExportingProvider / editorContentProvider 的重复定义仍未修复
- isExportingProvider 三重重复最为严重，Riverpod 运行时取最后定义，行为不可预测
- TC-ARCH-6 守门测试设计意图是捕捉重复定义，但因 skip 永久失效，失去守门价值

### 深读 2：LiveEditingState O(n²) 路径确认（Issue #245 延续）

追踪路径：
```
editor_status_bar.dart:68 展示 wordCount
  → LiveEditingState.wordCount（live_editing_state.dart:46-52）
    → for (final id in _editor.allIds)   # O(n) 遍历
      → sourceOf(id)（:32）
        → _liveSources[id] ?? _editor.sourceOf(id)
          → _editor.sourceOf(id)（in_memory_document_editor.dart:206-212）
            → getBlock(id)（:72-77）  # O(n) 线性扫描 _blocks List
```

复杂度分析：
- wordCount: O(n) × O(n) = O(n²)
- isDirty（:60-67）: O(n) × O(n) = O(n²)
- 每次按键触发 notifyListeners() → isDirty + wordCount 双 O(n²) 计算
- n=500 blocks → ~250,000 次比较/次按键；n=2000 → ~4,000,000

关键发现：
- InMemoryDocumentEditor.getBlock() 使用线性扫描而非 Map（:72-77），是 O(n) 根因
- LiveEditingState 注释（:56-59）已承认此问题，并给出优化方向：「脏 block 集合」仅增量维护差异
- Issue #245 根因已 Confirmed：需要为 InMemoryDocumentEditor 引入 _blockMap: Map<BlockId, _Entry> 索引

---

## Frontier Progress

| Entry | 昨日 depth | 今日 depth | 变化 |
|-------|-----------|-----------|------|
| FR-001 | current:1 / target:3 (blocked) | current:1 / target:3 (blocked) | 无进展；adb device offline 阻塞仍待 #263 决策 |
| FR-002 | current:1 / target:1 (cooling) | current:1 / target:1 (cooling) | 无代码变化，维持冷却 |

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

**结论**：第 3 轮（#256）曾通过，但第 5/7/9/10 轮均因 adb: device offline 失败。代码变更未触及 emulator 启动/连接逻辑，根因在 CI runner 基础设施层。

**Depth progress**: N+1（smoke 链路曾通）→ blocked（adb device offline，基础设施问题）
**Next depth target**: 等待 #263 决策（是否切换 runner 类型 / 添加诊断 dump）
