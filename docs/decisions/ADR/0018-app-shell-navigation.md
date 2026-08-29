# ADR-0018：App Shell 导航与跨屏数据流（App Shell Navigation & Cross-Screen Data Flow）

> **状态**：Accepted（2026-08-30 批量追认——App Shell 导航已实施：StatefulShellRoute + 底部导航收敛（P0-2 后 2 tab））
> **版本**：v1.1
> **起草日期**：2026-07-29
> **起草人**：AI Agent 起草，Human Owner 评审决策
> **关联文档**：
> - [UI_SPEC.md](../../product/UX-GUIDE.md)（Screen 10 Home v3 / Screen 7 Files / Screen 8 Me / Bottom Tab Bar 视觉规范——本 ADR 不重复视觉细节，只冻结架构）
> - [ADR-0016 Document Repository Boundary](./0016-document-repository-boundary.md)（`DocumentRepository` 为文档生命周期唯一边界）
> - [ADR-0017 Design System Alignment](./0017-design-system-alignment.md)（颜色/字体单一真相源）
> - [AGENTS.md §4.2](../../../AGENTS.md)（UI 不得绕过 Provider 直接访问服务层）
>
> **审批路径**：Human Owner 在 PR #93 评审（2026-07-28）中指出五项设计层问题（数据访问不一致 / Tab 导航丢状态 / EditorTokens 角色漂移 / FileManagerScreen 直读 filesystem / 无跨屏刷新机制），本 ADR 冻结整改后的架构决策，供 Home / Files / Reader / Me 四屏共用。

---

## 版本修订记录

- **v1.0（2026-07-29）**：初版。冻结三项决策：① `StatefulShellRoute.indexedStack` 为 App Shell 唯一导航机制；② `documentListProvider`（Stream）为文档列表唯一跨屏数据源；③ `EditorTokens` 角色扩展为 app-wide design tokens。
- **v1.1（2026-07-29，Human Owner 二轮评审补强）**：① 新增 Decision 4「Shell 会话恢复」（`indexedStack` 只覆盖运行期，冷启动恢复策略此前缺失）；② 新增 Decision 5「Reader 语义冻结」（阅读空间 + `ReadingHistoryRepository` 数据边界，防退化为第二个 Files）；③ Decision 2 补派生 Provider 规则（禁止单一 Provider 统治所有查询）与统一 `AsyncValue` 三态 UI 契约（loading/error/data + empty）。

---

## 背景

### 当前状态

PR #93 首次引入产品级 App Shell（首页 + 底部 4 Tab 导航），此前应用只有编辑器单屏 + FileManagerScreen 兜底。初版实现存在五项架构缺陷（Human Owner 评审 1.1–1.5）：

1. **数据访问架构不一致**：HomeScreen 走 `fileRepositoryProvider`，FileManagerScreen 却 `getApplicationDocumentsDirectory()` + `Directory.listSync()` 直读 filesystem，违反 AGENTS.md §4.2 与 ADR-0016（`DocumentRepository` 是唯一边界）。
2. **Tab 导航丢状态**：`HomeTabBar` 用 `context.go('/home'|'/files'|...)` 切换，每次切 Tab 整棵子树重建，滚动位置 / 加载状态全部丢失。
3. **EditorTokens 角色漂移**：`EditorTokens` 语义上是编辑器 token，但 Home / Files / 占位页都在消费，职责未声明。
4. **FileInfo 直读文件名**：列表显示 UUID 文件名而非文档标题，因为绕过了 Repository 的元数据层。
5. **无跨屏共享/刷新机制**：Home 与 Files 各自一次性 `Future` 拉取，任何一屏增删文档，另一屏不会刷新。

### 触发本 ADR 的事件

Human Owner 评审指出：这是**产品级 UI 重构**，App Shell / 导航 / 跨屏数据流属于长期架构决策，必须先冻结文档，否则后续 Reader / Me / 搜索等屏落地时会再次各自发明数据通路与导航方式。

