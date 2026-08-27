# 测试补齐方案（E2E + UI 回归）

> 基于 2026-07-28 测试资产审计（125 个测试文件：100 `test/` + 25 `integration_test/`）。
> 基线：PR #89（`feat/block-interaction`，commit `4589bd7`）CI 全绿后的 main。
> **排序原则**：按自动化落地容易度从高到低排列——Tier 1/2 AI 可直接写完并由 CI 验证；
> Tier 3 需本地 Android 模拟器（AI 可跑但慢/易抖）；Tier 4 必须 Human Owner 真机人工验证，放最后。

> **状态更新（2026-08-06，基于代码实况核实）**
>
> | 项 | 状态 | 证据 |
> |----|------|------|
> | T1-1 触屏 tap 显示 BlockToolbar | ✅ 已修复 + 测试覆盖 | `block_selection.dart:50` `showChrome = _hovering || selected`；`block_interaction_test.dart:250/265` 触屏路径断言 |
> | T1-2 拖拽手势 widget 测试 | ✅ 已完成 | `test/presentation/blocks/shared/block_drag_gesture_test.dart` |
> | T1-3 FormulaRenderer 降级测试 | ✅ 已完成 | `test/presentation/widgets/formula_renderer_fallback_test.dart` |
> | T1-4 `applyBlockPrefix` 纯函数单测 | ✅ 已修复 | `block_convert.dart` 已抽顶层函数；`block_convert_test.dart` 单测存在 |

---

## 总览

| Tier | 性质 | 执行者 | 验证途径 | 项数 |
|------|------|--------|----------|------|
| 1 | Widget/单元测试 + 1 个产品缺陷修复 | AI | CI（`flutter test`） | 4 ✅ 全部完成 |
| 2 | Golden UI 回归基线（**环境三固定前置 + 分批**，首批 ≤ 12 张） | AI | CI Golden job（需恢复） | T2-0 前置 + 首批 10 张 |
| 3 | integration_test E2E | AI（本地模拟器） | 手动门禁 + verification report | 4 |
| 4 | 真机人工验收 | **Human Owner** | 人工检查清单 | 4 |

**建议节奏**：每个 Tier 一个分支一个 PR，做完 Tier 1 即可显著降险；Tier 3/4 可与后续 Phase 并行。
**验收对象**：见文末「Release Gate — Phase 3.5 测试退出标准」——收口以 Gate 清单为准，**不以新增测试数量为指标**。

---

## Tier 1 — Widget/单元层（CI 可全自动验证，最先做）

### T1-1 触屏 tap 显示 BlockToolbar（产品缺陷修复 + 测试）⚠️ 唯一含生产代码改动 ✅ 已修复

**状态**：✅ 已修复（2026-08-06 核实）。`block_selection.dart:50` 已改为 `showChrome = _hovering || selected`，触屏 tap 选中（`focusedId == blockId`）即显示工具栏。`block_interaction_test.dart:250/265` 两条触屏路径测试断言覆盖完整。

**原问题**：`BlockSelectionChrome` 依赖 `MouseRegion` hover 显示工具栏/拖拽手柄。**手机没有 hover**，触屏用户永远看不到 BlockToolbar —— 这是产品级缺陷，不只是测试缺口。

- 改动：`block_selection.dart` —— chrome 显示条件从 `hover` 扩展为 `hover || coordinator.focusedId == blockId`（tap 选中即显示）。
- 测试（`block_interaction_test.dart` 追加 2 个）：
  1. tap 块 → focusedId 命中 → BlockToolbar/DragHandle 可见（不依赖 MouseRegion）；
  2. tap 另一块 → 原块 chrome 消失。
- 守门：不新增依赖方向违规（TC-ARCH-UI-5）；`flutter analyze --fatal-warnings` 零告警。

### T1-2 拖拽手势 widget 测试（真手势，非直接构造 Command）✅ 已完成

