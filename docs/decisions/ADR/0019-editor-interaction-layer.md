# ADR-0019：引入 Editor Interaction（输入意图）层

> **状态**：✅ Accepted（Human Owner 签字：2026-07-29；实施 PR #97 已合入 main）
> **版本**：v1.1
> **起草日期**：2026-07-29
> **起草人**：AI 协作开发者（基于 Human Owner Phase 3.5 评审裁定）
> **关联文档**：
> - [editor-interaction.md](../../../flutter_app/docs/spec/editor-interaction.md)（本 ADR 的行为真相源：§3 Enter 矩阵 / §4 行为 / §5 Live 同步 / §9 验收）
> - [ADR-0012 Live Editing State](./0012-live-editing-state.md)（Live/Domain 同步）
> - [ADR-0008 Editor Transaction Model](./0008-editor-transaction-model.md)（Command/Operation 既有约定）
> - [ADR-0018 App Shell 导航](./0018-app-shell-navigation.md)
> - [ADR-0020 Block Model](./0020-block-model.md)（其 Decision 5「D5：BlockRenderer 不裁决行为」以本 ADR 为权威依据，见 §0）
> - 真机问题报告 `docs/releases/phase3.5-realdevice-issues.md`

---

## 版本修订记录

- **v1.0（2026-07-29）**：初版。引入 Editor Interaction Layer 作为编辑器内核第三层抽象；冻结 7 项决策（统一经 `EditorIntentDispatcher`、以 spec 为行为真相源、废弃 `onSubmitted` 错误路径、Live 同步硬规则、视觉去边框、集中裁决禁 per-block 行为、工具栏移动端两级）；含被否决方案、守门与分期。
- **v1.1（2026-07-29，Human Owner 签字补强）**：Status 由 Proposed → **Accepted**（实施 PR #97 已合 main，结论被 ADR-0020 D5 引用）；补 §0 与 ADR-0020 的审计关系；显式析出「BlockRenderer 不裁决行为」原则（即 ADR-0020 D5 的权威来源）；相对链接修正至 canonical `docs/decisions/ADR/` 位置。

---

## 0. 与 ADR-0020 的审计关系（闭合说明）

ADR-0020 的 Decision 5（**D5：BlockRenderer 不裁决行为**——渲染与交互分离，由 Intent Layer 裁决）明确以本 ADR 为权威依据。本 ADR 的 **Decision 1 + Decision 6** 即 D5 的源头：

- **Decision 1**：所有输入事件必须先经 `EditorIntentDispatcher`，禁止 UI 层直接派发分块/编辑类命令。
- **Decision 6**：渲染组件（各 Block Widget / `BlockRenderer`）只负责绘制，**不监听输入、不派发命令、不含 per-block 行为方法**（禁止 `ParagraphBlock.onEnter()` 之类）；Intent → Command 的映射集中在 `BlockBehaviorResolver`。

=> **渲染组件不裁决行为** = 本 ADR 的必然推论，由 ADR-0020 D5 冻结引用。本 ADR 落盘前，ADR-0020 §0 将其列为审计缺口；本 v1.1 签字后即闭合。

---

## 背景（Context）

Phase 3.5 真机测试暴露一组编辑器内核缺陷（问题 #1 回车不分块 / #3 块工具条常驻 / #4 工具栏复活已删文本 / #5 工具栏溢出）。根因分析表明：FormulaFix 已实现 **Document Model（块结构）** 与 **Rendering（双态渲染）** 两层，但缺失 **Editing Intent（输入 → 行为映射）** 层。现有输入处理散落在 `base_block_state.dart`（`onSubmitted` 接 `SplitBlockCommand`）与 `markdown_toolbar.dart`（ad-hoc handler），且：

- 回车分块接在 `onSubmitted` 上——多行 `TextField` 的软键盘回车插入 `\n` 且不触发 `onSubmitted`，**真机为死代码**（P0 临时补丁 `fix/editor-kernel` 已翻车验证）。
- 工具栏命令未先 flush live，导致已删文本随格式复活（#4）。
- 回车被无脑等同于分块，未受 block 类型约束（Code/List/Quote 语义错乱）。

Human Owner 裁定：**分块不是错的，但"所有回车都变成分块"是错的；应先补 Editor Interaction Specification，再实现，不应继续在错误层打补丁。**

---

## 决策（Decision）

