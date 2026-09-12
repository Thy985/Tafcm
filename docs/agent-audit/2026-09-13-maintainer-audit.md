# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-13（本地 UTC+8）· 触发：schedule cron 01:23
> HEAD: `5e7e023`（docs(positioning): 产品定位收敛，#243）
> 仓库：Thy985/Tafcm · 目标分支：main

## Repository Health

Commit: `5e7e023`（docs(positioning): 产品定位收敛——用户侧聚焦 T/F/M，A/C 降级工程差异化 · #243 · PR #285）
Version: v0.1.1+2（pubspec: 0.1.1+2；kAppVersion 硬编码 0.1.0+1 → Issue #238 未修复）
CI: ✅ 全绿（CI #34693534368 success；本次 maintainer run #34714264306 in_progress）
Tests: ✅ TC-ARCH-6 7/7 passed（上次 6 skipped 已清零）；export 子集 9/9 passed；export_semantic_snapshot_test U9 全通过
Build: ✅ apk + web 构建成功（CI #34693534368 全部 job 通过）
Flutter analyze lib/: 0 errors, 0 warnings, 33 info-level（deprecated_member_use + prefer_const_constructors 等存量）

**近 5 commit 代码级变更回顾**：
- `d9eb9fa` fix(mermaid): 图表随 Dark/Sepia 主题切换渲染（#239 · PR #284）——✅ 已合入，Issue #239 关闭
- `e1ac5c7` fix(home): 移除首页空壳搜索按钮（#242 · PR #283）——✅ 已合入，Issue #242 关闭
- `7f26ac3` refactor(providers): 消除 3 个 Provider 重复定义，删除 2 个死文件（#266 · PR #282）——✅ 已合入，Issue #266 关闭
- `d895050` test(architecture): TC-ARCH-6 unskip 3 个已修复的 Provider 唯一性测试（#265 · PR #281）——✅ 已合入，Issue #265 关闭
- `5e7e023` docs(positioning): 产品定位收敛 ADR-0033（#243 · PR #285）——纯文档，无代码影响

**昨日（09-12）已闭合 Issue 汇总**：
| Issue | 状态 | 关联 Finding |
|-------|------|-------------|
| #239 Mermaid 图表不随 Dark/Sepia 主题切换 | ✅ CLOSED | mermaid theme fix |
| #242 首页搜索按钮为空壳 | ✅ CLOSED | F-2026-09-03-04 |
| #245 O(n²) wordCount 路径 | ✅ CLOSED | PR #280 perf(editor) |
| #265 skip 消息过时 | ✅ CLOSED | F-2026-09-10-01 |
| #266 Provider 重复定义 | ✅ CLOSED | F-2026-09-10-02 |
| #273 TXT 导出 BoldElement 静默丢失 | ✅ CLOSED | F-2026-09-12-01 |


## New Findings

No significant findings.

---

## Existing Issue Updates

### Issue #263（adb device offline）

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新代码触及 CI runner 配置；C-01 无第 11 轮（无新 PR 合入）。CI #34693534368（main push）成功但未包含 Android emulator integration job。Issue 仍开放，等待 Human Owner 决策。
Next Step: 等待 Human Owner 决策是否切换 runner 类型或添加 adb logcat dump

### Issue #238（kAppVersion 漂移）

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: flutter_app/lib/main.dart:24 仍硬编码 `const String kAppVersion = '0.1.0+1'`，pubspec.yaml version 为 `0.1.1+2`，漂移未修复。
Next Step: 待修复（低优先级 P3）

### Issue #234（无测试验证导出公式可见性）

Status: UNCHANGED
Root Cause: Unknown
New Evidence: 无新代码触及公式导出 PNG 透明度或 MathJax SVG 真实渲染路径。U9 测试已通过（U9 关注 TXT 语义恒等，不涉及 PNG 透明度）。
Next Step: 等待产品侧复现补充或人工决策是否增加 golden test

---

## Ecosystem Findings

### E-2026-09-13-01 — Node.js 20 弃用 Deadline 已过，主 CI workaround 仍未迁移

