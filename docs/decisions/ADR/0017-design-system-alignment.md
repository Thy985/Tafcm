# ADR-0017：设计系统 Token 与字体对齐（Design System Token & Typography Alignment）

> **状态**：Accepted（2026-08-30 批量追认——Design System Token 已实施：tokens.json + AppTheme 映射 + EditorTokens（Phase 3.4.5））
> **版本**：v1.0
> **起草日期**：2026-07-28
> **起草人**：AI Agent 起草，Human Owner 评审决策
> **关联文档**：
> - [Phase 3.4.5 Design System Alignment](../../ROADMAP.md)（ROADMAP §Phase 3.4.5）
> - [ADR-0015 Theme Architecture Migration](./0015-theme-architecture-migration.md)（主题机制：static const → ThemeExtension）
> - [design-system/tokens.json](../../../design-system/tokens.json)（产品 token 权威源，2026-07-18 提取自高保真稿）
> - [docs/design/ui-spec.md](../../design/ui-spec.md)（工程实现参考，待向本 ADR 对齐）

---

## 版本修订记录

- **v1.0（2026-07-28）**：初版。定义颜色单一真相源 `AppColors` + 字体系统 `AppTypography` + "Widget 禁止硬编码颜色" 守门；撤回 ADR-0015 中 "Typography Refactor = wontfix" 的立场，将字体系统提升为 Phase 3.4.5 的 P0-2 一等公民。

---

## 背景

### 当前状态

UI 还原度审计（2026-07-28）结论：

- **Engineering Foundation ~90%+**：编辑内核 / 块运行时 / 持久化 / 主题架构 / 自动保存 / 文件树 / TOC / 导出 / 图片链路均已落地。
- **Visual / Product Identity ~40%**：结构都在，但设计语言几乎没落地。

审计定位的最大根因：**Design System 未作为单一真相源接入**。具体：

1. 当前 `EditorTokens` 主色为 `0xFF165DFF`（亮 Azure），而 redesign token 主色为 `#1E3A5F`（深海军蓝）。两者传递完全不同的产品人格（SaaS 工具 vs 学术出版）。
2. `ThemeData` 未设 `fontFamily`，正文/标题/公式默认 sans（Roboto），而设计要求 serif 学术感。
3. 背景为冷灰 `#F2F3F5`，设计应为暖纸 `#FAFAF7`。
4. 颜色字面量散落在 `lib/presentation/` 多处 Widget，未全部走 `EditorTokens`。

### 触发本 ADR 的事件

Phase 3.4 Advanced Capabilities 主体已完成，进入产品化阶段。Phase 3.4.5 Design System Alignment 规划将 "Functional Editor" 变为 "FormulaFix Product Identity"，需要先把 token 与字体的**单一真相源 + 接入规则**固化，否则各 Widget 自行取色会再次导致视觉漂移。

### 现有约束

- [ADR-0015](./0015-theme-architecture-migration.md)：已定 `EditorTokens` 从 `static const` 改造为 `ThemeExtension<EditorTokens>`，由 `ThemeData.extensions` 注入（机制层）。但 ADR-0015 将 "inline 颜色 / TextSpan 一致性 / Typography Refactor" 标为 `wontfix` + `phase-3.4-typography` 延期——**本 ADR 撤回该立场**（见 §与 ADR-0015 关系）。
- 设计 token 已由 `design-system/tokens.json`（2026-07-18）从 `formulafix-redesign.design/` 高保真稿提取，值为产品权威源。

---

## 决策

建立两条单一真相源，并通过 `EditorTokens`（已为 `ThemeExtension`，ADR-0015）接入生产 UI：

### 1. 颜色单一真相源 `AppColors`

新建纯数据层 `AppColors`，集中存放 redesign token 的精确值（light / dark 两套）。`EditorTokens`（ThemeExtension 实例）**消费** `AppColors` 构建，Widget 只经 `EditorTokens.of(context)` 取色。

> 不把颜色直接写进 `EditorTokens` 的理由：`AppColors` 作为无 context 依赖的纯常量层，便于单测、便于三主题共享同一组语义命名（primary / accent / paper），避免 `EditorTokens` 实例字段重复罗列数值。

### 2. 字体系统 `AppTypography`

新建 `AppTypography`，按用途拆分文本样式（display / h1 / h2 / body / caption / formula / code）。

