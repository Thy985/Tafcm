# FormulaFix UI 修复实施计划（UI_FIX_PLAN）

> **状态**：v1.1（进度同步）　**版本**：v1.1　**日期**：2026-07-31
> **基准**：`origin/main` = `0715de5`（PR-D #112 合并点；基础设施 PR #113 待合并）
> **配套文档**：`docs/UI_STATUS.md`（UI 还原度与 AppShell 进度现状）
> **来源**：两轮只读审计 —— ① 技术适配质量审计；② 设计还原度 + AppShell 进度审计
> **方法**：每项含 问题 / 位置（文件:行）/ 改法 / 验证 / 建议 PR。不改动代码，待评审后分批实施。

---

## 0. 修复总览

| 来源 | 维度 | 代表缺口 |
|---|---|---|
| 适配审计 | 安全区 / 响应式 / Golden 矩阵 | 主屏底部 SafeArea 缺失（顶部已由 AppBar 接管，防 double-inset）、无断点体系、Golden 仅单尺寸 |
| 还原度审计 | 令牌系统化落地 | 暗色阴影失效、spacing/radius 未集中、toggle/fab 等组件缺失 |
| **用户反馈 (7/30)** | **抄设计稿设备装饰** | **设计稿 `home-v3.html:233-257` 画了 `<!-- Status bar -->` 装饰条（9:41 + Signal/Wi-Fi/Battery SVG），这是设计工具占位；真机由系统提供。当前 `home_screen.dart:31` `SafeArea(top:true)` 为这条占位预留顶部空间 → 视觉上像"双状态栏"（系统真 + APP 占位）。APP 不应抄上此装饰。** |

**综合优先级**：P0（视觉正确性/回归守护）→ P1（系统化落地）→ P2（组件规格 + 清理）

### 设计还原铁律（来自用户反馈 7/30）

> **不抄设计稿的"设备装饰"**：设计稿（`.design/pages/*.html`）中的状态栏、home indicator、刘海、手势条等是**设计工具的展示占位**，不代表 APP 要实现的功能 UI。真机上这些由操作系统提供，APP 只负责**内容区 + 必要的 `SafeArea` 内缩**。
>
> - 还原首页/编辑器时，**不要**为设计稿的状态栏占位预留/复制任何高度或组件（grep 确认 `lib/` 无 9:41/电池/信号字样，本就未画；但 `SafeArea(top:true)` 的留白在视觉上对应此占位，需改为 `top:false` 让内容顶到最顶）。
> - 系统状态栏本身**保留**（iOS 无法隐藏，Android 也不应隐藏）——只让内容贴顶、状态栏透明叠加在内容背景色上，视觉上"仅一个系统状态栏"。
> - 例外：若某屏真的需要自定义顶部栏（如编辑器 AppBar），那是**功能 UI**，不是设备装饰，正常实现；但顶栏之上的系统状态栏仍由系统提供，二者不冲突（顶栏通过 `systemOverlayStyle` 让系统状态栏图标适配主题即可）。
**建议 PR 拆分**（改动面大，避免单巨 PR 难 review）：

| PR | 内容 | 关联项 | 状态 |
|---|---|---|---|
| PR-A | 暗色阴影令牌体系 | P0-1 | ✅ 已合并 #109 |
| PR-B | 主屏 SafeArea | P0-3（适配） | ✅ 已合并 #110 |
| PR-C | 首页 golden + Golden 矩阵扩充 | P0-2 + P1-4 | ✅ 已合并 #111 |
| PR-D | 响应式断点体系 | P1-1（适配） | ✅ 已合并 #112 |
| PR-E | spacing/radius/字号令牌集中化 | P1-2 + P1-3 | ✅ 已提交 PR #116（像素中性，待合并） |
| PR-F | 组件 Widget + 死代码清理 + 即时颜色项（仅影响主题的黑/白） | P2-1/2 + P2-3收窄 | 🟡 已提交 PR（feat/pr-f-components-cleanup，像素中性部分；接线/颜色延后 PR-Fb） |
| PR-G | 不抄设计稿设备装饰（首页 `SafeArea(top:false)` 只留系统状态栏） | P0-4 | ✅ 已合并 #108 |
| PR-H | 颜色语义化长期治理（独立排期，逐文件小 PR） | P3 | ⬜ 待启动（长期） |