**状态**：✅ 已完成（2026-08-06 核实）。测试文件 `test/presentation/blocks/shared/block_drag_gesture_test.dart` 已存在。

**原现状**：`block_interaction_test.dart` 的重排测试全部是 `coordinator.handle(MoveBlockCommand(...))` 直接派发，没有验证 `ReorderableDragStartListener → onReorderItem → blockReorderArgs → MoveBlockCommand` 这条 UI 链路。

- 新文件：`test/presentation/blocks/shared/block_drag_gesture_test.dart`
- 用 `tester.startGesture` 在 `BlockDragHandle` 上长按 + `moveBy` 越过下一块高度 + `up`，断言 `coordinator.allIds` 顺序变化。
- 至少 3 个：下拖一格、上拖一格、拖动后取消（回到原位不派发命令）。
- 注意：`ReorderableListView` 拖拽在 widget 测试中需要 `tester.pump(kLongPressTimeout)` 触发 delayed drag（`ReorderableDelayedDragStartListener` 语义）；若 `ReorderableDragStartListener` 是立即拖拽则不需要长按等待——以实际组件为准。

### T1-3 FormulaRenderer 降级路径 widget 测试 ✅ 已完成

**状态**：✅ 已完成（2026-08-06 核实）。测试文件 `test/presentation/widgets/formula_renderer_fallback_test.dart` 已存在。

**原现状**：Phase 3.5 公式渲染只有渲染成功路径的间接覆盖，降级链（SVG 未就绪 → flutter_math_fork → serif italic 源码）无显式断言。

- 新文件：`test/presentation/widgets/formula_renderer_fallback_test.dart`
- 覆盖：① 块级 SVG 服务未就绪时降级 serif italic 且样式来自 `AppTypography.formula`；② 行内非法 LaTeX 时 flutter_math_fork 失败 → 源码兜底；③ 三主题（light/dark/sepia）下降级文本颜色 = `EditorTokens.textPrimary`。
- 前置：`MaterialApp(theme: AppTheme.xxxTheme)` 注入 EditorTokens（MEMORY §3 规则）。

### T1-4 `_applyBlockPrefix` 纯函数单测补全 ✅ 已修复

**状态**：✅ 已修复（2026-08-06 核实）。函数已抽到 `lib/presentation/blocks/shared/block_convert.dart` 顶层 `applyBlockPrefix(String source, BlockType target)`（与 `editor/block_reorder.dart` 同模式）。测试文件 `test/presentation/blocks/shared/block_convert_test.dart` 已存在。

**原现状**：多行清理修复（`4589bd7`）后仅有 widget 层间接覆盖，无直接单测（函数目前是私有，需提取为可测顶层函数或 `@visibleForTesting`）。

- 改动：`block_toolbar.dart` 将 `_applyBlockPrefix` 提为 `@visibleForTesting String applyBlockPrefix(...)`（或抽到 `block_convert.dart` 纯函数文件，与 `block_reorder.dart` 同模式——**推荐后者**，守单一职责）。
- 新文件：`test/presentation/blocks/shared/block_convert_test.dart`，覆盖：多行 blockquote → paragraph（全行剥 `>`）、多行 paragraph → blockquote（全行加 `>`）、`## x` → blockquote、列表前缀剥离、空字符串。

**Tier 1 Gate**：✅ 全部满足（2026-08-06 核实）。`flutter test` 全绿 + analyze 零告警 + CI 通过 + **T1-1 触屏缺陷在 widget 层证实已修**（tap 路径可见 chrome）。四个风险点（触屏可达性 / 拖拽链路 / 公式降级 / 前缀转换）均有直接断言。

---

## Tier 2 — Golden UI 回归基线（AI 可落地，**分批 + 硬前置**）

