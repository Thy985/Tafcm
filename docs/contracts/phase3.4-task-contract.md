# Phase 3.4 Task Contract: Advanced Capabilities（高级能力）

> **版本**：v1.1（v0.1 评审升 v1.0 定三 ADR + 平台矩阵 + 演进 Gate；v1.1 据第二轮评审补 DirtyStateSource 抽象 / 资产命名冻结 / 删除仅引用 / ADR-0015 措辞修正 / ADR-0016，待签字定稿）
> **起草日期**：2026-07-26
> **起草人**：AI Agent
> **状态**：Draft（未在 git 提交；架构决策类文件按 AGENTS.md 需 Human Owner 授权后提交）
> **前置阶段**：Phase 3.3 Mobile Markdown Editing Experience（✅ 已合并 PR #67，main 当前 tip `fcb6c15`）
> **后继阶段**：Phase 3.5 Deferred Block Runtime Items / Phase 4 多平台与高级功能
>
> **关联文档**：
> - [ROADMAP.md §Phase 3.4+](../ROADMAP.md)
> - [design/ui-spec.md §7 Phase 3.4+](../design/ui-spec.md)
> - [Phase 3.3 Task Contract v1.6](../contracts/phase3.3-task-contract.md)（E2E Gate 模式沿用）
> - [ADR-0009 UI Architecture Design](../ADR/0009-ui-architecture-design.md)
> - [ADR-0012 Live Editing State](../ADR/0012-live-editing-state.md)
> - [ADR-0013 Autosave Architecture](../ADR/0013-autosave-architecture.md)（**新增**，3.4.7 自动保存定案）
> - [ADR-0014 Document Asset Management](../ADR/0014-document-asset-management.md)（**新增**，3.4.9 图片资源定案）
> - [ADR-0015 Theme Architecture Migration](../ADR/0015-theme-architecture-migration.md)（**新增**，3.4.3 主题迁移定案）
> - [ADR-0016 Document Repository Boundary](../ADR/0016-document-repository-boundary.md)（**新增**，FileTree/Autosave/Export 共用的仓储边界）
>
> **设计评审纪要（2026-07-26，Human Owner）**：整体可作为实施级 RFC，评分 架构设计 9/10、任务拆解 9/10、风险控制 8.5/10、实施可执行性 8/10、长期演进价值 9/10。要求签字前补三份 ADR（自动保存 / 图片资源 / 主题迁移）+ E2E 平台矩阵 + 架构演进 Exit Gate，已在本版落实。**第二轮评审将 v1.0 提升至 ~9.2/10**，并追加：AutosaveService 依赖 `DirtyStateSource` 抽象（去 Coordinator 耦合）、资产命名冻结 `img_<uuid>.png`、删除仅 reference removal（GC 留 Phase 4）、ADR-0015 措辞由「向后兼容」改为「语义兼容 / API 迁移」、新增 ADR-0016 Document Repository Boundary。均已落实于 v1.1。本版可作为 **v1.1 正式签署版本**。

---

## 0. 任务缘起

Phase 3.3 完成了移动端 Markdown **输入体验**（工具栏 / 自动配对 / 自动续列表 / 焦点模式 / 字号缩放 / 模板菜单 / Undo-Redo / 字数 / AppBar 标题）。Phase 3.4 进入 **Advanced Capabilities（高级能力）**：从"能舒服地写"升级为"能高效地导航 / 阅读 / 管理 / 导出"。

ROADMAP §Phase 3.4+ 列出 10 个候选任务。它们**并非同一优先级、也并非都适合手机端**：

- 部分（TOC / 主题 / 自动保存 / 图片插入）是移动端高价值能力，应优先；
- 部分（快捷键 / 打字机）源于桌面增强，手机 ROI 低，建议整体移入 Phase 4 Desktop 子阶段；
- 部分（选区格式化菜单 Overlay）在 Phase 3.3 已验证为高风险，建议保持可选 / 最后做。

本契约的任务表（§1）对 10 个任务重新分配优先级，并提出**切片执行顺序**（§10），避免 10 个任务混在一起或选错方向。