### 现有约束

- [ADR-0016](./0016-document-repository-boundary.md)：文档生命周期操作只能经 `DocumentRepository`；UI 层禁止 `File()` / `Directory()`（TC-ARCH-1/2 守门）。
- [ADR-0017](./0017-design-system-alignment.md)：Widget 禁止硬编码 `Color(0x...)`，颜色经 `EditorTokens.of(context)`，字体经 `AppTypography`。
- go_router 已是既定路由方案（`app_router.dart`）；Riverpod 已是既定状态方案。
- [UI_SPEC.md](../../product/UX-GUIDE.md) Screen 10/7/8：Bottom Tab Bar 为 4 等分 Tab（首页/文件/阅读/我的），Editor 与 Reader 阅读态为 Immersive（无 Tab Bar）。

---

## 决策

### 1. 导航：`StatefulShellRoute.indexedStack` 为 App Shell 唯一机制

```
GoRouter
├── StatefulShellRoute.indexedStack          ← App Shell（含底部 Tab Bar）
│   ├── branch 0: /home   → HomeScreen
│   ├── branch 1: /files  → FileManagerScreen
│   ├── branch 2: /reader → ReaderPlaceholderScreen
│   └── branch 3: /me     → MePlaceholderScreen
├── /editor/:id  → EditorScreen              ← Immersive，Shell 之外
└── /            → BootstrapScreen（重定向 /home 或 last-opened editor）
```

- **Tab 切换**只允许 `navigationShell.goBranch(index)`，**禁止** `context.go()`——`indexedStack` 保证各分支子树常驻，滚动位置与加载状态跨切换保留。
- 底部 Tab Bar 由 Shell 层 `HomeScaffold`（`home_shell.dart`）统一渲染，**各分支页面不得自带 Tab Bar**（初版占位页内嵌 HomeTabBar 属违规，已移除）。
- Editor / Reader 阅读态等 Immersive 屏注册在 Shell 之外的顶层 route，进入即全屏，返回自动回到原分支（indexedStack 状态未销毁）。

### 2. 数据流：`documentListProvider` 为文档列表唯一跨屏数据源

```
DocumentRepository (接口，ADR-0016)
  └── watchAllDocuments() → Stream<List<DocMetadata>>   ← 本 ADR 新增端口
        └── FileRepository 实现（documents/ 目录，updatedAt 倒序）
              └── documentListProvider = StreamProvider(...)
                    ├── HomeScreen（最近 3 篇 + 更早）
                    ├── FileManagerScreen（全量列表）
                    └── 未来：Reader 最近阅读 / 搜索
```

- 任何屏幕需要文档列表，**只能** `ref.watch(documentListProvider)`；禁止各自 `FutureProvider` / 一次性 `Future` / 直读 filesystem。
- 增删改文档后由 Repository 推送新列表事件，所有订阅屏幕自动刷新——跨屏一致性由数据源保证，不靠页面间通知。
- 列表项显示 `DocMetadata.title`（解析自文档内容/frontmatter），**禁止**显示物理文件名（UUID）。
- 该决策是 ADR-0016 的自然延伸：`watchAllDocuments()` 作为 `DocumentRepository` 的新端口冻结进接口。

**派生 Provider 规则（v1.1，防"一个 Provider 统治所有查询"）**：

- `documentListProvider` 是**全量列表的真相源**，不是所有查询的终点。屏幕专属视图必须以**派生 Provider** 表达，在 Provider 层做过滤/切片，UI 不做业务过滤：

```
documentListProvider（全量，Stream ← Repository）
  ├── recentDocumentsProvider     ← Home「最近」区（take(3)）
  ├── earlierDocumentsProvider    ← Home「更早」区（skip(3)）
  └── 未来：favoriteDocumentsProvider / searchResultsProvider
```

