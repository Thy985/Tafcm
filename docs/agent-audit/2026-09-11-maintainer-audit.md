# Tafcm Daily Maintainer Audit

> 运行日期：2026-09-11（本地 UTC+8）· 触发：schedule cron 01:23
> HEAD: d83c827（chore(agent): daily maintainer audit 2026-09-10）

## Repository Health

Commit: `d83c827`（chore(agent): daily maintainer audit 2026-09-10）
Version: v0.1.1+2（pubspec: 0.1.1+2；kAppVersion 硬编码 0.1.0+1 → Issue #238，未修复）
CI: ⏳ 本次 maintainer run #34522790711 in_progress（北京时间 03:51 触发）；主 CI 无近期 push；Issue #263 跟踪 adb device offline 阻塞 C-01 E2E
Tests: ✅ 架构守门 75 passed, 6 skipped（provider_uniqueness_test 6 skip 均为已知问题）；parser+error 子集 149 passed, 6 skipped
Build: ✅ apk + web 构建成功（C-01 第九轮 build 阶段通过）
Golden failures: ✅ 0
flutter analyze lib/: 0 errors, 0 warnings, 33 info-level issues（deprecated_member_use + prefer_const_constructors 等）
无新产品代码变更（自 09-10 audit commit 起无 lib/ 或 test/ 改动）
Provider 重复定义现状（延续 09-10 核查，无变化）：
- ✅ sharedPreferencesProvider：仅定义于 editor_providers.dart:7（治理轮已修复）
- ✅ darkModeProvider：仅定义于 editor_providers.dart:63（治理轮已修复）
- ✅ previewModeProvider：仅定义于 editor_providers.dart:67（治理轮已修复）
- ❌ documentsProvider：重复定义（providers.dart:12 + domain/providers/document_provider.dart:9）
- ❌ isExportingProvider：三重重复（editor_providers.dart:69 + domain/providers/editor_provider.dart:11 + providers.dart:89）
- ❌ editorContentProvider：重复定义（editor_providers.dart:71 + providers.dart:92）
domain/providers/document_provider.dart 和 domain/providers/editor_provider.dart 均无 lib/ 导入（死代码）

---

## New Findings

No significant findings.

## Existing Issue Updates

### Issue #265

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无新代码触及 provider_uniqueness_test.dart；skip 消息仍引用旧状态（sharedPreferencesProvider/darkModeProvider/previewModeProvider 已收敛至 editor_providers.dart 单一定义，但 skip 消息未更新）；Issue 开放等待修复
Next Step: 同步 Issue #266 一并修复

### Issue #266

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: 无新代码触及 providers.dart / editor_providers.dart / domain/providers/；3 个 Provider 重复定义仍存在（documentsProvider 2x、isExportingProvider 3x、editorContentProvider 2x）；domain/providers/document_provider.dart（86 行）和 domain/providers/editor_provider.dart（74 行）无 lib/ 导入，确认为死代码，使用已废弃 DocumentService（@Deprecated，ADR-0003 违反）
Next Step: 待 Human Owner 决策清理优先级（建议：空档期 P2 一并清理）

### Issue #263

Status: UNCHANGED
Root Cause: Hypothesis
New Evidence: 无新代码触及 CI runner 配置；C-01 第 9-10 轮（#261/#262）延续同一故障模式——adb device offline；Issue 已创建但待 Human Owner 决策
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

### Issue #238

Status: UNCHANGED
Root Cause: Confirmed
New Evidence: flutter_app/lib/main.dart:24 仍硬编码 kAppVersion = '0.1.0+1'，pubspec.yaml version 为 0.1.1+2，漂移未修复
Next Step: 待修复（低优先级 P3）

---

## Ecosystem Findings

### E-2026-09-11-01

Topic: GitHub Actions Node.js 20 弃用Deadline 逼近
Current Solution: tafcm-maintainer.yml 已使用 actions/setup-node@v4 + node-version: 22；主 CI (ci.yml) 设置 ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: true 过渡期兼容
Alternative: 等待 subosito/flutter-action 发布 Node 24 原生支持后移除 workaround
Comparison: Node.js 20 将于 2026-09-16 被 runner 移除（距今日 5 天）；maintainer workflow 已就绪（Node 22）；主 CI 通过环境变量 workaround 兼容，风险可控但时限紧迫
Recommendation: INVESTIGATE
Decision: no