> **Phase 3.3 延期项回填（明确排入本阶段）**：Phase 3.3 PR #4 二次修订（commit `6b8c82b`）因 `editor_shell.dart` 缩放/焦点手势竞争修复，受影响的 widget 测试暂缺。按用户建议于 **Phase 3.4 初始 sprint** 在 `editor_shell_test.dart` 补齐 4 个场景（缩放按钮→zoomScale 变化 / 重置在 zoomScale=1.0 时 disabled / 焦点切换→AppBar/Toolbar/StatusBar 隐藏 / 双指缩放→gesture 更新 zoomScale）。本项不计为 Phase 3.4 新功能，仅回填测试债。

---

## 1. 目标与范围

### 1.1 核心目标

在 Phase 3.3 的编辑体验基础上，补齐导航 / 阅读 / 管理 / 导出类高级能力。聚焦**移动端真正高价值**的能力，桌面增强类（快捷键 / 打字机）按 ROI 评估后移出或最后做。

### 1.2 范围（10 个任务，优先级草案见 §1.3）

| # | 任务 | 优先级（草案） | 扩展点 | 不破坏的契约 |
|---|------|----------|--------|-------------|
| 3.4.1 | TOC 大纲侧滑面板（点击标题跳转） | **P0** | `panels/side_panel_host.dart` → `TocPanel` | EditorShell 布局不变（侧栏为 overlay/drawer） |
| 3.4.3 | 主题切换（Night / Sepia / GitHub） | **P0** | `EditorTokens` → `ThemeExtension<EditorTokens>` | 所有 `EditorTokens.xxx` 引用不变（向后兼容） |
| 3.4.7 | 自动保存（dirty 定时落盘） | **P0** | 独立 `AutosaveService`（见 ADR-0013） | `CoordinatorState` 不变 |
| 3.4.9 | Markdown 图片插入（从相册选图） | **P0** | `file_picker` + `ImageElement` + `assets/img_<uuid>.png` 副本 | BlockRenderer 不变 |
| 3.4.8 | 页面宽度控制（max-width 720px） | P1 | `ConstrainedBox` 包裹 EditorViewport | EditorViewport 布局不变 |
| 3.4.2 | 文件树侧滑面板（替换文件管理屏） | P1 | `panels/side_panel_host.dart` → `FilePanel` | EditorShell 布局不变 |
| 3.4.4 | 导出进度反馈（百分比 + 公式计数） | P1 | `EditorAppBar` action + 导出服务回调 | `EditorCoordinator` 不变 |
| 3.4.10 | 选区格式化菜单（Overlay 浮动菜单） | P1（可选） | `Overlay` + `TextSelection` 定位 | `BlockViewState` 不变 |
| 3.4.5 | 快捷键支持（物理键盘 / Web） | **P2（移 Phase 4）** | `Shortcuts` + `Actions` widget | CommandHandler 路径不变 |
| 3.4.6 | 打字机模式（光标行居中） | **P2（移 Phase 4）** | `EditorViewport` ScrollController | EditorShell 布局不变 |

> 优先级为草案，需 Human Owner 在 §9 决策中确认。最终优先级影响切片顺序（§10）。

### 1.3 优先级分配依据（草案，待确认）

- **P0（移动端高价值 + 脚手架就绪）**：
  - 3.4.1 TOC：`SidePanelHost` 占位已就绪，从 `coordinator.allIds` 读标题即可，低风险；且是后续文件树 / 搜索 / Outline / Backlinks 的底层能力验证。
  - 3.4.7 自动保存：先落地（基础文档生命周期能力），`coordinator.isDirty` / `markSaved()` 已就绪，独立 `AutosaveService`（ADR-0013）中等。
  - 3.4.3 主题：阅读体验最大提升；但属较大重构（ThemeExtension 迁移 + 全量调用方改造），作为独立高风险切片排期。
  - 3.4.9 图片插入：移动端高频需求，依赖 `file_picker` + `assets/` 副本（ADR-0014），中等。
- **P1（价值中等 / 较大）**：3.4.8 页面宽度（纯布局，极简）、3.4.2 文件树（涉及路由/文件服务，较大）、3.4.4 导出进度（依赖导出服务）、3.4.10 选区菜单（高风险，可选）。
- **P2（移 Phase 4）**：3.4.5 快捷键 / 3.4.6 打字机 —— 源于桌面增强，手机端 ROI 低（无物理 Ctrl 键、软键盘占半屏）。整体移入 Phase 4 Desktop Enhancement 子阶段，本契约不再跟踪。

---