- 派生 Provider **只能**从 `documentListProvider`（或 Repository 新端口）派生，禁止旁路自建数据通路。
- **规模上限预警**：当文档量增长到全量内存列表不可承受（参考阈值 ~1000 篇）或搜索需要索引时，在 `DocumentRepository` 增加带查询参数的端口（如 `watchDocuments(query)` / 独立索引服务），派生 Provider 改接新端口——**UI 层不感知**该迁移。该演进记入新 ADR，不在本 ADR 冻结实现。

**统一异步 UI 状态契约（v1.1）**：

- 所有消费文档列表的屏幕必须完整处理 Riverpod `AsyncValue` 三态 + 空态，**禁止**各屏自行发明状态枚举：

| 状态 | 判定 | UI 要求 |
|---|---|---|
| loading | `AsyncValue.isLoading`（首帧无数据） | 骨架屏或居中 loading，禁止空白帧 |
| error | `AsyncValue.hasError` | 可见错误提示 + 重试入口；**禁止静默 catch 吞错**（评审 2.1） |
| data + empty | `value.isEmpty` | 空状态引导（视觉见 UI_SPEC 对应 Screen） |
| data | 非空列表 | 正常渲染 |

- 空态/错误态的视觉规范归 UI_SPEC；本 ADR 只冻结「四态必须齐全、由 `AsyncValue` 承载」这一契约。测试须覆盖四态（override provider 注入）。

### 3. Token：`EditorTokens` 角色扩展为 app-wide design tokens

- **决策**：不拆分 `AppTokens`。`EditorTokens` 正式声明为**全应用** design token 载体（历史名称保留，避免大范围重命名破坏 Tier 1-3 测试基线），在类 doc comment 中注明"app-wide，非仅编辑器"。
- 理由：tokens.json 本就是全产品单一真相源（ADR-0017）；Home/Files 与编辑器共享同一套 paper/primary/accent 语义色，拆两套 ThemeExtension 只会制造第二真相源。
- 若未来非编辑器屏出现编辑器不需要的 token（如 Tab Bar 专属色），先加进 `EditorTokens`；仅当编辑器专属字段占比失衡时再评估拆分（记新 ADR）。

### 4. Shell 会话恢复（Session Restoration，v1.1）

`indexedStack` 只解决**运行期**的 Tab 状态保持；App 被杀后台后冷启动，Shell 状态归零。冻结如下恢复策略：

- **恢复层级（冻结）**：

| 层级 | 是否恢复 | 机制 |
|---|---|---|
| 上次所在 Tab（branch） | ✅ 恢复 | `lastShellBranchProvider`：`goBranch` 时持久化 branch index（走既有 Settings/Storage 通路，与 last-opened doc 同级） |
| 上次打开的文档（Editor） | ✅ 恢复（既有） | BootstrapScreen last-opened 逻辑不变，**优先级高于 Tab 恢复**——上次在编辑器内被杀，重启直接回编辑器 |
| Tab 内滚动位置 | ❌ 不恢复（P2 optional） | 收益低、实现重（需 PageStorage 持久化）；用户重启后从列表顶部开始是可接受心智 |

- **启动决策链（BootstrapScreen）**：`last-opened doc 存在且有效 → /editor/:id`；否则 `lastShellBranch 有值 → /home shell + goBranch(saved)`；否则 `→ /home（branch 0）`。
- 持久化值损坏/越界时静默回退 branch 0，不报错不崩溃。
- 示例场景（评审用例）：用户在 Files 滚动到深处 → 杀后台 → 重启 → **恢复到 Files Tab 顶部**（不是 Home，也不承诺滚动位置）。

### 5. Reader 语义冻结（v1.1）

**Reader = 阅读空间（Reading Space），不是文件管理，不是收藏列表。** 防止其退化为「第二个 Files 页」的产品风险，冻结三屏职责边界：

| Tab | 回答的问题 | 数据源 |
|---|---|---|
| Home | 「我最近在**写**什么？」 | `documentListProvider`（按 updatedAt） |
| Files | 「我的**全部**文档在哪？」 | `documentListProvider`（全量管理：增删改） |
| Reader | 「我最近在**读**什么？读到哪了？」 | `ReadingHistoryRepository`（**独立数据边界**） |