> **当前进度总览（2026-08-01 同步）**：UI 修复 **P0 全部完成**、**P1 完成 3/4**（响应式 #112 + Golden 矩阵 #111 + 令牌集中化 #116 待合并）、**P2 进行中（PR-F 组件+死代码已提交，像素改动延后 PR-Fb）/ P3 未启动**。
> - ✅ 已合并（5 个）：`#108`(P0-4) `#109`(P0-1) `#110`(P0-3) `#111`(P0-2 + P1-4) `#112`(P1-1)
> - 🟡 已提交待合并（2 个）：`#116`(PR-E: P1-2/P1-3 令牌，像素中性)、PR-F(`feat/pr-f-components-cleanup`: P2-2 死代码 + P2-1 四个令牌化组件，像素中性；接线/颜色延后 PR-Fb)
> - ⬜ 待做（按顺序）：`PR-Fb`（PR-F 延后：首页 `_RoundButton`→`GhostButton` 接线、搜索栏接 `SearchPill`、P2-3 主题色 swap，均需 WSL 补 golden）→ `PR-H`(P3 颜色语义化长期治理)
> - 🔶 基础设施（非 UI 修复）：`#113` Repository Safety Layer（git 仓库防损坏护栏）**OPEN**，待合并 + 批准 `AGENTS.md` §12/§7 架构决策修改（详见下方"基础设施 PR"）

### 基础设施 PR（独立于 UI 修复，2026-07-30 新增）

| PR | 内容 | 关联项 | 状态 |
|---|---|---|---|
| PR-I（基础设施） | Repository Safety Layer：`.agent/` 安全层（REPO_POLICY/ENVIRONMENT/GIT_RULES/COMMAND_SAFETY + `guard.sh`）+ `.gitignore` 修正 + `.gitattributes` 根治 CRLF + `AGENTS.md` §12/§7 退役标注 | —（协作基础设施） | 🔶 OPEN #113（待合并 + 批准 AGENTS.md 架构决策修改） |

> **背景**：7/30 仓库因 `rsync --delete` 目标塌缩为 `/` 删除 `.git` 等事故后，复盘结论是"问题不在 git，而在协作基础设施缺位"。本 PR 把安全规则从会话记忆外化为仓库内文件 + 机器校验（pre-push 拦嵌套 `.git`、危险命令三前置）。**本 commit 全程用原生 git 完成，作为"git 底层绕过术退役"的实地验证**。详见 PR #113 描述与评论。

> 文档类（`UI_STATUS.md` + 本文件）与代码修复 PR 独立；用户审核后 `UI_STATUS.md` + `UI_FIX_PLAN.md` 一并提交。

---

## 1. P0 — 视觉正确性与回归守护

### P0-1 暗色阴影失效（还原度 Top 2）

- **问题**：`AppShadows.card` 明暗写死同值，暗色模式下阴影不可见，整体视觉偏离令牌。
- **位置**：`lib/core/constants/app_constants.dart:71-77`（`:73` `isDark ? black : black`）；令牌 `design-system/tokens.json:85-96`（`shadow.dark` 四档 0.3~0.6）。
- **改法**：
  1. 在 `AppShadows` 新增 `light`/`dark` 两套 `sm/md/lg/xl`，对齐 `tokens.json`（alpha 用令牌值，非写死）。
  2. 消费点改为按 `Theme.of(context).brightness` 取对应套；或封装 `AppShadows.of(context)`。
  3. 暗色 `shadow.dark` 四档全部接入（当前代码无对应）。
- **验证**：新增/更新暗色 golden（如 `editor_shell_full_page_dark`、`paragraph_dark` 已存在可复用，扩到 home/file_manager）；真机暗色截图比对。
- **注意**：会改变所有暗色 golden 像素 → 需 `flutter_app/tool/wsl_golden.sh --update` 重基线（WSL 与 CI 同环境）。

### P0-2 首页整页 golden + 搜索占位（还原度 Top 1）