## 2. 关键架构约束（Hard Rules，沿用 + 新增）

### 2.1 AST 零污染（沿用 Phase 2.9 / 3.0）
禁止在 `DocumentElement` 新增 UI 状态字段。TOC / 文件树 / 主题均为 UI 层能力，不污染 AST。

### 2.2 Command Layer 强制（沿用 Phase 3.0 / 3.3）
所有文档修改（图片插入、自动保存落盘）必须经 `EditorCommand` → `EditorCoordinator.handle()`。自动保存**不是**绕过 Command Layer 直接写文件，而是定时调用已有的 save 路径（ADR-0009 §3 / ADR-0013）。

### 2.3 依赖方向严格（沿用 Hard Rule 8）
`panels/` 可 import `editor/editor_coordinator.dart`，禁止 import `editor/` 下其他文件、`blocks/`、`chrome/`。
`chrome/` 仍禁止 import `blocks/` / `panels/`（TOC 面板属于 `panels/`，AppBar 通过 Coordinator 间接驱动面板开关）。

### 2.4 主题向后兼容（新增，对应 3.4.3 / ADR-0015）
`EditorTokens.xxx` 的所有现有调用方必须继续工作。主题切换通过 `ThemeExtension<EditorTokens>` 注入，不改变 token 常量名；迁移逐步进行，守门测试全跑。

### 2.5 避免 God Object（沿用 Phase 3.0 + ADR-0013）
TOC / 文件树逻辑落在 `panels/`，主题逻辑落在 `theme/`，自动保存落在独立 `AutosaveService`（**已定案，不再留 Coordinator 二选一**，见 ADR-0013）。`EditorCoordinator` 只协调，不持有 autosave timer / debounce 等业务状态。

### 2.6 旧 UI 不动（沿用 Phase 3.2）
`lib/presentation/screens/editor_screen.dart` 旧代码不修改。文件树若替换 `FileManagerScreen`，需评估旧 `screens/` 是否仍被路由引用（见 §9.3）。

---

## 3. 任务详细分解（要点）

### 3.1 3.4.1 TOC 大纲面板（P0）
- **数据来源**：遍历 `coordinator.allIds`，`getBlock(id)` 命中 `HeadingBlock` 时取 `level` + 渲染文本。
- **标题文本提取（强制）**：**复用现有 Markdown inline parser** 解析 heading source（如 `# **Hello** world` → 显示 `Hello world`，**不得**手写正则剥离 `**`）。Heading 的纯文本由 inline parser 渲染得到，unit 覆盖各级标题含 inline 格式。
- **交互**：AppBar 新增目录图标 → 打开 `TocPanel`（Drawer / overlay）。点击条目 → 聚焦对应块（`coordinator.focusBlock(id)` 或等价 API）+ 滚动到该块。
- **实时性**：`coordinator` 每次 `notifyListeners` 时 TOC 重建（或直接监听 `allIds` 变化）。

### 3.2 3.4.3 主题切换（P0，高风险重构，对应 ADR-0015）
- **重构**：`EditorTokens` 从 `static const` 类改为 `ThemeExtension<EditorTokens>`，由 `ThemeData.extensions` 注入；所有 `EditorTokens.textPrimary` 类调用改为 `EditorTokens.of(context).textPrimary`（或封装 `EditorTokens.of(context)`）。
- **inline 颜色边界**：`linkColor` 等 `TextSpan` 硬编码常量问题（见 `editor_tokens.dart` 注释）——TextSpan 不支持运行时 `Theme.of`。**本阶段边界**：仅保证 `Text` Widget 主题生效；inline 颜色一致性（同 Phase 3.3 §9.1 TextSpan 缩放边界）留后续 `Typography Refactor`，Issue 标 `wontfix` + `phase-3.4-typography`。不在本期顺手解决，否则切片膨胀。
- **主题清单**：`light`（默认）/ `dark`（Night）/ `sepia`。`Night` 对移动端阅读价值最高。
- **持久化**：用户主题偏好存 `SharedPreferences`（经 `sharedPreferencesProvider`，注意 AGENTS.md §3.2 同名 Provider 重复定义 bug 待处理）。