- **数据边界（冻结接口意向，实现随 Reader 落地）**：新建 `ReadingHistoryRepository`，记录阅读行为而非文档本体：

```dart
class ReadingRecord {
  final String docId;        // 关联 DocMetadata
  final DateTime lastReadAt; // 最近阅读时间
  final double progress;     // 阅读进度 0.0–1.0
  final List<Bookmark> bookmarks; // 书签（可选，v1 可空实现）
}
```

- Reader Tab 列表按 `lastReadAt` 排序、显示进度（对齐 UI_SPEC Screen 13「阅读进度 66%」）；点击进入 Immersive 阅读态（Shell 之外，Decision 1）。
- **守门**：Reader 屏禁止提供增删改文档能力（那是 Files 的职责）；Reader 列表数据源禁止直接是 `documentListProvider` 全量（必须经阅读历史 join）。
- 当前 PR #93 阶段 Reader 保持 Placeholder，但占位文案须与本语义一致（「阅读空间」而非「文件」），避免用户形成错误心智。`ReadingHistoryRepository` 的持久化格式（建议：`.workbuddy` 外独立 JSON/DB，不污染 .md 单一真相源，遵守 ADR-0003）在 Reader 实现 PR 时定案并修订本 ADR。

---

## 被否决的方案

| 方案 | 否决理由 |
|---|---|
| `context.go` + 手写 Tab 高亮（初版） | 每次切 Tab 重建子树，丢滚动/加载状态；Human Owner 评审 1.2 否决 |
| `BottomNavigationBar` + 本地 `IndexedStack`（不经 router） | 深链（如通知打开 /files）无法定位 Tab；与 go_router 双真相源 |
| 各屏独立 `FutureProvider` 拉列表 | 跨屏不同步（评审 1.5）；刷新时机不可控 |
| 新建 `AppTokens` 与 `EditorTokens` 并存 | 双真相源，违反 ADR-0017 精神；重命名成本高收益低 |
| 冷启动一律回 Home（不恢复 Tab） | 用户在 Files/Reader 工作中被系统杀后台，重启回 Home 打断心智；恢复成本仅一个持久化 int |
| 冷启动恢复滚动位置 | 实现重（PageStorage 持久化 + 列表数据先就绪）、收益低；降为 P2 optional |
| Reader 数据直接复用 `documentListProvider` | Reader 会退化为第二个 Files 页（产品风险）；阅读历史是行为数据，与文档元数据边界不同 |
| 单一 `documentListProvider` 承担所有查询（Home/Files/Reader/Search） | 全量列表随文档增长过重；派生 Provider + Repository 查询端口是正确演进路径 |

---

## 影响与守门

- **TC-ARCH-1/2**（既有）：presentation 禁 `File()`/`Directory()`——FileManagerScreen 的 `listSync()` 整改后由该守门防回归。
- **新增约定（TC-ARCH-UI-8 候选）**：`presentation/screens/` 内禁止出现 `context.go('/home')` 等 Shell 分支路径字面量；Tab 切换只经 `goBranch`。
- **测试要求**（评审 3.2 + v1.1）：Home 空状态 / loading / error / 最近-更早分区 / 三主题渲染 / 底栏跳转保状态，用 `documentListProvider` override 注入假数据覆盖四态；Shell 恢复策略补 BootstrapScreen 决策链单测（last-opened doc / lastShellBranch / 兜底 branch 0 / 损坏值回退）。
- **PR #93 落地范围**：Decision 1/2/3 + Decision 4 的 `lastShellBranchProvider` + Decision 2 的四态契约与 recent/earlier 派生 Provider。Decision 5 的 `ReadingHistoryRepository` 属 Reader 实现 PR 范围，本 PR 只落占位文案语义。
- 后续 Reader / Me 真实实现必须复用本 ADR 的通路，不得另起炉灶。