- **问题**：`home_screen` 整页无像素回归（最大盲区）；搜索为占位 `SnackBar`。
- **位置**：`lib/presentation/screens/home_screen.dart:136-140`（搜索 SnackBar）；`:26,55-56`（`documentListProvider` 真实数据）。
- **改法**：
  1. 新增 `test/golden/home_screen_light_test.dart` 等，pump `HomeScreen` 经 `ProviderScope` + 固定尺寸，生成 light/dark/sepia 三张 golden。
  2. 搜索：短期在 `home_screen.dart:138` 标注 `// TODO(UI): 接 searchPill 规格 tokens.json:211-217`；中期实现 `searchPill` 组件（见 P2-1）。
- **验证**：golden 新增 + 测试通过；空态/有文档两种 fixture 各一张。

### P0-3 主屏 SafeArea（适配 Top 2）

- **核心规则（Flutter SafeArea 正确套法）**：`Scaffold(appBar: AppBar())` 时，**顶部 inset 由 AppBar 自动接管**，`body` 内**不应再套 `SafeArea(top: true)`**，否则 AppBar 已让一次 + SafeArea 再让一次 → **顶部 double inset**（内容被额外下压）。正确结构是：

  ```
  Screen
   └── Scaffold
        ├── AppBar          ← 自动处理顶部（状态栏/刘海）inset
        └── Body
             └── SafeArea(bottom: true)   ← 仅在底部 home indicator / 手势条需要内缩处包
  ```

  **不是所有页面统一套 `SafeArea`**：只有"无 AppBar 的自绘顶栏页"才需 `SafeArea(top: false)`（见 P0-4 的 `home_screen`）；"有 AppBar 的页"顶部交给 AppBar，body 只按需 `SafeArea(bottom: true)`。

- **问题**：编辑器/文件管理器主屏已用 `Scaffold(appBar: …)`，顶部 inset 已被 AppBar 接管；但未对**底部** home indicator / 手势条做内缩，且存在误加顶部 SafeArea 的风险。
- **位置**（均 `Scaffold(appBar: …)`，顶部由 AppBar 接管）：
  - `lib/presentation/editor/editor_shell.dart:172-181`（`appBar: _focusMode`，底部状态栏/工具栏需 `SafeArea(bottom: true)`）；
  - `lib/presentation/screens/file_manager_screen.dart:25-27`（`appBar: AppBar(`，列表底部需 `SafeArea(bottom: true)`）；
  - `lib/presentation/screens/editor_screen.dart:352-353`（`appBar: _buildAppBar(mode)`，legacy 屏，底部同）。
- **改法**：
  1. 三处 `body` 顶层**移除任何 `SafeArea(top: true)`**（若现状无则保持无）；底部锚定区（状态栏/工具栏/列表末项）包 `SafeArea(bottom: true)`。
  2. 自查：用 `grep -rn "SafeArea(top" lib/presentation/screens lib/presentation/editor` 确认无"Scaffold→SafeArea→AppBar"反模式（有则改 `top: false` 或移到 body 内）。
- **验证**：模拟器/真机刘海屏（如 Android 16 真机）截图比对——顶部 AppBar 紧贴状态栏、无多余留白；底部内容不被 home indicator 遮挡。本机无 golden 改动（SafeArea 不影响 800×1200 基线中部）。

### P0-4 不抄设计稿设备装饰 — 只保留系统状态栏（设计还原铁律 #1）

> **问题定性（用户反馈 2026-07-30 11:09）**：这是**设计问题，不是技术问题**。设计稿 `formulafix-redesign.design/pages/home-v3.html:233-257` 在首页顶部画了一条 `<!-- Status bar -->` 装饰条（`h-12`=48px，含 `9:41` + Signal/Wi-Fi/Battery 三组 SVG）——这是**设计工具的展示占位**，真机上由操作系统提供，**APP 还原时不应抄上**。当前观感"双状态栏" = ① 系统真状态栏（9:41）② `home_screen.dart:31` `SafeArea(top:true)` 为这条占位预留的顶部留白，在视觉上对应设计稿状态栏位置，像"APP 也画了一个"。**正确结果：只留系统状态栏，APP 不复制设备装饰。**

