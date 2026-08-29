# Tafcm 架构总览

> 本文描述 Tafcm 的**当前架构、目标架构、已知问题与重构风险**。  
> 所有内容基于实际代码分析，不凭空设计。
>
> **状态更新（2026-08-10，Phase 3.7 完成后）**：本文为 Phase 0 末（2026-07-18）的历史快照 + Phase 1 关闭后（2026-07-19）的局部更新。§1.1/§1.3 已滞后于 Phase 3 后的实际代码结构（presentation 层已从 4 子目录扩展为 13 子目录，数据流已从"编辑/预览双模式"改为 WYSIWYG）。完整 Phase 3 后的架构见 [Component-Tree.md](UI-COMPONENT-MODEL.md) + [UI-ARCHITECTURE.md](UI-ARCHITECTURE.md) + [ADR-0009](../decisions/ADR/0009-ui-architecture-design.md)。

---

## 1. 当前架构（As-Is）

### 1.1 六层分层架构

```
┌──────────────────────────────────────────────────┐
│ presentation/    UI 组件、屏幕、主题、对话框、菜单 │
├──────────────────────────────────────────────────┤
│ providers/       全局 Riverpod Provider           │
├──────────────────────────────────────────────────┤
│ domain/          业务领域：导出服务、业务 Provider  │
├──────────────────────────────────────────────────┤
│ data/            数据模型：Document、Template      │
├──────────────────────────────────────────────────┤
│ core/            基础设施：解析器、渲染器、服务     │
├──────────────────────────────────────────────────┤
│ main.dart        App 入口 + ProviderScope         │
└──────────────────────────────────────────────────┘
```

