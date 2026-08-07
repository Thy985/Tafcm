# FormulaFix UI 还原度与 AppShell 进度状态

> **状态**：DRAFT（待评审）　**版本**：v1.0　**日期**：2026-07-30
> **基准**：`origin/main` = `5a481fc`
> **令牌真源**：`design-system/tokens.json` v1.0.0（来自 `formulafix-redesign.design`）
> **方法**：只读静态审计（全局检索 + 关键文件行号核实），未改动任何文件。

> **状态更新（2026-08-06，基于代码实况核实）**
>
> 本文档反映 2026-07-30 的审计基线。以下缺口已通过 UI 修复 PR 落地，更新摘要详见 `docs/UI_FIX_PLAN.md` 头部"进度同步"表：
>
> | 章节 | 缺口 | 当前状态 | 修复证据 |
> |------|------|---------|---------|
> | §1 shadow 维度 | 暗色阴影失效（明暗同值） | ✅ 已修复（PR-A #109） | `app_constants.dart:71-77` 分 light/dark 套 |
> | §1 component 维度 | `toggle/searchPill/ghost/fab` 0 实现 | ✅ 已实现（PR-F #117） | `buttons.dart` 4 组件 + 单测 |
> | §2 side_panel_host | 占位死代码 | ✅ 已删除（PR-F #117） | Glob 找不到 `side_panel_host.dart` |
> | §4 Top 缺口 #1 | 首页无 golden + 搜索占位 | ✅ golden 已补（PR-C #111）/ 🟡 搜索占位仍 `SnackBar` | `home_screen_*_test.dart` 已建 |
> | §4 Top 缺口 #2 | dark 阴影失效 | ✅ 已修复（PR-A #109） | 同上 |
> | §4 Top 缺口 #3 | 4 组件规格 0 实现 | ✅ 已实现（PR-F #117） | 同上 |
> | §4 Top 缺口 #4 | 侧栏占位死代码 | ✅ 已清理（PR-F #117） | 同上 |
> | §4 Top 缺口 #5 | spacing/radius 令牌未集中 | ✅ 已提交（PR-E #116） | `AppSpacing` 补全 7 项命名令牌 |
> | §4 Top 缺口 #6 | 主题切换无 golden + 字号令牌缺 | ✅ golden 已补（PR-C #111）/ 🟡 字号令牌部分补（PR-E #116） | — |
> | §4 Top 缺口 #7 | "双状态栏"观感（抄设备装饰） | ✅ 已修复（PR-G #108） | `home_screen.dart:31` `SafeArea(top:false, bottom:true)` |
> | §5 守门建议 | Golden 矩阵扩充 | ✅ 已扩充（PR-C #111） | `home_screen` 三主题 + 多尺寸 golden |
>
> **仍未完成项**：PR-Fb（首页 `_RoundButton`→`GhostButton` 接线 / 搜索栏接 `SearchPill` / P2-3 主题色 swap）+ PR-H（P3 颜色语义化长期治理）。

---

## 0. 结论速览

**AppShell 骨架与真实数据接入做得不错**——编辑器、文件管理、工具栏、状态栏、顶栏、底部 Tab、主题切换（light/dark/sepia 持久化）均已 ✅ 或 🟡。

**设计系统的"系统化落地"偏弱**——暗色阴影失效、spacing/radius 命名令牌未集中、toggle/searchPill/fab 等组件规格整体缺失，且**首页整页与主题切换效果缺乏 golden 守护**。

| 模式 | 综合还原度估算 |
|---|---|
| 亮色（light） | ≈ 70%（颜色/字体/组件骨架到位，spacing/radius/阴影规格未完全对齐） |
| 暗色（dark） | ≈ 50%（受 `shadow.dark` 未接入、暗色 accent 缺失拖累） |
| 护眼（sepia） | ≈ 55%（主题已落地，但组件规格与暗色同款缺口） |

---

## 1. 设计令牌还原度（对照 `tokens.json`）

落地 = 有对应 Dart 字段 / Widget 真正消费；部分 = 仅近似或仅 light；缺失 = 代码无对应实现。