- **根因诊断**（grep 确认 `lib/` 全源码**无** `9:41`/电池/信号/`StatusBar`（系统）字样 → APP 并没有真正画状态栏组件）：
  1. `lib/presentation/screens/home_screen.dart:29-31`：`Scaffold(body: SafeArea(child: ...))` — `SafeArea(top:true)` 让出顶部系统状态栏高度（iOS ~44-47pt），让下方内容（Header / 文档列表）从状态栏底开始。这段留白在视觉上对应设计稿 `home-v3.html:233-257` 的状态栏装饰条位置 → 用户感知为"APP 抄了设计稿状态栏"。
  2. 设计稿的 `<!-- Status bar -->` 条本身**不是功能 UI**，是设备装饰占位；真机上它由系统绘制且无法（也不应）被 APP 隐藏 → 还原时正确的处理是**不为它预留/复制任何空间**，内容直接顶到屏幕最顶，系统状态栏透明叠加在内容背景色（纸色 #FAFAF7）上。
  3. `lib/main.dart:33-53` 与 `lib/presentation/theme/app_theme.dart` 的 `AppBarTheme` 均未注入 `systemOverlayStyle` → 系统状态栏图标亮度走系统默认（iOS 浅色=黑字）；暗色/护眼主题下黑字状态栏图标在深色背景看不清（**这是附带问题，非"双状态栏"根因**，见下方"推荐增强"）。

- **改法（主线：删抄设备装饰）**：
  1. **`home_screen.dart:31`**：`SafeArea(top: true, ...)` → **`SafeArea(top: false, bottom: true)`**。顶部不再为"设计稿状态栏占位"预留空间，Header（`_Header`）直接顶到屏幕最顶；系统状态栏透明叠加在纸色背景上，视觉上"仅一个系统状态栏"。`bottom: true` 保留（首页无底部 Tab，仍须让出 home indicator/底部手势条）。
  2. **设计还原守门（防回归）**：在 `docs/UI_STATUS.md` §6 标注铁律；可选补静态守门断言 `lib/presentation/screens/**` 的 `SafeArea` 不得为"状态栏装饰"预留额外 `Container/SizedBox` 高度（即不要有人日后为"还原设计稿状态栏"而加 48px 占位条）。

- **推荐增强（让系统状态栏在暗色下可见，非本项必需）**：
  - 新建 `lib/presentation/theme/app_overlay_style.dart`，基于 `ThemeMode`+`brightness` 计算 `SystemUiOverlayStyle`（light → 图标 `Brightness.dark`；dark/sepia → 图标 `Brightness.light`）。
  - `lib/main.dart:38 builder` 包 `AnnotatedRegion<SystemUiOverlayStyle>(value: overlayStyleFor(ref.watch(themeModeProvider), brightness), child: ...)`；`app_theme.dart` 三套 `AppBarTheme` 设 `systemOverlayStyle`。
  - 这只是"让系统状态栏图标适配主题"，**不画状态栏、不复制设备装饰**，与用户诉求不冲突，反而让"只留系统状态栏"在暗色下更协调。可并入本 PR 或单独 PR。

- **验证**：
  1. iOS/Android 模拟器 + 真机截图：顶部**只有一个**系统状态栏，Header 紧贴其下（无"双状态栏"观感）；内容顶到最顶。
  2. 对照 `home-v3.html:233-257`：确认未复制 `9:41`/Signal/Battery 装饰条（grep `lib/` 无上述字样）。
  3. （若做推荐增强）三主题切换时系统状态栏图标亮度翻转，暗色下可见。
  4. 更新 `test/golden/home_screen_light_test.dart`（P0-2 新建）基线（`tool/wsl_golden.sh --update`），因 Header 顶到最顶。
  5. 不破坏 P0-3（SafeArea 仍作用于底部 home indicator）。

- **注意**：
  - iOS 状态栏无法（也不应）隐藏 — 用户明确"只保留手机的就行"，故**不要**用 `SystemUiMode.immersive` 去藏状态栏；正确做法是 `SafeArea(top:false)` 让内容贴顶 + 系统状态栏透明叠加。
  - iOS 模拟器"9:41"是系统标准占位时间，无需处理"为什么显示 9:41"；重点是无"双状态栏"观感。
  - 编辑器 `editor_shell.dart` 顶部栏 (`editor_app_bar.dart`) 是**功能 UI**（非设备装饰），正常实现；其上的系统状态栏由系统提供，二者不冲突（顶栏经 `systemOverlayStyle` 让系统状态栏图标适配主题即可）。

