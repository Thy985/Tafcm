# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-09（本地 UTC+8）· 触发：schedule cron 01:23
> HEAD: 2468de3（chore(agent): daily maintainer audit 2026-09-08）

## Repository Health

Commit: `2468de3`（chore(agent): daily maintainer audit 2026-09-08）
Version: v0.1.1+2
CI: ⚠️ 主 CI #33953543937 failure（adb device offline，Issue #263）；Maintainer run #34272013866 in_progress
Tests: ✅ 架构守门 75 passed, 6 skipped；parser+error 子集 149 passed, 6 skipped
Build: ✅ apk + web 构建成功（C-01 第九轮 build 阶段通过）
Golden failures: ✅ 0
flutter analyze lib/: 0 errors, 0 warnings, 33 info-level issues（deprecated_member_use）
无新产品代码变更（自 09-08 audit commit 起仅 audit 文档提交）

---

## New Findings

No significant findings.

## Existing Issue Updates

### Issue #263

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新代码触及 CI runner 配置；C-01 第 9-10 轮（#261/#262）仍因 adb device offline 失败；Issue 已创建但待 Human Owner 决策
Next Step: 等待 Human Owner 决策

### Issue #245

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 今日深读确认：`live_editing_state.dart:46-52`（wordCount getter）对每个 block id 调用 sourceOf(id)；sourceOf 内部 _liveSources[id] ?? _editor.sourceOf(id)（:32）；_editor.sourceOf(id)（in_memory_document_editor.dart:206-212）调用 getBlock(id) 做线性扫描 _blocks List（:72-77）。整条路径 O(n²)，每次按键触发 notifyListeners() → isDirty getter（:60-67，同样 O(n²)）→ wordCount getter（同样 O(n²)）→ EditorStatusBar 刷新。
Next Step: 待 Phase 4

### Issue #216

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新代码触及 formula/mermaid renderer 渲染路径
Next Step: 等待产品侧复现补充

---

## Ecosystem Findings

### E-2026-09-09-01

Topic: GitHub Actions Node.js 20 弃用
Current Solution: tafcm-maintainer.yml 已使用 actions/setup-node@v4 + node-version: 22；主 CI (ci.yml) 设置 ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: true 过渡期兼容（flutter-action v2.x 尚未完全适配 Node 24）
Alternative: 等待 subosito/flutter-action 发布 Node 24 原生支持后移除 workaround
Comparison: Node.js 20 将于 2026-09-16 被 runner 移除（距今日 7 天）；maintainer workflow 已就绪（Node 22）；主 CI 通过环境变量 workaround 兼容，风险可控
Recommendation: INVESTIGATE
Decision: no

---

## Pending Decisions

- [ ] Issue #263 是否进入下周修复？（关联：F-2026-09-07-01；建议：进入，阻塞 E2E 自动化）
- [ ] C-01 实验是否继续投入？（关联：F-2026-09-07-01；建议：暂停，等待 #263 决策）
- [ ] domain/providers/document_provider.dart 死代码清理优先级？（关联：F-2026-09-08-01；建议：低优先级 P2，可在空档期一并清理）

---

## Depth Anchor — 当日深读记录

### 深读 1：LiveEditingState O(n²) 路径确认（Issue #245 根因闭环）

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
- isDirty（:60-67）: O(n) × O(n) = O(n²)（同样调用 _editor.sourceOf(id)）
- 每次按键触发 notifyListeners() → isDirty + wordCount 双 O(n²) 计算
- n=500 blocks → ~250,000 次比较/次按键；n=2000 → ~4,000,000

关键发现：
- InMemoryDocumentEditor.getBlock() 使用线性扫描而非 Map（:72-77），是 O(n) 根因
- LiveEditingState 注释（:56-59）已承认此问题："预期文档规模下开销可忽略；若未来出现大文档 TTI 退化，可优化为「脏 block 集合」仅增量维护差异"
- Issue #245 根因已 Confirmed：需要为 InMemoryDocumentEditor 引入 _blockMap: Map<BlockId, _Entry> 索引，使 getBlock/sourceOf 降为 O(1)

### 深读 2：AutosaveService 事务与并发保护（续 09-08）

追踪路径：
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

关键发现：
- AutosaveService 设计良好（ADR-0013）：_inflight future 保证并发保存串行化
- 失败指数退避重试（_scheduleRetry()，封顶 60s）避免磁盘满时风暴
- Issue #249 延续：整文档序列化，大文档（>500 block）保存延迟可能 >1s
- save 回调在起始同步捕获文档快照（避免写盘期间实时编辑被覆盖）——正确实现

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

结论：第 3 轮（#256）曾通过，但第 5/7/9/10 轮均因 adb: device offline 失败。代码变更未触及 emulator 启动/连接逻辑，根因在 CI runner 基础设施层。

Depth progress: N+1（smoke 链路曾通）→ blocked（adb device offline，基础设施问题）
Next depth target: 等待 #263 决策（是否切换 runner 类型 / 添加诊断 dump）