Topic: GitHub Actions runner 兼容性（Node.js 20 退役）
Current Solution: ci.yml 仍设置 `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: 'true'`（见 ci.yml:31），这是针对 Node 20 过渡期的 workaround
Deadline: 2026-09-16（已过期，今日为截止日之后）
Alternative: 迁移至 Node 22 action（maintainer workflow 和 cline-pr-review 已使用 node-version: 22）
Comparison: 主 CI 仍依赖 workaround 运行在 Node 20 上；两个辅助 workflow 已正常运行于 Node 22，风险隔离证明 Node 22 可用。主 CI 未迁移可能在未来某次 runner 升级时突然中断（而非优雅降级）。
Recommendation: INVESTIGATE
Decision: no
Related Issue: N/A（生态发现，不创建 Issue；建议 Human Owner 在主 CI 下一次变更时顺手升级）

---

## Pending Decisions

- [ ] Issue #263（adb device offline）是否进入修复？（关联：FR-001；建议：继续等待，非阻塞项）
- [ ] Issue #238（kAppVersion 漂移）是否进入空档期修复？（建议：P3，一行修复）
- [ ] E-2026-09-13-01（Node.js 20 已过期）主 CI 何时迁移至 Node 22？（建议：下次涉及 ci.yml 变更时顺手完成）

---

## Depth Anchor — 当日深读记录

### 深读 1：Mermaid 主题联动修复验证（Issue #239 已闭合）

追踪路径：
```
mermaid_block.dart:121-126
  → MermaidElementWidget(theme: Theme.of(context).brightness == Brightness.dark ? dark : light)
  → MermaidElementWidget.didUpdateWidget(oldWidget)（mermaid_renderer.dart:72-88）
    → if (oldWidget.theme != widget.theme) → renderToSvg(new theme)
  → MermaidService.renderToSvg(code, theme)（mermaid_service.dart:300+）
    → _themeSvgCache[theme] check（:68）→ 命中缓存则直接返回 SVG，零额外 WebView 调用
    → 未命中 → JS 端 mermaid.initialize(theme: ...) + render → 写入 _themeSvgCache
```

关键验证：
- Sepia 主题 brightness = Brightness.light（app_theme.dart:119），正确映射到 MermaidTheme.light
- 主题切换时 InheritedWidget 依赖树重建 → MermaidBlock._buildMermaidContent() 重新执行 → theme 参数变化 → didUpdateWidget 检测变化 → 重渲染
- `_themeSvgCache` 按主题缓存，Sepia（light）和 Dark 切换无冗余 WebView 调用
- Issue #239 已闭合，修复正确

### 深读 2：TC-ARCH-6 闭环比对（F-2026-09-10-01/02 已闭合验证）

追踪路径：
```
flutter_app/test/architecture/provider_uniqueness_test.dart
  → _grepLib(RegExp) 扫描 lib/ 下所有 .dart
  → 7 个 test case 全部 pass（之前 6 skipped + 1 pass）
flutter_app/lib/domain/providers/ 目录
  → 仅剩 export_progress_provider.dart（1 文件）
  → document_provider.dart（86 行）和 editor_provider.dart（74 行）已删除（PR #282）
flutter_app/lib/providers/providers.dart
  → documentsProvider: 1 定义（:12）✅
  → isExportingProvider: 仅 editor_providers.dart:69 定义，providers.dart:91 是注释说明 ✅
  → editorContentProvider: 仅 editor_providers.dart:71 定义，providers.dart:92 是注释说明 ✅
```

关键验证：
- 3 个 Provider 重复定义已全部消除（domain/providers/ 死代码已删除 + providers.dart 冗余定义已清理）
- provider_uniqueness_test.dart skip 消息已更新（PR #281）
- TC-ARCH-6 守门测试恢复真实有效性
- Issues #265/#266 均已闭合

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

**结论**：第 3 轮（#256）曾通过，但第 5/7/9/10 轮均因 `adb: device offline` 失败。代码变更未触及 emulator 启动/连接逻辑，根因在 CI runner 基础设施层。今日无第 11 轮（无新 PR）。

**Depth progress**: N+1（smoke 链路曾通）→ blocked（adb device offline，基础设施问题）
**Next depth target**: 等待 #263 决策

---