### 3.3 3.4.7 自动保存（P0，对应 ADR-0013）
- **机制（已定案）**：独立 `AutosaveService` 持有 debounce（dirty 后 1.5s），消费 `coordinator.isDirty`，触发**与手动保存共用**的 save 路径；`markSaved()` 后重置 timer。详见 ADR-0013。
- **用户反馈**：可选 toast / StatusBar 显示「已保存」（轻量，不阻断）。
- **Out of Scope（明确，避免误解）**：崩溃恢复（App 被杀且 dirty 未保存）→ 留 Phase 4+；云同步 / 多设备同步 → 依赖本服务 save 抽象，未来接入；历史版本 / 快照 → 未来在 save 之后追加，不在本期。

### 3.4 3.4.9 图片插入（P0，对应 ADR-0014）
- **流程**：工具栏 / `+` 菜单新增「图片」→ `file_picker` 选图 → **复制到文档目录 `assets/`** → **命名冻结为 `img_<uuid>.png`**（UUID，避免同步冲突）→ 插入 `![alt](assets/img_<uuid>.png)` 经 `InsertTextCommand` / `InsertTemplateCommand`。文档自包含，相对路径引用（见 ADR-0014）。
- **渲染**：`ImageElement` 已在 Phase 3.2 inline rendering 支持占位；本任务确保插入后落盘 + 重开一致（链 3 强制）。
- **删除语义（关键）**：块删除时**仅移除 Markdown 引用，不删 `assets/` 物理文件**（用户可立即 undo 恢复）；物理文件清理推迟到 Phase 4 的 Asset Garbage Collector（ADR-0014）。
- **完成判据（强制）**：不仅「插入成功」，必须 `关 App → 重开` 后三项同时成立——① markdown source 含 `![](assets/img_<uuid>.png)`；② 文件系统 `assets/img_<uuid>.png` 存在；③ 渲染出该图片。

### 3.5 3.4.8 页面宽度控制（P1，极简）
- `EditorViewport` 外层 `ConstrainedBox(maxWidth: 720)` + 居中。纯布局，无状态。可配合主题 / 设置持久化。

### 3.6 3.4.2 文件树面板（P1，较大）
- `SidePanelHost` → `FilePanel`：列出 `.md` 文件（复用 `FileService` / `DocumentService`）。
- **决策点**：是否替换现有 `FileManagerScreen`（路由 `/` 入口），或并存（Editor 内抽屉打开文件树，App 启动仍进文件管理屏）。见 §9.3。

### 3.7 3.4.4 导出进度反馈（P1）
- `EditorAppBar` 导出 action 调用导出服务时，监听进度回调（百分比 + 当前公式计数），以 `SnackBar` / `LinearProgressIndicator` 展示。

### 3.8 3.4.10 选区格式化菜单（P1，可选，高风险）
- 释放 Phase 3.3 §3.3.7 工具栏内置选区包裹模式，新增 `Overlay` 浮动菜单（加粗/斜体/行内代码/链接/删除线）。
- **风险**：Flutter `Overlay` + `TextSelection` + 光标坐标 + 滚动同步在三端行为不一致（Phase 3.3 已验证）。建议最后做或保持可选。

### 3.9 3.4.5 / 3.4.6 快捷键 / 打字机（P2，移 Phase 4）
- 源于桌面增强，手机 ROI 低。整体移入 Phase 4 Desktop Enhancement 子阶段实现，本契约不再跟踪。

---

## 4. 验证计划

沿用 Phase 3.3 §12 的**阶段级 E2E Gate** 模式（每个子任务独立 Gate：功能 → Unit → Arch → E2E → Review → Merge）。

### 4.1 自动化验证（每切片对应 unit + integration_test）
| 子任务 | unit test 文件 | E2E 文件 |
|--------|----------------|----------|
| 3.4.1 TOC | `test/presentation/panels/toc_panel_test.dart` | `integration_test/phase34_toc_test.dart` |
| 3.4.3 主题 | `test/presentation/theme/editor_tokens_ext_test.dart` | `integration_test/phase34_theme_test.dart` |
| 3.4.7 自动保存 | `test/presentation/editor/autosave_test.dart` | `integration_test/phase34_autosave_test.dart` |
| 3.4.9 图片 | `test/presentation/commands/image_insert_test.dart` | `integration_test/phase34_image_test.dart` |
| 3.4.8 页面宽度 | `test/presentation/editor/page_width_test.dart` | `integration_test/phase34_page_width_test.dart` |
| 3.4.2 文件树 | `test/presentation/panels/file_panel_test.dart` | `integration_test/phase34_file_tree_test.dart` |
| 3.4.4 导出进度 | `test/presentation/chrome/export_progress_test.dart` | `integration_test/phase34_export_test.dart` |