> 现状：`test/golden/` 仅 1 个 `file_manager_test.dart`，CI Golden job **paused**（`if: false`）。
> **历史事实**（ci.yml 注释 + TEST_SKIP_REGISTRY `GOLDEN-CI-001`）：Golden job 正是被跨平台字体渲染差异干停的——Windows 本地基线 vs Linux CI 实测 0.09% / 4007px diff，非真实回归。
> **审计事实（2026-07-28）**：CI runner = `ubuntu-latest`（浮动镜像，未固定版本）；Flutter = 3.44.6（已固定 ✅）；`pubspec.yaml` **无任何 `fonts:` 打包**——serif/mono/中文/公式字体全部依赖平台字体解析。**这是误报的直接根源，未解决前铺任何基线都是负资产。**
>
> **维护成本原则**：Golden 数量是维护负担，不是覆盖率——改一个 padding 全量基线作废。因此**分批铺、设总量预算（首批 ≤ 12 张，全期 ≤ 40 张）**，每张基线必须回答"它防的是哪类回归"。

### T2-0 环境三固定（硬前置，未完成禁止铺基线）⛔

| 项 | 现状 | 动作 |
|----|------|------|
| CI image | `ubuntu-latest`（浮动） | 固定为显式版本（如 `ubuntu-24.04`），杜绝镜像升级引发字体/渲染漂移 |
| Flutter version | `3.44.6` 已固定 ✅ | 保持；升级 Flutter 时把「重新生成基线」列入升级 checklist |
| Font package | **未打包**（平台解析）❌ | `pubspec.yaml` 打包全部视觉关键字体：serif 正文/标题、mono 代码、公式字体、中文字体；golden 测试 `setUpAll` 显式 `FontLoader.load()`，禁止依赖系统 fallback |

- 同时满足 `GOLDEN-CI-001` 解封条件：固定 locale / textScaleFactor / viewport；基线在 **Linux CI 内生成**（`--update-goldens` 产物由 CI artifact 下载后提交，不用 Windows 本机产物）。
- **验证门槛**：试点 1 张（paragraph light）先行，连续 10 次 CI 运行 0 随机 diff，才允许铺第一批。

### T2-1 第一批：核心视觉资产（≤ 12 张，覆盖 ~80% 视觉风险）

只铺回归风险最高、且 3.4.5/3.5 刚动过的资产：

| 资产 | 张数 | 防什么 |
|------|------|--------|
| formula（块级降级态 + 行内） | 2 | Phase 3.5 刚重写的渲染内核，token/字体一动就崩 |
| code block | 1 | mono 字体 + chip 圆角 token |
| heading（h1/h2 同图） | 1 | headingFontSizes 单一真相源刚重构 |
| paragraph | 1 | 基准排版（serif 15px / blockSpacing 20） |
| MarkdownToolbar | 1 | chrome sans 字体 + 图标布局 |
| EditorShell 整页（含状态栏 32px） | 1 | 布局骨架 + viewportPadding 24 |
| 以上关键 3 项（formula / paragraph / shell）× dark 主题 | 3 | 主题色 token 回归 |

合计 **10 张**。sepia 主题、其余块类型（table/list/mermaid/blockquote）、BlockSelectionChrome 三态**全部推迟到第二批**。

### T2-2 第二批（默认不做，触发式扩展）

触发条件（满足其一才扩展）：① 第一批稳定运行 ≥ 2 周 / 20 次 CI 无误报；② 某未覆盖资产真实发生视觉回归（用事故证明价值）。扩展时仍受全期 ≤ 40 张预算约束，超预算须先删低价值基线。

**Tier 2 Gate**：T2-0 三固定完成 + 试点 10 连绿 → 第一批 10 张入库 → Golden job 从 `if: false` 恢复为 required + `TEST_SKIP_REGISTRY.md GOLDEN-CI-001` 销案 + 基线更新 SOP 文档化（谁改 token 谁更新基线，PR 必须附 golden diff 截图）。

---

## Tier 3 — integration_test E2E（AI 可执行，Android 模拟器，慢/易抖）