依赖方向严格自上而下。详细目录见 [README.md](file:///d:/Projects/Active/math2/flutter_app/README.md)。

### 1.2 模块职责

#### `lib/core/`

| 子模块 | 职责 |
|--------|------|
| `constants/` | 颜色 / 间距 / 阴影常量（[app_constants.dart](file:///d:/Projects/Active/math2/flutter_app/lib/core/constants/app_constants.dart)） |
| `parser/` | Markdown 解析 + 公式提取 |
| `renderers/` | 自研 SVG AST + SVG→PDF |
| `router/` | go_router 配置 |
| `services/` | 文档 / 文件 / 公式 / Mermaid / 剪贴板 |
| `utils/` | 撤销重做栈 |

#### `lib/data/`

- `models/document.dart`：sealed class `DocumentElement` + `InlineElement` + `Document`
- `models/template.dart`：内置 3 类模板

#### `lib/domain/`

- `providers/`：业务级 Provider
- `services/export_service.dart`：导出 facade + 错误分类
- `services/exporters/`：PDF / Word / TXT 导出器 + OOXML 拼装
- `services/word_ooxml_templates.dart`：OOXML 模板

#### `lib/presentation/`

> **状态更新（2026-08-10）**：Phase 3 后 presentation 层已从 4 子目录扩展为 13 子目录，详见 [Component-Tree.md](UI-COMPONENT-MODEL.md)。

Phase 0 末结构（历史快照）：
- `screens/`：编辑器 / 文件管理（`/files` 路由，已合并原 `DocumentListScreen` 死代码）
- `widgets/`：渲染器、对话框、菜单
- `components/`：通用组件
- `theme/`：浅色 / 深色主题

Phase 3 后实际结构（13 子目录）：
- `editor/`：EditorShell / EditorCoordinator / EditorPage / EditorScope（Phase 3.0）
- `blocks/`：8 种 BlockType（paragraph/heading/code/quote/table/mermaid/formula/input）+ shared/（Phase 3.2-3.5）
- `chrome/`：AppBar / StatusBar / Toolbar（IDE 惯例分离，Phase 3.0 v1.1）
- `panels/`：TOC / 文件树（Phase 3.4.1/3.4.2）
- `commands/`：EditorCommand（sealed）+ CommandHandler（Phase 2.9 / 3.0）
- `states/`：BlockViewState / CoordinatorState（Phase 2.9）
- `theme/`：EditorTokens（ThemeExtension，Phase 3.4.5）
- `themes/`：AppTheme（light / dark / sepia，Phase 3.4.3）
- `observability/`：可观测性 UI（诊断导出按钮等，Phase 3.7）
- `components/` / `widgets/`：通用组件
- `prototype/`：Phase 2.9 Prototype Demo（4 个）
- `screens/`：顶层 Screen

#### `lib/providers/`

全局 Provider。Phase 1 1.1 已合并 `sharedPreferencesProvider` / `darkModeProvider` 重复定义（commit `ec76f06`），[provider_uniqueness_test.dart](file:///d:/Projects/Active/math2/flutter_app/test/architecture/provider_uniqueness_test.dart) 守门。

### 1.3 数据流

> **状态更新（2026-08-10）**：Phase 3.1 后已移除"编辑/预览双模式"，改为 WYSIWYG 块级编辑。下方编辑流为 Phase 0 末历史快照，实际数据流见 [Interaction-Model.md](UI-INTERACTION-MODEL.md)。

#### 编辑流（Phase 0 末历史快照）

```
用户输入
  └→ TextEditingController
      └→ _onTextChanged → editorContentProvider.state = text
          ├→ FileRepository.write(.md)（Phase 1.2 后为单一真相源，废弃 500ms 防抖 + SharedPreferences）
          └→ PreviewContent 重建
              └→ MarkdownParser.parse(content)
                  └→ List<DocumentElement>
                      └→ 各 *Renderer Widget 渲染
```

**问题**：每次按键全量重解析，文档 > 500 行时卡顿。Phase 2 增量解析后缓解。

#### 编辑流（Phase 3 后 WYSIWYG）

```
用户操作（键盘 / 触摸 / IME）
  └→ UI Event（Widget 层）
      └→ EditorCommand（纯数据，可序列化）
          └→ CommandHandler（意图分发 + 守卫 + Transaction 生命周期）
              └→ TransactionBuilder → BlockOperation
                  └→ AST（Document 模型）
                      └→ BlockRenderer → Widget Tree（光标块 edit 态，其余 render 态）
                          └→ AutosaveService（debounce 1.5s）→ FileRepository.write(.md)
```

详见 [Interaction-Model.md](UI-INTERACTION-MODEL.md) + [ADR-0009](../decisions/ADR/0009-ui-architecture-design.md)。

#### 导出流

```
用户点击导出
  └→ ExportService.exportAndShare
      ├→ 阶段 1: exporter(markdown)
      │   ├→ PDF: parse → collectAllFormulas → FormulaSvgService.preRenderAll
      │   │       → FormulaRenderPlan → PdfExporter 拼装
      │   ├→ Word: parse → FormulaPdfRenderer.preRenderAll → WordOoxmlBuilder
      │   └→ TXT: parse → TextExporter 序列化
      ├→ 阶段 2: getTemporaryDirectory → 写文件 → Share.shareXFiles
      └→ 异常 → classifyError → ExportFailureException → UI 本地化
```

详见 [domain/services/export_service.dart](file:///d:/Projects/Active/math2/flutter_app/lib/domain/services/export_service.dart)。

### 1.4 关键设计决策（已落地）

> **状态更新（2026-08-10）**：ADR 已从 6 份扩展到 24 份，下方仅列 Phase 0-1 的基础决策。完整 ADR 索引见 [README.md ADR 索引](../README.md#adr-索引)。

| 决策 | ADR |
|------|-----|
| 项目命名为 Tafcm（原 FormulaFix），目录结构 6 层 | [ADR-0031](../decisions/ADR/0031-rebrand-tafcm.md)（取代 ADR-0001 §1） |
| 状态管理选 Riverpod | [ADR-0002](../decisions/ADR/0002-state-management-riverpod.md) |
| 存储目标：.md 文件作为单一真相（**Phase 1 已达成，ADR-0003 Implemented**） | [ADR-0003](../decisions/ADR/0003-storage-single-source-md-files.md) |
| 解析器扩展策略：补齐缺失元素而非重写 | [ADR-0004](../decisions/ADR/0004-markdown-parser-extension-strategy.md) |
| 导出器 facade + 依赖注入 | [ADR-0005](../decisions/ADR/0005-exporter-facade-dependency-injection.md) |
| CI 选 GitHub Actions | [ADR-0006](../decisions/ADR/0006-ci-github-actions.md) |
| BlockEditor 抽象设计（Phase 2.1） | [ADR-0007](../decisions/ADR/0007-blockeditor-abstraction-design.md) |
| 编辑器 Transaction 模型（Phase 2.6） | [ADR-0008](../decisions/ADR/0008-editor-transaction-model.md) |
| UI 架构设计（Phase 2.9，核心接口冻结） | [ADR-0009](../decisions/ADR/0009-ui-architecture-design.md) |
| Design System Token & Typography（Phase 3.4.5） | [ADR-0017](../decisions/ADR/0017-design-system-alignment.md) |
| 编辑器可观测系统（Phase 3.7） | [ADR-0023](../decisions/ADR/0023-editor-observability-system.md) |

---

## 2. 当前架构问题

完整列表见 [CRITICAL_REVIEW.md](../archive/audits/CRITICAL-REVIEW.md)。

> **状态更新（2026-07-19，Phase 1 关闭后）**：本节列表为 Phase 0 末（2026-07-18）的历史快照。下列 P0 项已在 Phase 1 修复：§2.1-2（`b43e5c1`）、§2.1-3（`b36d930`）、§2.1-4（`ec76f06`）、§2.1-5（`da4ab00`）、§2.1-6（`d57d2f2`）。§2.4 中 P3-30/31/32/33/35 也在 Phase 0 / Phase 1 修复。详细证据见 [Verification Report](file:///d:/Projects/Active/math2/docs/releases/phase1-verification-report.md) 与 [AGENTS.md §10](file:///d:/Projects/Active/math2/AGENTS.md)。
>
> **仍存在项**：§2.1-1 范式错位（Phase 3）、§2.2 P1 体验问题（Phase 3）、§2.3 P2 完善问题（Phase 3+）、§2.4 静态状态污染测试（Phase 2）。

### 2.1 P0 阻塞

1. **范式错位**：编辑/预览分离，与 Typora WYSIWYG 灵魂对立 → **Phase 3 待修复**  
   证据：[editor_screen.dart:300-321](file:///d:/Projects/Active/math2/flutter_app/lib/presentation/screens/editor_screen.dart#L300-321)
2. ~~**三套存储并存**~~ → ✅ Phase 1 1.2 已修复（commit `b43e5c1`，[ADR-0003](file:///d:/Projects/Active/math2/docs/decisions/ADR/0003-storage-single-source-md-files.md) Implemented）
3. ~~**DocumentListScreen 是死代码**~~ → ✅ Phase 1 1.3 已修复（commit `b36d930`，路由合并到 `/files`）
4. ~~**Provider 重复定义**~~ → ✅ Phase 1 1.1 已修复（commit `ec76f06`，[provider_uniqueness_test.dart](file:///d:/Projects/Active/math2/flutter_app/test/architecture/provider_uniqueness_test.dart) 守门）
5. ~~**解析器缺 7 类元素**~~ → ✅ Phase 1 1.5 已修复（commit `da4ab00`，[edge_case_test.dart](file:///d:/Projects/Active/math2/flutter_app/test/parser/edge_case_test.dart) 覆盖）
6. ~~**工具栏与解析器矛盾**~~ → ✅ Phase 1 1.6 已修复（commit `d57d2f2`）

### 2.2 P1 体验

- 预览被卡片包裹，浪费手机宽度
- AppBar 标题写死 "Tafcm"
- 每次按键全量重解析（性能瓶颈）
- WebView 冷启动 2-3 秒
- 单条公式 30s 超时，导出整体 120s 超时
- 导出无进度反馈
- 剪贴板自动弹对话框骚扰用户
- 退出编辑器清空所有缓存
- 代码块无语法高亮

### 2.3 P2 完善

- 主题只有 light/dark 两套
- 字号不可缩放
- 颜色定义两套并存（`AppColors` / `AppTheme.*Color`）
- 缺大纲 / TOC 面板
- 缺焦点模式 / 打字机模式
- 错误消息透传 `detail` 给用户
- 异常被静默吞（[file_manager_screen.dart:46](file:///d:/Projects/Active/math2/flutter_app/lib/presentation/screens/file_manager_screen.dart#L46)）

### 2.4 P3 工程化

- ~~缺 `pubspec.yaml`（CI 阻塞）~~ → ✅ Phase 0 0.1 已修复
- ~~残留文件 [export_service_tail.txt](file:///d:/Projects/Active/math2/flutter_app/lib/domain/services/export_service_tail.txt)~~ → ✅ Phase 0 0.6 已清理
- ~~[web/manifest.json](file:///d:/Projects/Active/math2/flutter_app/web/manifest.json) 描述仍是默认 "A new Flutter project."~~ → ✅ Phase 0 0.6 已更新
- ~~`main()` 多余 async~~ → ✅ Phase 1 1.2 副作用（添加 `await StorageMigration.migrateIfNeeded()`，async 现为必要）
- 静态状态污染测试（CJK 字体、缓存等）→ **Phase 2 待修复**
- ~~测试覆盖不足（缺 UI / 路由 / Provider 集成测试）~~ → ✅ Phase 1 1.8 已修复（314 tests / 0 regression，详见 [Verification Report](file:///d:/Projects/Active/math2/docs/releases/phase1-verification-report.md)）

---

## 3. 目标架构（To-Be）

### 3.1 范式重构目标（Phase 2）

```
┌────────────────────────────────────────────────────────┐
│ presentation/                                          │
│   screens/                                              │
│     - WysiwygEditorScreen（块级渲染 + 光标态切换）       │
│     - FileTreeScreen（侧滑，替代 DocumentListScreen）   │
│     - OutlineScreen（侧滑大纲，跳转标题）                │
│   widgets/                                              │
│     - BlockEditor（每个 DocumentElement 一个块）        │
│     - InlineEditor（光标所在块渲染为 TextField）         │
│     - RenderedBlock（非聚焦块渲染为最终样式）           │
├────────────────────────────────────────────────────────┤
│ providers/  统一到一处，删除重复                        │
├────────────────────────────────────────────────────────┤
│ domain/                                                │
│   services/file_repository.dart  ← 单一存储入口        │
│   services/export/               ← 不变                │
├────────────────────────────────────────────────────────┤
│ data/                                                  │
│   models/  AST 扩展：InlineCode / Link / Image 等      │
├────────────────────────────────────────────────────────┤
│ core/                                                  │
│   parser/   完整 Markdown + GFM 语法                    │
│   renderers/  SVG 不变                                 │
└────────────────────────────────────────────────────────┘
```

### 3.2 数据存储目标（Phase 1 已达成）

- **单一真相**：`.md` 文件（应用沙盒内 + 用户可见目录）— ✅ [FileRepository](file:///d:/Projects/Active/math2/flutter_app/lib/core/services/file_repository.dart) + [StorageMigration](file:///d:/Projects/Active/math2/flutter_app/lib/core/services/storage_migration.dart)
- 文档列表 = 扫描 `.md` 文件 + FrontMatterParser 解析元数据 — ✅
- **已废弃**：`formula_fix_documents.json`（迁移期保留 .bak）、`SharedPreferences['pref_last_content']` — ✅
- 文档元数据（最近打开、收藏、置顶）走 `SharedPreferences` 或 SQLite — Phase 2 派生缓存（受 [ADR-0003](file:///d:/Projects/Active/math2/docs/decisions/ADR/0003-storage-single-source-md-files.md) §边界约束 5 守护，**可重建**而非真相源）

详见 [ADR-0003](file:///d:/Projects/Active/math2/docs/decisions/ADR/0003-storage-single-source-md-files.md)（状态：Implemented）。

### 3.3 解析器目标

- 完整支持 CommonMark + GFM（任务列表 / 删除线 / 表格 / 自动链接）
- AST 扩展，每个 inline 元素一个子类
- 块级渲染时**只重解析光标所在块**，非全量

详见 [ADR-0004](file:///d:/Projects/Active/math2/docs/decisions/ADR/0004-markdown-parser-extension-strategy.md)。

---

## 4. 重构风险

### 4.1 数据迁移风险（最高）

**风险**：把 JSON 文档库迁到 .md 文件可能丢用户数据。

**缓解**：
- 迁移前做一次性 `DocumentService.exportAllToJsonBackup()` 写一份完整备份
- 迁移逻辑幂等：检测到旧 JSON 文件存在则迁移，迁移成功后**保留** JSON 作为 `.bak`
- 提供回滚脚本

### 4.2 解析器重写风险

**风险**：`DocumentElement` 类型变化会破坏 PDF/Word 导出器与所有 renderer。

**缓解**：
- AST 扩展**只新增不修改**现有子类签名
- 新增子类时通过 sealed class 让 Dart 3 强制 exhaustive switch 报错
- 导出器与 renderer 必须同步更新，且 PR 内同时改

### 4.3 范式重构风险

**风险**：从编辑/预览分离改为 WYSIWYG 是大规模 UI 重写，可能引入大量 bug。

**缓解**：
- 渐进式：先实现"块级实时渲染"（聚焦块渲染、非聚焦块渲染为预览态），不动整体架构
- 保留旧 `EditorScreen` 一段时间，通过 feature flag 切换
- 每个 PR 只改一个块类型的渲染

### 4.4 WebView 缓存策略风险

**风险**：改 `MermaidService._cache` 等静态状态会让现有缓存失效。

**缓解**：
- 重构期间不删除静态状态，先抽出接口
- 测试用 `MarkdownExporter.register({...})` 注入 fake 避开 WebView 依赖

### 4.5 Provider 重命名风险

**风险**：合并重复 Provider 时，identity 变化会导致状态丢失（用户感觉暗色模式被重置）。

**缓解**：
- 重命名 PR 单独提交，不混入功能改动
- 在 release notes 中告知用户

### 4.6 pubspec 缺失风险（~~当前阻塞~~ 已解决）

**风险**：CI 无法运行，新人无法启动。

**缓解**：~~见 [ROADMAP.md](../ROADMAP.md) Phase 0 前置任务。~~ ✅ 已解决（Phase 0.1，`pubspec.yaml` 已补齐含依赖最小集 + assets 声明）。

### 4.7 静态状态污染测试风险

**风险**：CJK 字体加载状态、SVG 缓存等跨测试用例共享。

**缓解**：
- 测试 `setUp` / `tearDown` 显式调用 `clearCache()`
- 后续重构时把静态状态抽成 instance + DI

---

## 5. 相关文档

- [AGENTS.md](../../AGENTS.md) — AI 协作规范
- [ROADMAP.md](../ROADMAP.md) — 路线图
- [CODING_RULES.md](../engineering/DEVELOPMENT-RULES.md) — 详细编码规范
- [GIT_WORKFLOW.md](../engineering/GIT-WORKFLOW.md) — Git 流程
- [CRITICAL_REVIEW.md](../archive/audits/CRITICAL-REVIEW.md) — 现状批判
- [ADR/](ADR/) — 架构决策记录（24 份）
- [UI-ARCHITECTURE.md](UI-ARCHITECTURE.md) — UI 架构心智模型（Phase 2.9 产出，Accepted）
- [Interaction-Model.md](UI-INTERACTION-MODEL.md) — 交互事件模型（Phase 2.9 产出，Accepted）
- [Component-Tree.md](UI-COMPONENT-MODEL.md) — 组件树与核心接口冻结（Phase 2.9 产出，Accepted）
- [UI_SPEC.md](../product/UX-GUIDE.md) — UI 设计规范（产品视觉 source of truth）
- [E2E_TEST_PLAN.md](../engineering/VERIFICATION-POLICY-source-e2e.md) — E2E 测试计划
- [releases/](releases/) — 各 Phase Verification Report