### 4.2 架构验证
- 依赖方向守门（Hard Rule 8 / TC-ARCH-UI-5~7）
- AST 零污染守门（grep `DocumentElement` 无 UI 字段）
- 主题向后兼容守门（`EditorTokens.xxx` 引用不破）
- God Object 守门（`editor_coordinator.dart` 不含 `Timer` / debounce；行数 ≤200）
- 无新增全局静态状态

### 4.3 E2E 三条链（沿用 §12.3）
- 链 1 用户操作链（UI → Command → Document）
- 链 2 状态同步链（Document → UI 重渲染）
- 链 3 持久化链：**强制范围** = 图片插入（3.4.9）/ 自动保存（3.4.7）/ 主题偏好（3.4.3 偏好需重开一致）/ 文件树（3.4.2 打开文件一致）。TOC（3.4.1）/ 页面宽度（3.4.8）/ 导出进度（3.4.4）为纯 UI/导航，豁免链 3。

### 4.4 E2E 平台矩阵（新增，提前定义避免每 PR 重争）

因 `integration_test` 在 Windows 桌面未启用 + Web 不支持，平台能力边界**预先固化**，禁止单 PR 临时争论「为什么 Windows 跑不了」：

| 测试能力 | Windows | Android Emulator | 说明 |
|----------|---------|------------------|------|
| TOC 跳转 | ✅ | ✅ | 纯 UI / 滚动，两端均可 |
| 主题切换 + 偏好持久化 | ✅ | ✅ | SharedPreferences 两端一致 |
| 自动保存落盘 | ✅ | ✅ | 文件 IO 两端一致 |
| 图片插入（file_picker） | ⚠️ 受限 | ✅ | Windows 无相册，需 mock picker 或跳过真选图 |
| IME / 中文输入 | ❌ | ✅ | 桌面未启用 + Web 不支持 |
| 双指缩放 | ❌（降级 smoke） | ✅ | 合成手势不稳定（Phase 3.3 §9.1 同源） |

- 标 ❌ 的能力：该 PR 的 E2E 在受限平台**允许降级**（smoke + 平台级验证 TODO），不阻塞合并；真机/模拟器验证在 Android Emulator sanity gate（Maestro / Patrol）补。
- 标 ⚠️ 的能力：Windows 用 mock `file_picker` 注入测试图片，不依赖真实相册。

---

## 5. 风险评估

| 风险 | 影响 | 缓解（含本版补强） |
|------|------|------|
| 主题重构破坏 `EditorTokens` 全量引用 | 高 | `ThemeExtension` + `EditorTokens.of(context)` 封装，逐步迁移；守门测试全跑（ADR-0015） |
| inline 颜色（TextSpan 常量）无法主题化 | 中 | 已知边界（同 3.3 §9.1），留 Typography Refactor，Issue `wontfix`（ADR-0015） |
| TOC 标题文本提取错误（如 `**bold**` 残留） | 中 | **复用 inline parser**，unit 覆盖各级标题含 inline 格式（§3.1） |
| 自动保存与手动保存竞争 / Coordinator 膨胀 | 中 | **已定案**：独立 `AutosaveService`（ADR-0013），God Object 守门 |
| 图片资产生命周期（跨设备 / 重开失效） | 高 | **已定案**：`assets/` 副本 + 相对路径，文档自包含（ADR-0014）；关 App 重开三项一致强制 |
| 文件树替换 FileManagerScreen 影响路由 | 高 | §9.3 先定替换/并存策略，守门路由测试 |
| 选区菜单 Overlay 三端漂移 | 高 | 建议最后做 / 保持可选，优先工具栏内置模式 |
| 快捷键/打字机手机 ROI 低 | 低 | §9.5 已定移 Phase 4 |

---

## 6. 成功标准（Phase 3.4 Exit Gate）

### 6.1 UI 验证
- [ ] TOC 面板打开显示标题大纲，点击跳转对应块（标题文本经 inline parser，格式正确）
- [ ] 主题切换（Night/Sepia）生效，Text Widget 整体换肤；偏好重开一致
- [ ] 修改后自动保存落盘，重开文档一致
- [ ] 图片从相册插入，渲染 + 落盘 + 重开一致（三项强制）
- [ ] 页面宽度限制生效
- [ ] （P1）文件树可浏览/打开 .md
- [ ] （P1）导出显示进度