> 前置：合并 PR #89；旧 `test/phase34-e2e-p0` 分支已落后 main（无 formula_renderer.dart），**放弃 rebase，从新 main 重拉分支**。
> 环境坑（MEMORY §7）：flutter lockfile 真路径、taskkill 双斜杠、横屏用 `adb shell wm size`、proxy 断连重试。
> CI 不跑 integration_test —— 每次运行结果须写入 verification report 作为手动门禁记录。

### T3-1 `integration_test/phase35_block_interaction_test.dart`

真实设备拖拽链路：长按手柄拖动重排 → 顺序断言；tap 选中 → 工具栏出现（依赖 T1-1 修复）→ 点删除/转换 → 文档变化；验证触屏（无 hover）路径在真机成立。

### T3-2 `integration_test/phase35_formula_test.dart`

块级 `$$` 真实 MathJax SVG 渲染（WebView 只有真机/模拟器可验）；行内公式 WYSIWYG；SVG 未就绪窗口期降级再升级；三主题下公式颜色。

### T3-3 `integration_test/phase35_persistence_roundtrip_test.dart`

编辑含 `$$` 公式 + 表格 + 代码块的文档 → autosave → 重启 app → 重新打开 → AST 与渲染一致（现有 `phase34_persistence_test` 只测纯文本）。

### T3-4 导出全链路 E2E（`phase35_export_e2e_test.dart`）

设备上 md → PDF/Word 真实产出文件，校验文件存在 + 字节头（`%PDF` / `PK`）+ 非零尺寸（现有覆盖只到进度 UI 和 unit 层）。

**Tier 3 Gate**：4 个 E2E 在 Android 模拟器全绿 + **Formula compatibility matrix**（行内/块级 × 合法/非法 LaTeX × SVG 就绪/未就绪 × 3 主题）填满无空格，运行记录写入 `docs/releases/phase3.5-verification-report.md`（对应 Release Gate G1/G3/G6）。

---

## Tier 4 — 真机人工验收（Human Owner 执行，放最后）

> 这些无法可靠自动化，AI 提供检查清单，由你在真机上过一遍并在 verification report 勾选。

### T4-1 IME 中文输入真机验收

- 系统输入法（搜狗/微信键盘）中文 composing：拼音候选中不落盘、上屏后正确插入；
- 在公式 `$...$` 边界处输入中文不破坏公式；
- 长文档快速输入无丢字（IME 事务完整性只在真输入法下可信）。

### T4-2 横竖屏旋转状态保持

- 编辑中途旋转：光标位置、未保存内容、滚动位置、选中块保持；
- 拖拽进行中旋转不崩溃。

### T4-3 导出文件真实打开验证

- 导出 PDF 在手机 WPS/系统阅读器打开：公式/表格/中文字体不缺字、不乱码；
- 导出 Word 在 WPS 打开可编辑；
- 含 GBK 来源的 .md 导入 → 导出 round-trip 无乱码。

### T4-4 触屏交互手感验收（主观项）

- 拖拽手柄大小/命中区在手指下是否好按（当前 24px 宽，Material 推荐 ≥48px 命中区——可能需要 T1-1 之后追加 padding 调整）；
- 工具栏悬浮位置是否遮挡内容；
- 单手操作长文档重排的流畅度。

**Tier 4 退出条件**：检查清单全部勾选或缺陷立项，记入 verification report。

---

## Release Gate — Phase 3.5 测试退出标准（验收以此为准，不以测试数量）

> 原则：**测试数量不是质量指标**。本方案的验收对象是下面的 Gate 清单——全部满足即 Phase 3.5 测试收口，与新增了多少个测试无关；任何一条不满足，加再多测试也不算完成。

### Phase 3.5 Exit Criteria