- **优先级理由**：用户定性"设计问题、不该抄设计稿、只留系统状态栏" → 还原铁律级事项，且与 P0-3（底部 SafeArea 内缩）职责分离，单独立项 P0-4。

---

## 2. P1 — 系统化落地

### P1-1 响应式断点体系（适配 Top 3/5）

- **问题**：无 `LayoutBuilder`/`OrientationBuilder`/`kIsWeb`/断点常量；侧栏 240 / 对话框 480 固定宽，375 屏溢出。
- **位置**：`lib/presentation/panels/side_panel_host.dart:49`（`width:240`）；`lib/presentation/widgets/formula_insert_dialog.dart:82`（`width:480`）；`editor_shell.dart:203-216` 文件树 `SizedBox(width:260)`。
- **改法**：
  1. 新增断点常量 `kTabletBreakpoint = 1024`（`app_constants.dart` 或独立 `layout_constants.dart`）。
  2. 侧栏/文件树：`LayoutBuilder` 或 `MediaQuery.size.width` 判断，窄屏退化为 `Drawer`/覆盖层（不挤占编辑区）。
  3. 对话框：`width: min(480, MediaQuery.size.width * 0.9)`。
  4. （可选）`OrientationBuilder` 处理 Landscape（当前无横屏布局）。
- **验证**：新增 375×812 / 834×1112 golden 变体；真机窄屏截图。

### P1-2 spacing / radius 命名令牌集中化（还原度 Top 5）

> **状态（2026-07-31）**：令牌命名集中化已提交 **PR #116（像素中性，待合并）**——`AppSpacing` 新增 `readerHorizontal/cardGap/sectionGap/fabBottomOffset/topBarHeight/bottomSheetMaxHeightFactor/inputRadius` 命名令牌，`app_theme.dart` 输入框圆角改走 `AppSpacing.inputRadius(8)`。
> **延后（改像素，需 WSL 补 golden 另开 PR）**：卡片/底部 sheet 消费 `radius.lg(16)`/`radius.xl(24)`（当前仍用 `cardRadius=12`）。

- **问题**：spacing 6 项无名令牌；`radius.lg=16/xl=24` 从未使用。
- **位置**：`design-system/tokens.json:130-142`（`readerHorizontal28`/`cardGap12`/`sectionGap24`/`fabBottomOffset88`/`topBarHeight48`/`bottomSheetMaxHeight88vh`）；`app_theme.dart:61` 输入框用 `8` 非令牌；`AppSpacing.cardRadius=12` 非令牌值。
- **改法**：
  1. `AppSpacing`/`EditorTokens` 补上述缺项（`topBarHeight` 用 `kToolbarHeight` 或显式 48 并注明）。
  2. `app_theme.dart` 输入框圆角改 `radius.sm`(6) 或新增 `radius.input`(8) 入令牌。
  3. 卡片/底部 sheet 消费 `radius.lg`(16)/`radius.xl`(24)。
- **验证**：无功能回归；相关 golden 若因圆角变化需 `--update`。

### P1-3 字号令牌补全与冲突收敛（还原度 Top 6）

> **状态（2026-07-31）**：字号令牌补全已提交 **PR #116（像素中性，待合并）**——`AppTypography` 新增 `caption=10`/`tabLabel=11`/`formulaDisplay=19`/`formulaDisplayReader=21`，`formula()` 硬编码 19→`formulaDisplay`，`home_tab_bar.dart` 硬编码 11→`AppTypography.tabLabel`。
> **延后（改像素，需 WSL 补 golden 另开 PR）**：段落字号 `AppSpacing.body=16` 与 `EditorTokens.paragraphFontSize=15` 收敛为单一来源（当前 golden 以 15 为准）。