### 6.2 架构验证
- [ ] 依赖方向守门通过
- [ ] AST 零污染
- [ ] 主题向后兼容（现有 `EditorTokens` 引用不破）
- [ ] 无新增全局静态状态
- [ ] God Object 守门：`editor_coordinator.dart` 不含 autosave timer / debounce，行数 ≤200

### 6.3 工程验证
- [ ] `flutter analyze` 0 error
- [ ] `flutter test` 0 regression（含 `integration_test/phase34_*.dart`）
- [ ] `flutter build apk --debug` 成功
- [ ] `flutter build web` 成功

### 6.4 文档验证
- [ ] ROADMAP.md Phase 3.4 状态更新
- [ ] ui-spec.md §7 Phase 3.4 checkbox 同步
- [ ] Phase 3.4 Verification Report 完成
- [ ] 本契约 + ADR-0013/0014/0015/0016 签字后提交（需 Human Owner 授权）

### 6.5 架构演进 Exit Gate（新增，防架构漂移）
Phase 3.4 最大风险不是 bug 而是架构腐化，额外增加三项硬性守门（CI / 守门脚本执行）：

1. **Coordinator 体积上限**：`editor_coordinator.dart` **严格 < 250 行**（Phase 3.3 守门 ≤200，Phase 3.4 放宽但不破 250）。超则必须拆出 `AutosaveService` / `LiveEditingState` / 面板协调逻辑。
2. **Service 边界禁令**：禁止 `autosave` / `theme` / `file` / `export` 业务逻辑进入 `EditorCoordinator`。Coordinator 只做协调 + 状态透传，具体能力落 `services/` / `theme/` / `panels/`。
3. **依赖图必须单向**：维持 `chrome → coordinator → domain`，禁止 `theme → blocks`、`panel → chrome`、`blocks → chrome` 等反向 / 跨层依赖。`panels/` 仅可 import `editor/editor_coordinator.dart`（Hard Rule 8）。

---

## 7. 回滚计划

- 单切片回滚：revert 对应 PR（按范围描述定位）。
- 主题重构回滚：恢复 `EditorTokens` 为 `static const`。
- 文件树回滚：恢复 `FileManagerScreen` 为路由入口。
- 自动保存回滚：移除 `AutosaveService` 注入，保留手动保存。
- 图片回滚：移除 `assets/` 副本逻辑，回退为纯文本插入。

---

## 8. PR 策略

- **每切片独立 PR + 独立分支**（`feat/phase3.4-<scope>`），遵循 AGENTS.md §5。
- AI 创建分支 / commit / 开 PR，**不 merge、不碰 main**（等 Human Owner review）。
- E2E Gate：每切片 PR 须含 feature + unit + arch + e2e，Gate 通过后才允许合入。

---

## 9. Human Owner 决策事项（待签字）

> 以下决策点需 Human Owner 在批准本契约时一并确认。每项给出推荐方案。

### 9.1 TOC 面板呈现形式
- **推荐**：手机端用 `Drawer` / overlay 覆盖（窄屏优先），AppBar 目录图标触发；不占持久布局宽度。
- 备选：持久侧栏（仅大屏 `width>=1024` 显示，复用 `SidePanelHost.shouldShow` 的 MediaQuery 条件）。
- **需确认**：overlay 还是持久侧栏（或两者按屏宽自适应）。

### 9.2 主题方案
- **推荐（已固化为 ADR-0015）**：`ThemeExtension<EditorTokens>` 注入（Material 3 标准做法），封装 `EditorTokens.of(context)`。
- 备选：Riverpod `themeProvider`（与现有 Provider 体系一致，但 `TextSpan` 仍拿不到 context；可作「选哪个主题」入口，与 ThemeExtension 不冲突）。
- **inline 颜色边界**：同 Phase 3.3 §9.1，本阶段仅保证 Text Widget 主题生效，TextSpan 一致性留后续 Typography Refactor，Issue `wontfix` + `phase-3.4-typography`。
- **需确认**：方案选择 + 是否接受 inline 颜色已知边界。