- **serif（文档 / 标题 / 公式）**：`Iowan Old Style, Palatino Linotype, Source Han Serif SC, Songti SC, Georgia, serif`
- **mono（代码）**：`SF Mono, JetBrains Mono, Fira Code, Consolas, monospace`
- **sans（chrome / 标签 / 按钮 / 导航）**：系统无衬线栈（含 `PingFang SC` / `Microsoft YaHei` 中文回退）

`ThemeData.fontFamily` 设为 serif 默认（文档正文场景为主），chrome / 标签等 UI 文本显式使用 `AppTypography` 的 sans 样式。公式样式**不写死在 `FormulaBlock`**，由 `AppTypography.formula` 提供（serif + italic + 18sp）。

### 3. Widget 颜色守门（硬规则）

- **禁止**在 `lib/presentation/` 的 Widget 中硬编码 `Color(0x...)` / `Colors.xxx` 字面量。
- 所有颜色必须经 `EditorTokens.of(context).xxx`（或其底层 `AppColors`）。
- 守门：grep `Color(0x` 在 `lib/presentation/**` 零残留（豁免：`AppColors` / `EditorTokens` 定义文件本身）。
- 字体同理：Text 样式引用 `AppTypography.xxx`，不内联 `TextStyle(fontFamily: ...)`（豁免：`AppTypography` 定义文件）。

---

## Token 值（来自 design-system/tokens.json）

### 颜色

| Token | Light | Dark |
|-------|-------|------|
| brand.primary | `#1E3A5F` | `#5B8DB8` |
| brand.primaryForeground | `#FFFFFF` | `#0F1419` |
| brand.primaryHover | `#16304F` | `#7AA5CA` |
| brand.accent | `#E76F51` | `#F4A261` |
| brand.accentForeground | `#FFFFFF` | `#0F1419` |
| semantic.success | `#2D6A4F` | `#52B788` |
| semantic.warning | `#E9C46A` | `#E9C46A` |
| semantic.error | `#C1121F` | `#E76F51` |
| surface.background | `#FAFAF7` | `#0F1419` |
| surface.foreground | `#1A1D23` | `#E8EAED` |
| surface.card | `#FFFFFF` | `#1A1D23` |
| surface.muted | `#F0EFEA` | `#242830` |
| surface.mutedForeground | `#6B7280` | `#9AA0A6` |
| surface.border | `#E5E4DF` | `#2A2F38` |
| surface.input | `#E5E4DF` | `#2A2F38` |
| surface.ring | `#1E3A5F` | `#5B8DB8` |
| editor.background | `#FDFDFB` | `#13171D` |
| editor.line | `#EFEDE6` | `#22272F` |
| editor.toolbarBg | `rgba(255,255,255,0.92)` | `rgba(26,29,35,0.92)` |
| editor.formulaBgStart | `#EBF0F5` | `#1E2A36` |
| editor.formulaBgEnd | `#E8EEF2` | `#1C2530` |

### 字体 scale（节选自 tokens.json.typography.scale）

| 用途 | 字号 | 行高 | 字重 | 字体 |
|------|------|------|------|------|
| editorBody | 15px | 1.85 | 400 | serif |
| readerBody | 16px | 1.9 | 400 | serif |
| h1 | 26px | 1.25 | 700 | serif |
| h2 | 19px | 1.3 | 600 | serif |
| sectionHeader | 18px | 1.3 | 600 | serif |
| cardTitle | 14px | 1.4 | 600 | sans |
| body (chrome) | 13px | 1.5 | 400 | sans |
| meta | 11px | 1.4 | 400 | sans |
| caption | 10px | 1.3 | 400 | sans |
| formulaDisplay | 19px | 1.4 | 400 | serif |
| statusBar | 11px | 1.0 | 400 | sans |

### 圆角 / 间距（来自 tokens.json，Phase 3.4.5.3 微调参考）

- radius：sm 6 / md 10 / lg 16 / xl 24
- spacing：pageHorizontal 24 / cardPadding 16 / paragraphGap 20 / statusBarHeight 32 / topBarHeight 48

---

## 与 ADR-0015 的关系