- **问题**：`caption=10`/`formulaDisplayReader=21` 无令牌；`tabLabel` 硬编码；`AppSpacing.body=16` 与 `EditorTokens.paragraphFontSize=15` 同段落冲突。
- **位置**：`app_typography.dart`（最小 11、公式固定 19）；`home_tab_bar.dart:115` 硬编码 tabLabel；`app_constants.dart:59`(`AppSpacing.body=16`) vs `editor_tokens.dart:203`(`paragraphFontSize=15`)。
- **改法**：
  1. `AppTypography` 补 `caption=10`、`formulaDisplayReader=21`。
  2. `home_tab_bar.dart:115` 改走 `EditorTokens`/`AppSpacing` 令牌。
  3. **收敛为单一来源**：以 `tokens.json editorBody=15` 为准，统一段落字号（建议 `AppSpacing.body` 改 15 或文档明确 renderer 用 `EditorTokens.paragraphFontSize` 为准，删除另一处）。
- **验证**：段落渲染 golden 比对（paragraph_light/dark 已存在）；无字号跳变。

### P1-4 Golden 矩阵扩充（适配 Top 1，最高 ROI）— 带规模控制

- **问题**：全部 golden 固定 `800×1200` + `textScaleFactor=1.0`，无法拦截窄屏溢出/系统缩放破版。
- **位置**：`test/golden/golden_helpers.dart:51`（`Size(800,1200)`）、`:46`（`textScaleFactorTestValue=1.0`）。
- **改法**：
  1. `pumpGoldenApp` 支持 `size` / `textScaleFactor` 参数（默认保持 800×1200/1.0 向后兼容）。
  2. **矩阵策略（不做全组合爆炸）** — 按"页面重要性"分层，明确覆盖集而非穷举：

     | 层级 | 页面 / 组件 | 主题 | 尺寸 | 数量估算 |
     |---|---|---|---|---|
     | 核心页 | `home_screen` | light / dark / sepia | 375 / 800 / 834 | 3×3 = 9 |
     | 核心页 | `editor_shell`（含工具栏/状态栏） | light / dark | 800 / 834 | 2×2 = 4 |
     | 核心页 | `file_manager_screen` | light / dark | 800 / 834 | 2×2 = 4 |
     | 普通组件 | `formula_block` / `paragraph` / `heading` / `code_block` / `inline_math` / `markdown_toolbar` | light / dark | 800（固定） | 6×2 = 12 |
     | 缩放项 | `home_screen` + `editor_shell` | light | 800 @ textScale 1.3 | 2 |

     合计 ≈ **31 张**（在现有 10 张基础上净增 ≈21 张），**远小于** 3 主题×3 尺寸×textScale×页面 的 50~100 张全组合。原则：
     - **首页三主题全覆盖**（sepia 必测，用户明确护眼模式是重点）；
     - **编辑器/文件管理只测 light/dark**（sepia 复用主题切换逻辑，不必每屏重复）；
     - **普通组件只测 light/dark，固定 800**（组件无响应式断点差异，不摊尺寸成本）；
     - **textScale 只加在 2 个核心页**（防止系统字体放大破版，不必每个组件都测）；
     - 平板尺寸（834）只在核心页出现，组件层不测。
  3. 对 `home_screen`/`editor_shell`/`file_manager` 落上述矩阵；**恢复** `test/golden/file_manager_test.dart:81-83` 被注释禁用的 `matchesGoldenFile`（先确保 png 与当前 UI 一致）。
- **验证**：CI 跑新矩阵全绿；新增 png 走 `tool/wsl_golden.sh --update` 重基线（WSL 与 CI 同环境）。

---

## 3. P2 — 组件规格 + 清理 + 语义化

### P2-1 缺失组件 Widget（还原度 Top 3）

> **状态（2026-08-01）**：已实现 `GhostButton`/`AppToggle`/`SearchPill`/`AppFab` 四个令牌化组件（`lib/presentation/widgets/buttons.dart`）+ 单测（`test/widgets/buttons_test.dart`），全部接 `EditorTokens`/`ThemeData.colorScheme`，无硬编码颜色字面量。接线（首页 `_RoundButton`→`GhostButton`、搜索栏接 `SearchPill`、FAB 放置）会改像素、需 WSL 重新生成 golden 基线，属延后项 **PR-Fb**。