| 维度 | 落地率 | 已落地 | 关键缺口 |
|---|---|---|---|
| **color** | ≈85% | light/dark/sepia 主色+表面色+语义色基本覆盖（`app_theme.dart:20-34`、`editor_tokens.dart`） | 暗色/护眼 `accent`(#F4A261)未落地（`app_constants.dart:37` 仅 light）；editor 表面色非令牌化（`app_theme.dart:44/88` 近似 scaffold） |
| **radius** | ≈50% | `sm=6`(`editor_tokens.dart:220,223`)、`md=10`(`app_theme.dart:55,99,131`) | `lg=16`/`xl=24` 从未使用；输入框用 `8`(`app_theme.dart:61`) 非令牌值；`AppSpacing.cardRadius=12` 非令牌标准 |
| **shadow** | ⬜ 关键缺陷 | 亮色单一阴影 `AppShadows.card`(`app_constants.dart:71-77`) | **明暗同值**（`app_constants.dart:73` 写死 `isDark ? black : black`）→ 暗色阴影完全失效；`shadow.dark` 四档（0.3~0.6）未接入 |
| **typography** | ≈87% | 13/15 字号命中：editorBody15、readerBody16、h1~h2、sectionHeader、cardTitle、body、meta、formulaDisplay19、statusBar11、tabLabel(`app_typography.dart`、`editor_tokens.dart:203,212,215`) | `caption=10` 无令牌（最小 11）；`formulaDisplayReader=21` 无阅读变体（`app_typography.dart` 公式固定 19）；tabLabel 在 `home_tab_bar.dart:115` 硬编码而非令牌 |
| **spacing** | ≈36% | `pageHorizontal24`(`editor_tokens.dart:198`)、`paragraphGap20`(`:189`)、`statusBarHeight32`(`:228`)、`cardPadding16`(`app_constants.dart:51`) | `readerHorizontal28`/`cardGap12`/`sectionGap24`/`fabBottomOffset88`/`topBarHeight48`(实际 kToolbarHeight=56)/`bottomSheetMaxHeight88vh` 全无名令牌；`tabBarHeight64` 仅 `home_tab_bar.dart:22` 局部常量 |
| **component** | ≈50% | `button.primary`(`app_theme.dart` elevatedButtonTheme)、`tabBar`(`home_tab_bar.dart`)、`formulaBlock`(`formula_block.dart`，按 `_note` 故意无卡片)、`card`/`bottomSheet`/`progressBar` 近似 | **`toggle`/`searchPill`/`ghost`/`fab` 0 实现**（grep 确认全仓无 `FloatingActionButton`）；`button.secondary` 未主题化；首页搜索仅 `SnackBar('搜索即将上线')`(`home_screen.dart:138`) |

---

## 2. AppShell 组件进度

| 组件 | 状态 | 关键事实 | 位置 |
|---|---|---|---|
| `home_screen`（首页/文档库） | 🟡 部分 | 真实数据 `documentListProvider` + `recent/earlierDocumentsProvider`；空态/新建/打开真实；**搜索为占位 SnackBar** | `home_screen.dart:26,55-56,138` |
| `editor_shell`（编辑器外壳） | ✅ 完整 | AppBar+MarkdownToolbar+Workspace+StatusBar+TOC 抽屉+文件树侧栏+字号缩放+焦点模式，逻辑齐备 | `editor_shell.dart:170-268` |
| `editor_screen`（旧版） | 🟡 legacy | 单 TextField 编辑器，被 `editor_shell` 取代的 fallback | `editor_screen.dart` |
| `file_manager_screen` | ✅ 完整 | 真实列表、删除确认、空态 | `file_manager_screen.dart:51-115` |
| `home_tab_bar`（底部 Tab） | ✅ 完整 | 4 tab、active 用 primary、iOS home indicator | `home_tab_bar.dart:24-29,65-74` |
| `editor_app_bar`（顶部栏） | ✅ 完整 | 标题、dirty 点、Undo/Redo、TOC、文件树、**主题循环图标**、焦点模式、导出菜单 | `editor_app_bar.dart:140-144,221-233` |
| `markdown_toolbar` | ✅ 完整 | 11 按钮+溢出菜单+模板+图片，全经 Intent 派发 | `markdown_toolbar.dart:119-157` |
| `editor_status_bar` | ✅ 完整 | 块数/字数/Undo-Redo 态/缩放控件 | `editor_status_bar.dart:55-66` |
| `side_panel_host`（侧栏） | ⬜ 占位死代码 | `shouldShow` 恒返回 false；真实侧栏已由 `FileTreePanel`/`TocPanel` 在 `editor_shell` 另实现，原 host 未清理 | `side_panel_host.dart:38-42` |
| **主题切换入口** | ✅ 完整 | `themeModeProvider`(light/dark/sepia 持久化)+ `cycle()`；首页头部/编辑器 AppBar/旧版 popup 三处可切换，sepia 已落地 | `editor_providers.dart:14-56` |
| 首页/编辑器真实数据 | ✅ | 首页 `documentListProvider` 真实；EditorShell 用真实 `EditorCoordinator` | — |

---

## 3. Golden 守护现状

### 已锁定（像素比对，共 10 张）
- `editor_shell_full_page_light.png`（`editor_shell_full_page_light_test.dart:66`）
- `formula_block_light/dark/sepia.png`（3 张）
- `paragraph_light/dark.png`（2 张）
- `heading_light`、`inline_formula_light`、`markdown_toolbar_light`、`code_block_light`

### 缺失关键 AppShell 画面（回归盲区）
- ❌ **`home_screen` 整页**：无测试文件、无 png（**最大盲区**）
- ❌ `home_tab_bar` 底部导航：无 golden
- ❌ `file_manager`：png 存在但 `file_manager_test.dart:81-83` 已**注释禁用** `matchesGoldenFile`（潜伏 golden）
- ❌ `editor_screen`（旧版）整页：无 golden
- ❌ 主题切换后效果：dark/sepia 的 home/editor 整页无 golden
- ❌ status bar / bottom_sheet / 导出菜单 / reader·我的 占位屏 独立 golden

---

## 4. Top 缺口（按严重度）

1. **⬜ 首页无 golden + 搜索占位** — `home_screen` 整页无像素回归（`home_screen.dart:136-140` 搜索为 SnackBar），`searchPill` 组件规格完全未实现 → 设计稿首页还原度无法守护。
2. **❌ shadow 体系未落地，dark 阴影失效** — `AppShadows.card` 明暗同值（`app_constants.dart:73`），`shadow.dark` 四档未接入 → 暗色模式视觉明显偏离令牌。
3. **⬜ toggle / searchPill / ghost / fab 组件规格 0 实现** — 设计稿有定义（`tokens.json:164-178,196-217`），代码中无对应 Widget，编辑/首页交互层缺失这几类标准控件。
4. **⬜ 侧栏 `side_panel_host.dart` 占位死代码** — `shouldShow` 恒 false（`side_panel_host.dart:38-42`）；真实侧栏已在 `editor_shell` 另实现，原 host 未清理，且无入口发现性。
5. **🟡 spacing 命名令牌几乎未集中 + radius.lg/xl 未用** — `readerHorizontal/cardGap/sectionGap/topBarHeight/fabBottomOffset/bottomSheetMaxHeight` 全缺（`tokens.json:130-142`），`radius.lg=16/xl=24` 无消费 → 间距/圆角还原度低且不可主题统一。
6. **❌ 主题切换后无 golden 守护 + 个别字号缺令牌** — dark/sepia 整页渲染回归无测试；`caption(10)`、`formulaDisplayReader(21)` 无令牌 → 护眼/夜间模式与阅读态公式规格存在偏差。
7. **❌ 首页"双状态栏"观感（抄了设计稿设备装饰）** — 设计稿 `home-v3.html:233-257` 画了 `<!-- Status bar -->` 装饰条（9:41 + Signal/Wi-Fi/Battery SVG），是**设计工具占位**，真机由系统提供；当前 `home_screen.dart:31` `SafeArea(top:true)` 为这条占位预留顶部空间 → 视觉上像 APP 也画了一个状态栏（用户反馈 2026-07-30：这是**设计问题不是技术问题**，不应抄上，只留系统状态栏）。**修复**：`SafeArea(top:false)` 让内容顶到最顶，系统状态栏透明叠加在纸色背景上，视觉仅一个系统状态栏。

---

## 5. 建议修复路线（优先级）

### P0（视觉正确性，必须修）
- **R2 暗色阴影失效**：将 `AppShadows.card` 改为按 `isDark` 取 `shadow.dark` 四档（`app_constants.dart:71-77`）；建立 `AppShadows` 完整令牌（sm/md/lg/xl × light/dark）。
- **R1 首页 golden + 搜索**：补 `home_screen` 整页 golden（light/dark/sepia）；搜索占位先接 `searchPill` 规格或标注 TODO 路线。
- **R7 不抄设计稿设备装饰，只留系统状态栏**：`home_screen.dart:31` `SafeArea(top:true)` → `SafeArea(top:false, bottom:true)`（顶部不再为设计稿状态栏占位预留空间，内容顶到最顶，系统状态栏透明叠加在纸色背景上，视觉仅一个系统状态栏）；**设计还原铁律：不复制状态栏/home indicator/刘海等设备装饰**（grep 确认 `lib/` 无 9:41/电池/信号字样，本就未画）。推荐增强：注入 `AnnotatedRegion<SystemUiOverlayStyle>` 让系统状态栏图标随 light/dark/sepia 翻转（暗色下可见），不画状态栏、不冲突。

### P1（系统化落地）
- **R5 spacing/radius 集中化**：新增 `AppSpacing`/`EditorTokens` 缺项（readerHorizontal/cardGap/sectionGap/topBarHeight/fabBottomOffset/bottomSheetMaxHeight），消费 `radius.lg/xl`。
- **R6 字号令牌补全**：加 `caption=10`、`formulaDisplayReader=21` 到 `AppTypography`；`home_tab_bar` 的 tabLabel 改走令牌。

### P2（组件规格 + 清理）
- **R3 组件 Widget**：实现 `toggle`/`searchPill`/`ghost`/`fab`（FloatingActionButton）并接令牌；首页 `_RoundButton`(`home_screen.dart:184`) 收敛为 ghost 规格（size 36）。
- **R4 清理死代码**：删除/归档 `side_panel_host.dart` 占位（真实侧栏已在 `editor_shell` 实现），或显式标注 deprecated。

### 守门建议
- 扩充 `test/golden` 矩阵：新增 375×812（手机）、834×1112（平板）尺寸变体 + `textScaleFactor=1.3`，并对 `home_screen`/`editor_shell`/`file_manager` 补 dark/sepia 变体；恢复 `file_manager` golden 断言。
- 新增静态守门：断言 `AppShadows` 明暗分支不同值、spacing 命名令牌覆盖率（可选）。

---

## 6. 附录：关键文件速查

| 关注点 | 文件:行 |
|---|---|
| 暗色阴影失效 | `lib/core/constants/app_constants.dart:71-77`（`:73` 明暗同值） |
| 暗色 accent 缺失 | `lib/core/constants/app_constants.dart:37` |
| radius 输入框非令牌 | `lib/presentation/theme/app_theme.dart:61` |
| 字号分裂冲突 | `AppSpacing.body=16`(`app_constants.dart:59`) vs `EditorTokens.paragraphFontSize=15`(`editor_tokens.dart:203`) |
| 首页搜索占位 | `lib/presentation/screens/home_screen.dart:138` |
| 侧栏占位死代码 | `lib/presentation/panels/side_panel_host.dart:38-42` |
| 主题切换 | `lib/presentation/editor/editor_providers.dart:14-56` |
| 首页"双状态栏"观感（抄设备装饰） | 设计稿 `home-v3.html:233-257`（`<!-- Status bar -->` 装饰条）；`home_screen.dart:31` `SafeArea(top:true)` 为其预留顶部空间；`lib/` 无 9:41/电池/信号字样（未真画） |
| Golden 基础设施（单尺寸） | `test/golden/golden_helpers.dart:51,46` |
| 文件管理器 golden 禁用 | `test/golden/file_manager_test.dart:81-83` |

---

*本状态文档基于 2026-07-30 的只读审计生成，反映 `origin/main` = `5a481fc` 时刻的 UI 还原度与 AppShell 进度。后续改动请同步更新本表。*