| 维度 | ADR-0015 | 本 ADR（0017） |
|------|----------|---------------|
| 关注点 | 主题**机制**（static const → ThemeExtension） | 主题**值** + **字体系统** + **Widget 接入规则** |
| token 常量名 | 保持不变（语义兼容） | 值改为 redesign token（§Token 值） |
| Typography | 标 `wontfix` + `phase-3.4-typography` 延期 | **撤回 wontfix**，提升为 Phase 3.4.5 P0-2 一等公民 |
| 职责 | 定义 `EditorTokens.of(context)` 封装 | 定义 `AppColors` / `AppTypography`，约束 Widget 经 token 取色 |

> **撤回声明**：ADR-0015 §已知边界 中 "inline 颜色一致性留后续 Typography Refactor，Issue `wontfix`" 的立场，被本 ADR 覆盖。字体系统不再 `wontfix`，而是 Phase 3.4.5 的**必交付项**；TextSpan 取不到 context 的技术边界仍保留（同 ADR-0015 / Phase 3.3 §9.1），但字体族（serif/mono）本身可在 `TextStyle` 构造时绑定，不依赖运行时 theme 查询。

---

## 替代方案

### 替代 B：不引入 `AppColors`，直接改 `EditorTokens` 字段值
- 拒绝：颜色数值直接进 `ThemeExtension` 实例字段会导致 light/dark 两处重复罗列，且失去纯数据层单测能力。`AppColors` 作为共享语义层更利三主题扩展。

### 替代 C：不引入 `AppTypography`，继续在 Widget 内联 `TextStyle`
- 拒绝：这正是当前 ~40% 视觉漂移的根因之一。字体族 + 字号梯度必须集中定义，否则字号/行高/字重会在各 Block 间不一致。

### 替代 D：字体直接 `ThemeData.textTheme` 全套替换
- 部分采用：`ThemeData.textTheme` 可按 `AppTypography` 派生，但语义更清晰的做法是 `AppTypography` 作为显式语义层（display/h1/formula/code），`textTheme` 仅作 Material 组件兜底。

---

## 后果

### 正面后果
1. **产品识别统一**：主色 / 字体 / 背景一次性对齐 redesign，观感从 "Flutter 默认感" 切换为 "学术编辑器"。
2. **单一真相源**：颜色改一处（`AppColors`）即全局生效；字体梯度集中，跨 Block 一致。
3. **主题一致性**：`EditorTokens` 三主题注入同一组语义 token，新增主题零改调用方。
4. **可守门**：grep `Color(0x` 零残留，防止视觉漂移回潮。

### 负面后果
1. **迁移成本**：所有 `Color(0x..)` / `Colors.xxx` 字面量改为 token 引用（需逐文件 + 守门）。
2. **字体接入成本**：`ThemeData.fontFamily` + 各 Text 显式绑定 `AppTypography`，需回归视觉。

---

## 验证计划

### 单元
- [ ] `AppColors` 为颜色单一真相源（无第二处定义同语义色值）
- [ ] `EditorTokens`（ThemeExtension）三主题实例由 `AppColors` 构建
- [ ] `AppTypography` 提供 display / h1 / h2 / body / caption / formula / code 且字体族正确（serif 文档/公式、mono 代码、sans chrome）
- [ ] `ThemeData.fontFamily` 设为 serif 默认

### 架构守门
- [ ] `lib/presentation/**` 中 `Color(0x` 字面量零残留（grep 守门，豁免 token 定义文件）
- [ ] Widget 取色经 `EditorTokens.of(context)`，无 `Colors.xxx` 直接引用
- [ ] 公式样式来自 `AppTypography.formula`，不写死在 `FormulaBlock`

### E2E（链 3 持久化强制）
- [ ] 切换 Night → 关 App → 重开 → 主题偏好保持，整体换肤（含字体）
- [ ] 主色视觉从亮 Azure 变为深海军蓝，accent 赤陶生效

---

## 参考文档
- [ROADMAP.md §Phase 3.4.5 Design System Alignment](../../ROADMAP.md)
- [ADR-0015 Theme Architecture Migration](./0015-theme-architecture-migration.md)
- [design-system/tokens.json](../../../design-system/tokens.json)
- [docs/design/ui-spec.md](../../design/ui-spec.md)

---

**本 ADR 由 AI Agent 起草，v1.0（2026-07-28），随 Phase 3.4.5 提交，Human Owner 签字即 Accepted。**