- **问题**：`toggle`/`searchPill`/`ghost`/`fab` 0 实现；全仓无 `FloatingActionButton`；首页 `_RoundButton` 为 ad-hoc（size 40≠36）。
- **位置**：`tokens.json:164-178`（button.ghost/fab）、`:196-217`（searchPill/toggle）；`home_screen.dart:184`（`_RoundButton`）。
- **改法**：
  1. 实现 `AppToggle`/`SearchPill`/`GhostButton`/`AppFab`，全部接 `EditorTokens`/`AppColors`/`AppSpacing` 令牌。
  2. 首页 `_RoundButton` 收敛为 `GhostButton`（size 36 对齐令牌）。
  3. 若首页/编辑器需要主操作，补 `FloatingActionButton`（接 `button.fab` 规格）。
- **验证**：新组件单测 + golden；无令牌泄漏。

### P2-2 清理侧栏占位死代码（还原度 Top 4）

> **状态（2026-08-01）**：已删除 `side_panel_host.dart` 占位文件，并移除 `workspace.dart` 中 `if (SidePanelHost.shouldShow(context))` 死分支（`[SidePanelHost.shouldShow]` 恒 false，移除不改变渲染，像素中性）。真实侧栏由 `editor_shell` 的 `FileTreePanel`/`TocPanel` 承载。

- **问题**：`side_panel_host.dart` `shouldShow` 恒 false，真实侧栏已在 `editor_shell` 另实现（`FileTreePanel`/`TocPanel`），原 host 未清理且无入口发现性。
- **位置**：`lib/presentation/panels/side_panel_host.dart:38-42`。
- **改法**：删除该占位文件（确认无引用），或显式 `@deprecated` 标注并指向 `editor_shell` 的真实侧栏实现。
- **验证**：`flutter analyze` 无未使用导入/死代码告警。

### P2-3 颜色语义化 — 移出本轮（→ 见 P3）

> **改判（用户反馈 7/30）**：40+ 处 `Colors.xxx` 属**技术债**，但**不应与本轮 UI 修复绑定**。一次性替换会触发大量 golden 像素变化、diff 巨大、review 困难，且与 P0/P1 的"视觉正确性/回归守护"目标无直接关系。→ **拆为独立的 P3 长期治理（见 §3.5）**，本轮只做最小必要项。

- **本轮即时项（仅限影响主题的地方）**：
  - 范围收窄到 `Colors.black` / `Colors.white` 中**直接写死、会破坏暗色/护眼主题切换**的少数点（如硬编码白底黑字容器、未走 `EditorTokens.surface` 的区域）。
  - 位置：散落 `preview_content`、`markdown_input_field`、`list_renderer`、`paragraph_renderer`、`task_list_item_renderer`、`export_menu` 等中"白底/黑字"硬编码处。
  - 改法：仅这些点改走 `EditorTokens.surface` / `EditorTokens.onSurface`（其余 `Colors.grey/blue/red/green` 等留待 P3）。
  - 验证：只关注主题切换截图，不要求全量 golden 重基线。

---

### 3.5 P3 — 颜色语义化长期治理（独立于 UI 修复，长期技术债）

- **性质**：长期治理项，**不计入本轮 UI 修复 PR**，单独排期，避免 golden 大面积变化拖累 review。
- **范围**：全仓 `Colors.grey/black/white/blue/red/green` 等语义色泄漏（40+ 处），逐文件迁移到 `EditorTokens` / `AppColors` / `AppSpacing` 令牌。
- **建议执行方式**：
  - 按文件小批量 PR（每次 1~2 个文件），单 PR 配对应 golden `--update`，控制 diff 体积。
  - 每 PR 走 pre-push 守门（analyze 0 fatal + test 全绿）。
  - 静态守门（参考 TC-ARCH-MODEL-4 风格）：断言 `lib/presentation/{screens,widgets,blocks,panels}` 禁 `Colors.grey/black/white` 直写（仅允许 `EditorTokens` 等令牌），随迁移逐步收紧。
- **完成标准**：`flutter analyze` 无 `Colors.` 直写告警 + 守门全绿 → 关闭。
- **关联**：与 §6 DoD"无新增裸颜色"呼应——P3 是存量治理，DoD 是增量守门。

---

## 4. 验证与守门总则