1. **引入 Editor Interaction（输入意图）层**作为编辑器内核第三层抽象。所有输入事件（软键盘回车、物理键、工具栏点击、粘贴）**必须先经 `EditorIntentDispatcher`**（`EditorCoordinator.dispatch(Intent)` 入口），按当前 block 类型映射到 `EditorCommand`，禁止 UI 层直接派发分块类命令。
2. **采用 `editor-interaction.md` 为唯一行为真相源**，其中 §3 Enter 矩阵 / §4 行为 / §5 Live 同步规则 / §9 验收标准为本 ADR 的强制约束。
3. **废弃 `fix/editor-kernel` 的错误层修复**：其 `onSubmitted`→`SplitBlockCommand` 路径**不合并**；其 `flushLiveSource` 与 `command_selection_sync` 的 Split/Insert focus case 列为可复用资产，纳入规范实现。
4. **Live/Domain 同步硬规则**：所有 Command 派发前必须 `flushLiveSource(blockId)`，命令处理器只读 domain（呼应 #4，呼应 ADR-0012）。
5. **视觉去边框**：块默认无边框，边界仅 hover/focus/长按显式；块操作菜单长按触发（呼应 #3）。
6. **集中裁决，禁止 per-block 行为**：Intent → Command 的映射集中在 `BlockBehaviorResolver`（单一 `switch(blockType)`），UI 层统一经 `EditorIntentDispatcher.dispatch(Intent)`。禁止在 Block 子类写 `ParagraphBlock.onEnter()` 之类 per-block 行为方法——未来新增 Table / MathBlock / Callout / Image Caption 只需在 resolver 增加分支，无需改动任何 Block 组件。**渲染组件只负责绘制，不裁决行为**（见 §0，即 ADR-0020 D5 来源）。
7. **工具栏移动端两级**：一级固定 `B I H Code +`，二级 `⋯` 收纳 `H2/H3/Link/Quote/OL/UL/Task`（手机 393px 宽度约束，呼应 #5）。

---

## 被否决方案

| 方案 | 否决理由 |
|---|---|
| 继续在 `onSubmitted` 接 `SplitBlockCommand` | 多行字段软键盘回车不触发 `onSubmitted`，真机死代码（P0 已验证） |
| `onChanged` 检测 `\n` 无脑 split | 无 block 类型判断，Code/List/Quote 全错乱 |
| 取消 Block 退回单 TextField | 违背 Block Model 与 WYSIWYG 目标 |
| 工具栏让用户手写 Markdown 语法 | 移动端低效，违背语义操作原则 |
| 在 Block 子类写 `onEnter()`/`onBackspace()` 等 per-block 行为方法 | 未来新增 Block 类型需改遍每个类；集中 `BlockBehaviorResolver.switch` 才是唯一裁决点 |
| 工具栏全按钮平铺（桌面布局搬移动端） | 手机 393px 宽度无法承载，必须两级（Decision 7） |

---

## 后果与影响（Consequences）

- **正面**：输入行为可预测、可测试；新增 block 类型只需补矩阵分支；工具栏/快捷键统一经 dispatcher，消除 ad-hoc 发散；渲染组件与行为解耦（呼应 ADR-0020 D5）。
- **负面/成本**：需新增 `EditorIntentDispatcher` 与若干 Command（ExitList/ExitQuote/MergeWithNext/CreateNextListItem 等 TODO）；现有 `base_block_state` / `markdown_toolbar` 需重构接入 dispatcher。
- **守门**：
  - Intent 层单元测试（每个 Intent → 预期 Command 映射）。
  - **回车类验收必须在真机软键盘 E2E**（模拟器 `receiveAction` 不可靠，P0 已踩坑）。
  - 架构测试 **TC-ARCH-EDITOR-1**：UI 层禁止直接 `coordinator.handle(SplitBlockCommand(...))`，必须经 `dispatch(Intent)`（已在 PR #97 落地 `test/architecture/editor_intent_layer_test.dart`）。

---

## 测试要求

- Intent 映射单测：覆盖 §3 矩阵每个 cell（Paragraph/Heading/Code/List/Quote × Enter）。
- 真机软键盘 E2E：AS-I.1~AS-I.10（见规范 §9），其中 AS-I.1/4/5/6/7/8 必须真机回归。
- `realdevice_p0_test.dart` 保留命令层分块测试；回车验收改用真机 E2E 覆盖。

---

## 实现分期（与规范 §10 一致）

- **Phase A（P0 内核，重排）**（**✅ 已合 PR #97**）：
  - **P0-1（先行）**：`EditorIntentDispatcher` + `BlockBehaviorResolver`（唯一裁决点），所有输入事件统一经 `dispatch(Intent)`；删除 `onSubmitted` 错误路径。
  - **P0-2**：Enter 矩阵（Paragraph/Heading → Split；Code → 块内换行）经 dispatcher 落地，软键盘 `\n` 由 `TextInputFormatter` 拦截（真机正确通路）。
  - **P0-3**：Backspace 块首合并经 dispatcher，焦点移到连接点。
  - **P0-4**：ToolbarActionIntent 经 dispatcher；两级工具栏（一级 B/I/H/Code/+，二级 ⋯ 收纳 H2/H3/Link/Quote/OL/UL/Task）；含 flush 硬规则。
- **Phase B（P1）**：List/Quote 续行与退出、Markdown shortcut、ToolbarAction 全映射、视觉去边框。
- **Phase C（P2）**：Tab 缩进、Delete 合并、Paste 分块。

---

## 审批

- [x] Human Owner 签字（Accepted）—— 2026-07-29
- [x] 关联 PR #97（Editor Intent Layer）已合入 main
- [ ] 后续：Phase B / C 行为补全（不阻塞本 ADR 生效；本 ADR 仅冻结交互层抽象与裁决边界）