### 9.3 文件树 vs FileManagerScreen
- **推荐**：并存 —— Editor 内抽屉打开 `FilePanel` 切换文档；App 启动仍进 `FileManagerScreen`（保持现有入口，降低路由风险）。
- 备选：完全替换 `FileManagerScreen` 为 `FilePanel`（统一入口，但需改路由 + 处理旧 `screens/` 引用）。
- **需确认**：替换还是并存。

### 9.4 自动保存策略（**已定案，见 ADR-0013**）
- **决策冻结**：独立 `AutosaveService`，**不再留 Coordinator 二选一**。
- debounce 1.5s 落盘；消费 `coordinator.isDirty`；与手动保存共用 save 路径；`markSaved()` 后重置。
- Out of Scope：崩溃恢复 / 云同步 / 历史版本（留 Phase 4+）。
- **待确认（细节）**：定时时长是否微调 + 是否显示「已保存」轻提示。

### 9.5 快捷键 / 打字机是否移入 Phase 4
- **已定（推荐）**：整体移入 Phase 4 Desktop Enhancement 子阶段（手机 ROI 低）。本契约不再跟踪。
- **需确认**：是否同意移出（若同意，§10「移出」行可删）。

### 9.6 选区格式化菜单 Overlay
- **推荐**：保持可选 / 最后做（Phase 3.3 已验证高风险）；优先沿用工具栏内置选区包裹模式。
- 备选：本期实现 Overlay 浮动菜单。
- **需确认**：本期做 or 保持可选。

---

## 10. 切片执行顺序（v1.0，按评审微调）

> 每切片独立 PR。顺序原则：**先文档生命周期（自动保存），后 Presentation 层升级（主题）**；TOC 作为第一个真功能（底层能力验证）。

| 切片 | 任务 | 优先级 | 依赖 | 说明 |
|------|------|--------|------|------|
| **Sprint 0** | 补齐 Phase 3.3 延期 widget 测试（`editor_shell_test.dart` 4 场景）| — | 无 | 回填测试债，不计新功能 |
| **Slice 1** | 3.4.1 TOC 面板 | P0 | 无 | 脚手架就绪，低风险，第一个真功能；验证 block 遍历 / 滚动 / focus 联动 |
| **Slice 2** | 3.4.7 自动保存 | P0 | 无 | **先于主题**：基础文档生命周期能力（ADR-0013） |
| **Slice 3** | 3.4.3 主题切换 | P0 | 无 | 高风险 Presentation 重构，独立排期（需 §9.2 决策，ADR-0015） |
| **Slice 4** | 3.4.9 图片插入 | P0 | 无 | `file_picker` + `assets/` 副本（ADR-0014），中等 |
| **Slice 5** | 3.4.8 页面宽度 | P1 | 无 | 极简布局 |
| **Slice 6** | 3.4.2 文件树 | P1 | 无 | 较大，需 §9.3 决策 |
| **Slice 7** | 3.4.4 导出进度 | P1 | 无 | 依赖导出服务 |
| **Slice 8** | 3.4.10 选区菜单 | P1（可选） | 无 | 高风险，建议最后 |
| **（已移出）** | 3.4.5 / 3.4.6 | P2 | — | 移 Phase 4（§9.5） |

> 顺序可在签字时调整（如主题重构希望紧随 TOC，或图片插入优先于自动保存）。

---

## 11. 阶段级 E2E Exit Gate（沿用 Phase 3.3 §12 + 本版补强）

- 单个子任务完成标准：`功能实现 → Unit Test Pass → Architecture Gate Pass → E2E Pass（含平台矩阵 §4.4 降级规则）→ Human Review → Merge`。
- E2E 文件随功能 PR 一起提交（同一 PR 内含 feature + unit + arch + e2e）。
- 禁止多 P0 堆积实现后才统一补 `integration_test/`。
- 平台能力边界按 §4.4 矩阵预先固化，禁止单 PR 临时争论。
- Phase 3.4 整体 Exit Gate（§6）通过前提：每个子任务 E2E Gate 已先行通过，且架构演进 Exit Gate（§6.5）全绿。

---

**本文件为 v1.0（评审稿 v0.1 经 Human Owner 设计评审后升版），待 Human Owner 签字定稿并提交（架构决策类文件需授权）。关联 ADR-0013 / ADR-0014 / ADR-0015 同批提交。**