---

## Pending Decisions

- [ ] Issue #263 是否进入下周修复？（关联：F-2026-09-07-01；建议：进入，阻塞 E2E 自动化）
- [ ] C-01 实验是否继续投入？（关联：F-2026-09-07-01；建议：暂停，等待 #263 决策）
- [ ] domain/providers/document_provider.dart + editor_provider.dart 死代码清理优先级？（关联：F-2026-09-08-01 / F-2026-09-10-02；建议：P2，空档期一并清理，减少 TC-ARCH-6 skip 数量）
- [ ] provider_uniqueness_test.dart 过时 skip 消息是否更新？（关联：F-2026-09-10-01；建议：P2，同步 #266 修复一并处理）
- [ ] Node.js 20 弃用（2026-09-16 截止）：主 CI workaround 是否需要提前替换？（关联：E-2026-09-11-01；建议：5 天内验证主 CI Node 22 兼容性，避免 runner 移除后 CI 中断）

---

## Depth Anchor — 当日深读记录

### 深读 1：domain/providers/ 死代码 + Provider 重复定义根因追查（延续 F-2026-09-10-02）

追踪路径：
```
flutter_app/lib/domain/providers/document_provider.dart（86 行）
  → import '../../core/services/document_service.dart'（DocumentService @Deprecated）
  → documentsProvider 定义（:9）：使用 DocumentService（旧 JSON 存储路径）
  → currentDocumentProvider 定义（:14）：无外部引用
flutter_app/lib/domain/providers/editor_provider.dart（74 行）
  → isExportingProvider 定义（:11）：与 editor_providers.dart:69 + providers.dart:89 三重重复
  → editorModeProvider / isDarkModeProvider / contentProvider：无外部引用
grep -rn "import.*domain/providers/document" flutter_app/lib/ → 0 结果
grep -rn "import.*domain/providers/editor" flutter_app/lib/ → 0 结果
```

关键发现：
- domain/providers/document_provider.dart 和 editor_provider.dart 在 lib/ 下零导入，确认为孤立死代码
- document_provider.dart 使用的 DocumentService 已在 document_service.dart:9 标注 @Deprecated（"Phase 1 存储统一后由 FileRepository 取代"），与 ADR-0003 .md 单一真相源相悖
- isExportingProvider 三重重复中，Riverpod 运行时取最后定义（providers.dart:89 或 editor_providers.dart:69，取决于加载顺序），行为不可预测
- editorContentProvider 双重重复同理
- 修复方案：删除 domain/providers/document_provider.dart 和 domain/providers/editor_provider.dart，清理 providers.dart 中的 isExportingProvider:89 和 editorContentProvider:92

### 深读 2：FormulaSvgService + MermaidService 静态 WebView 共享生命周期（风险驱动）

追踪路径：
```
formula_svg_service.dart:100-101
  → MermaidService.isPageLoaded（mermaid_service.dart:63）
  → MermaidService.attachedController（:273 getter）
  → MermaidService._controller（:61 static InAppWebViewController?）
formula_svg_service.dart:203, 319
  → MermaidService.attachedController（共享同一个 static _controller）
formula_svg_service.dart:365
  → MermaidService.resetRenderer()（崩溃恢复共用）
```

关键发现：
- FormulaSvgService 不持有独立 WebView，完全依赖 MermaidService._controller（static singleton）
- 单点故障：Mermaid WebView 崩溃 → 公式渲染和 Mermaid 渲染同时失效
- 已有保护：_consecutiveTimeouts 连续 3 次超时才触发 resetRenderer（PR-C 修复级联放大）
- 测试隔离风险：static 状态在单元测试间不隔离（clearTelemetry()/clearQualityCounters() 可部分重置，但 _controller/_pageLoaded 无法重置）
- 这不是新 Finding（已在 09-07/09-08 深读中记录），但作为风险驱动锚点确认无恶化

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

**结论**：第 3 轮（#256）曾通过，但第 5/7/9/10 轮均因 `adb: device offline` 失败。代码变更未触及 emulator 启动/连接逻辑，根因在 CI runner 基础设施层。

**Depth progress**: N+1（smoke 链路曾通）→ blocked（adb device offline，基础设施问题）
**Next depth target**: 等待 #263 决策（是否切换 runner 类型 / 添加诊断 dump）