- 每个代码修复 PR 走既定 **pre-push 守门**（`.githooks/pre-push` → preflight：`flutter analyze` 0 fatal + 全量 `flutter test`）。
- 视觉类（P0-1/P0-2/P1-1/P1-4）改动后，在 WSL（`flutter_app/tool/wsl_golden.sh --update`）重基线，确保 CI Golden job 一致。
- 真机/模拟器截图验证：刘海屏 SafeArea（P0-3）、暗色阴影（P0-1）、窄屏响应式（P1-1）——本机 Android 16 真机（`adb-63cfc8cf-KZ0SQM`）或模拟器。
- 文档类（`UI_STATUS.md` + 本文件）独立于代码 PR，用户审核后一并提交。

## 5. 风险与注意

1. **暗色阴影改动（P0-1）** 会影响所有暗色 golden → 必须同步 `--update` 暗色基线，否则 CI Golden 红。
2. **响应式改动（P1-1）** 需确保不破坏现有 800×1200 布局（默认尺寸下行为不变）。
3. **字号收敛（P1-3）** 段落字号 16→15 会改变段落 golden 像素 → 同步更新 `paragraph_*` 基线。
4. **P3 颜色语义化**（已移出本轮）单独排期，逐文件小 PR + 对应 golden `--update`，控制单 PR diff；不混入 P0/P1 修复 PR，避免 golden 大面积变化拖累 review。

---

## 6. Definition of Done（UI 修复完成定义）

> 防止"无限优化"：满足以下全部条件，本轮 UI 修复（P0 + P1 + P2 + P0-4 设计铁律）才算**完成**，未满足项单独排期（如 P3）。

| # | 完成标准 | 验证方式 |
|---|---|---|
| 1 | `tokens.json` **核心 token 落地率 > 90%**（color/radius/shadow/typography.scale/spacing 主项均有对应 Dart 令牌消费） | 逐项核对 `app_constants.dart` / `app_theme.dart` / `editor_tokens.dart` 落地率（见 `UI_STATUS.md` §1 评分表） |
| 2 | 所有 **P0 Golden 通过**（含 P0-2 首页整页 golden、P0-1 暗色阴影 golden） | CI Golden job 全绿 |
| 3 | **Home / FileManager / Editor 三主屏 golden 覆盖**（light/dark，Home 另含 sepia） | `test/golden/` 三屏均有 golden 且 CI 绿 |
| 4 | **light / dark / sepia 三主题均可切换**且无破版 | `themeModeProvider` 三态切换 + 三主题 golden 比对 |
| 5 | `flutter analyze` **0 fatal**（无 error / 无新增 warning 守门） | pre-push 守门 `preflight.sh` |
| 6 | `flutter test` **全绿**（全量，含 golden 矩阵） | pre-push 守门 `preflight.sh` |
| 7 | **无新增裸颜色**（`Color(0x…)` 与 `Colors.grey/black/white` 直写不增；影响主题处已走令牌） | 静态守门（参考 TC-ARCH-MODEL-4 风格）+ review |
| 8 | **无死代码入口**（`side_panel_host` 占位已清理/标注，无不可达分支） | `flutter analyze` 无 unused + 人工确认 |
| 9 | **真机验证通过**：① 刘海屏 SafeArea（顶部无 double-inset、底部不被 home indicator 遮挡）② 深色模式（阴影可见、状态栏图标可读）③ 横屏（响应式/双栏退化合理） | Android 16 真机（`adb-63cfc8cf-KZ0SQM`）或模拟器截图比对 |

**边界说明**：
- P3（颜色语义化 40+ 处）**不计入**本轮 DoD（长期治理，独立排期）—— DoD #7 仅约束"无新增"，不要求存量清零。
- Golden 矩阵规模按 §1 P1-4 的"规模控制策略"执行（≈31 张，非全组合爆炸）—— DoD #3 指"三主屏覆盖"，不要求每个组件每尺寸每主题。

---

*本修复计划基于 `origin/main` = `5a481fc`（v1.0）的两轮只读审计，配套 `docs/UI_STATUS.md`。v1.1（2026-07-31）同步进度：`#111`(PR-C)、`#112`(PR-D) 已合并，新增基础设施 PR `#113`（Repository Safety Layer，独立排期）。实施前请逐 PR 评审，避免单巨 PR。*