| # | 条件 | 判定方式 | 当前状态 |
|---|------|----------|----------|
| G1 | **P0 E2E 全绿**：拖拽重排（T3-1）+ 公式真实渲染（T3-2）在 Android 模拟器通过 | 运行记录写入 verification report（CI 不跑 integration_test，手动门禁） | ❌ 未建 |
| G2 | **触屏可达性缺陷关闭**：无 hover 设备可通过 tap 使用 BlockToolbar/DragHandle | T1-1 widget 断言 + T4-4 真机勾选 | ✅ widget 层已修（T4-4 真机勾选待 Human Owner） |
| G3 | **Formula compatibility matrix 完成**：行内/块级 × 合法/非法 LaTeX × SVG 就绪/未就绪 × 3 主题，每格有测试或显式记录"不支持" | matrix 表格入 verification report，空格清零 | ❌ 未建 |
| G4 | **Golden baseline 建立**：T2-0 三固定 + 第一批 10 张入库 + Golden job 恢复 required | CI Golden job 绿 + GOLDEN-CI-001 销案 | ❌ paused |
| G5 | **无未关闭的 P0/P1 缺陷**：G1-G4 执行中发现的缺陷要么修复、要么降级立项并由 Human Owner 签字 | issue 清单 + report 签字 | —（随执行更新） |
| G6 | **持久化 round-trip 不丢内容**：含公式/表格/代码块文档 autosave → 重启 → 一致（T3-3） | E2E 通过记录 | ❌ 未建 |

- **裁剪权**：Human Owner 可显式豁免某条 Gate（写入 report 的 Waived 段 + 理由），但不允许默认跳过。
- Tier 4 人工清单（IME / 旋转 / 导出打开 / 手感）不阻塞 Phase 3.5 Exit，作为发布前独立 checklist 存在——它们属于 **Release Gate（App 发版）** 而非 **Phase Gate（阶段收口）**。

---

## 落地顺序与分支建议

| 顺序 | 分支 | 内容 | PR 门禁 |
|------|------|------|---------|
| 1 | `fix/touch-chrome-and-tests`（Tier 1） | T1-1~T1-4 | CI 全绿 + Tier 1 Gate |
| 2a | `ci/golden-env-pinning`（T2-0） | 固定 CI image + 字体打包 + 试点 1 张 10 连绿 | 试点稳定 |
| 2b | `test/golden-first-batch`（T2-1） | 首批 10 张核心资产基线 + 恢复 Golden job | Golden job 绿 + GOLDEN-CI-001 销案 |
| 3 | `test/phase35-e2e`（Tier 3） | T3-1~T3-4 + compatibility matrix | 本地模拟器全绿 + report |
| 4 | —（Tier 4） | 人工清单（发版 Gate，不阻塞 Phase Exit） | report 勾选 |

**已知风险**：
- 本会话 AI 本地 Flutter 环境异常（wrapper 进程被杀），Tier 1/2 的本地验证可能需依赖 CI 兜底或环境修复后再跑。
- Golden 已有前科（GOLDEN-CI-001：Windows/Linux 字体 diff 0.09% 停摆）——**T2-0 未完成前铺任何基线视为违规**；字体打包会增大 APK 体积，选型时评估 subset 字体。
- Golden 维护成本随张数线性上涨：全期预算 ≤ 40 张，任何人想加基线先回答"防哪类回归 + 删哪张换额度"。
- T1-1 是生产代码改动，需与 Phase 3.3 交互模型（focusedId 语义）对齐，避免与未来 selection 模型冲突。

---

*生成：2026-07-28 ｜ 修订 v2（同日）：① Tier 2 改为分批（首批 10 张 ≤ 12 张预算，全期 ≤ 40 张）+ T2-0 环境三固定硬前置（审计确认：ubuntu-latest 浮动、Flutter 3.44.6 已固定、pubspec 无字体打包）；② 新增 Release Gate 章节，验收以 G1-G6 为准而非测试数量 ｜ 基线 commit `4589bd7` ｜ 关联：docs/ROADMAP.md §3.5、docs/TEST_SKIP_REGISTRY.md GOLDEN-CI-001*
