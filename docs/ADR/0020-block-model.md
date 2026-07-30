# ADR-0020：Block Model 冻结规范

- **状态**：✅ Accepted（Human Owner 签字：2026-07-29）
- **日期**：2026-07-29
- **决策者**：Human Owner（裁定三大架构问题 + Block 改进方向）；AI Agent 起草
- **关联**：[ADR-0003 存储单一真相源](./0003-storage-single-source-md-files.md) / [ADR-0007 BlockEditor 抽象设计](./0007-blockeditor-abstraction-design.md) / [ADR-0008 Editor Transaction Model](./0008-editor-transaction-model.md) / [ADR-0018 App Shell 导航](./0018-app-shell-navigation.md) / [ADR-0019 Editor Interaction Layer](./0019-editor-interaction-layer.md)（D5 权威依据，见 §0）

---

## 0. 背景与已知缺口

**Block 模型定位（本 ADR 的核心价值）**：Block 不是「一个输入框」，而是 `Document AST` 中的**语义单元**。完整数据流为：`User Input → Intent Layer → Command → Transaction → AST → Renderer → Markdown Serializer`。该定位是后续所有决策（尤其 D5）的出发点——渲染组件只画不裁决，避免 `ParagraphWidget` 退化为同时处理输入 / 保存 / undo / split / format 的 God Object。

Phase 2 进入块级编辑内核后，出现三类反复出现的架构问题：

1. **AST 与 Markdown 双真相**：UI 直接读 `Document.content` 渲染，绕过 AST，导致编辑态与序列化态漂移。
2. **BlockId 脆弱**：`BlockId.value` 为 `int` 自增，分块/合并/撤销时易出现身份重用与碰撞。
3. **Command 无事务**：编辑操作（`BlockOperations`）是 eager apply 的隐式执行器，多步编辑无法原子撤销。

本 ADR 将 Block 模型冻结为 5 个决策（D1–D5）与 1 条类型扩展原则（D6），并划分为 A–E 五期实施。其中 A、B 已完成并合入 main；C、D、E 待本 ADR 签字后开工；D6 为已接受原则、无独立实施期。实施优先序经 Owner 评审调整为 **C（去边框）→ E（Transaction）→ D（UUID）**（见 §3 与 §0.1）。

### 文档审计状态

- **ADR-0019（Editor Interaction Layer）文档已落盘并签字 ✅**：其决策已在 PR #97（Intent Layer）实现并合入 main；`docs/ADR/0019-editor-interaction-layer.md` 已增补为 **✅ Accepted（v1.1，2026-07-29）**，并与本 ADR D5（BlockRenderer 不裁决行为）建立审计关系（见 ADR-0019 §0）。**本审计缺口已闭合（PR #101）**。原草稿曾误置于 `flutter_app/docs/ADR/`，现统一归位到 canonical `docs/ADR/`（与全部 ADR 一致）。
- **本 ADR（0020）此前仅在记忆笔记中起草**，本次为首次落盘（PR #100 已合 main）。

### 0.1 Owner 评审要点（2026-07-29，未签字前记录）

Owner 对本 ADR 的核心判断，作为后续裁定锚点：

- **最大价值确认**：Block 从 UI 抽象提升为领域模型（AST 语义单元）是本 ADR 最大价值；D5「BlockRenderer 不裁决行为」为关键冻结，须坚决守住，防止渲染组件退化为 God Object。
- **D1 / D4 认可**：D1 AST 单一真相源方向正确，应冻结；D4 去边框不只是 UI 修改，是在修正用户心智模型（从「多个独立输入框」→「Document Surface」），C 期放置合理。
- **D2 优先级下调**：UUID 解决的是 **session 内唯一性**，非跨 session 恢复；对单机编辑收益有限，属工程质量提升，优先级应**低于** Transaction（D3）。
- **D3 风险最高、影响面最大**：Transaction 改造波及 Command / History / Undo / Paste / AI 修改 / 多块操作，是编辑器生命线，须先 spike。
- **Transaction 粒度（D3 补强）**：禁止「每字符一事务」；须采 **typing session 合并**（undo grouping，类 VS Code）——输入 `hello` 为一个 Transaction（内含 5 个 Insert 操作），Ctrl+Z 一次性回退整词。
- **Selection / Cursor Identity 遗漏（补一句）**：BlockId UUID **不解决** selection mapping。块 merge/split 时光标与选区的迁移映射（blockId + offset）属于 Intent / Transaction 层职责（建议归 ADR-0019 或新 ADR-0021），不得误以为 UUID 能恢复光标。
- **建议补充 1：Block 生命周期规则（放 D2 后）**：需显式定义 Create / Split / Merge / Transform / Delete / Serialize / Deserialize 七态，并回答「谁生成 ID / 谁销毁 ID / History 如何保存」。已落盘为 §2「Block Lifecycle Rules」小节。
- **建议补充 2：Block 类型扩展克制原则（新增 D6）**：类型增加须由真实编辑语义驱动，禁止由渲染需求驱动（如 `BlueTextBlock`/`RedTextBlock` ❌；`CalloutBlock`/`MathBlock`/`TableBlock` ✅），防止 AST 爆炸。已落盘为 D6（✅ Accepted 原则，无独立实施期）。
- **建议补充 3：D3 Transaction 描述纠偏（eager apply）**：原「提交时统一 apply」易误导实现者做延迟 apply，与 Flutter `TextField` 实时变更模型冲突。改为：**编辑态允许 eager apply，Operation 发生时即 apply 并登记进当前 Transaction；`commit` 负责确认历史节点，`rollback` 负责逆向恢复**。已修正 §2 D3 决策段。

---

## 1. 决策总览

| 决策 | 内容 | 状态 | 实施期 | 落点 |
|------|------|------|--------|------|
| D1 | AST 单一真相源（Markdown 降级为序列化格式，UI 禁直接读 `Document.content`） | ✅ Accepted / 已合 #96 | A | `core/parser/markdown_serializer.dart` + `model_content_gate_test.dart` |
| D2 | BlockId：`int` 自增 → `String` UUID（in-memory identity，不持久化） | 🔧 实施中（PR #104） | D | `core/editing/block_types.dart` |
| D3 | Command → Transaction：`TransactionBuilder` 注入，`EditOperation` apply/revert 原子性 | 🔧 实施中（E spike, PR #103） | E | `core/editing/transaction*.dart` + `command_handler.dart` 失败原子回滚 |
| D4 | 去边框：块编辑 `decoration` → `InputBorder.none` | 🔧 实施中（PR #102） | C | `lib/presentation/blocks/**` |
| D5 | BlockRenderer 不裁决行为（渲染与交互分离，由 Intent Layer 裁决） | ✅ Accepted / 已合 #97 | B | ADR-0019（见 ADR-0019 §0） |
| D6 | Block 类型扩展克制原则（类型增加须由真实编辑语义驱动，禁渲染需求驱动） | ✅ Accepted（原则，无独立实施期） | — | 本 ADR §2 D6 + TC-ARCH-MODEL-5 |

> 净新增工作 = **C（去UI）/ D（UUID）/ E（Transaction）** 三项；D6 为已接受原则，无实现期。

---

## 2. 决策详述

### D1 — AST 单一真相源（✅ 已落地）

- **决策**：`DocumentElement` AST 是编辑态唯一真相；Markdown 仅作为序列化格式（经 `MarkdownSerializer.serialize` 导出）。`presentation/` 层禁止直接读 `Document.content` 字符串渲染。
- **现状**：PR #96 已合入 main（`flutter_app/lib/core/parser/markdown_serializer.dart` + `flutter_app/test/architecture/model_content_gate_test.dart` 守门 TC-ARCH-MODEL-1）。`getDocumentPreview` 经 Repository 取首行预览，UI 不直接读 content。
- **守门**：TC-ARCH-MODEL-1（presentation 层 `doc.content` 零直接引用，editor_page 加载豁免）。

### D2 — BlockId → UUID（⬜ 待实施，优先级低于 D3；**含冲突裁定**）

- **现状**：`core/editing/block_types.dart:23` 的 `BlockId` 当前 `final int value`，注释已预留「未来可扩展为 String UUID」。
- **决策（类型）**：`BlockId.value` 由 `int` 改为 `String`（UUID v4）。构造从 `BlockId(n)` 改为 `BlockId.generate()`（factory）或 `BlockId(String value)`；`==`/`hashCode` 基于 String 不变。`BlockOperations.split` 等新块身份用 `BlockId.generate()` 生成，会话内零碰撞。
- **决策（生命周期）— 与 ADR-0008 §9 的冲突裁定**：
  - ADR-0008 §9 明确：**BlockId 是 in-memory identity，不跨序列化边界持久化**（持久化需 frontmatter/sidecar = 第五套存储，违反 ADR-0003 §边界约束 5）。
  - **本 ADR 裁定**：D2 仅改变 BlockId 的**表示类型（int→uuid）**，**不**改变其 in-memory 生命周期约束。即 BlockId 仍是「当前 Document session 内有效、保存 .md 时不写入、加载时重新分配」。此裁定与 ADR-0008 §9 完全兼容，且兑现了 `block_types.dart:24` 的预留注释。
  - **「跨会话」诉求的处理**：若未来确需跨 session 稳定身份（协同编辑 / 崩溃恢复），**不得**通过把 BlockId 持久化进 .md 实现；必须按 ADR-0008 §9「未来扩展边界」的规定——先 **supersede ADR-0008 §9**（标记 Superseded by ADR-NNNN），评估与 ADR-0003 兼容性，并引入独立 stable identity 方案（UUID + Vector Clock 等）。**该能力不在本 ADR 范围**，作为独立 ADR 候选。
- **影响面**：`BlockId` 所有构造点（`BlockOperations.split/move/insert`、`BlockOperation` preserveId 上下文、`DocumentEditor`、`EditorHistory`）。机械替换，但调用点多，需 D 期 PR 全量扫描。
- **守门（D 落地后生效）**：TC-ARCH-MODEL-2（扫描 `presentation`/`core` 禁止 `BlockId(` 接 int 字面量）。
- **优先级与收益边界（Owner 评审 §0.1）**：UUID 仅解决 **session 内身份唯一性**，不提供跨 session 恢复；对单机编辑器的边际收益有限，本质是工程质量提升，故优先级排在 D3 Transaction 之后（实施序 C → E → D）。
- **Selection / Cursor Identity 不在此决策范围（Owner 评审 §0.1）**：BlockId 改 UUID **不会**自动解决光标 / 选区的 merge/split 映射。当 `Block A` 发生 Enter 拆分为 `A' + B` 时，光标从 `A.end` 迁移到 `B.start` 的「Selection Transform」属于 Intent / Transaction 层职责（建议归 ADR-0019 或新 ADR-0021），须单独设计。不得误以为 UUID 能恢复光标位置。

### Block Lifecycle Rules（置于 D2 后，补充建议 1）

Block 在编辑内核中经历七态，须显式定义其 ID 与 History 归属。本规则与 D2（UUID）、D3（Transaction）配合，是 Block 作为领域模型的运行时契约。

| 状态 | 含义 | ID 生成 / 销毁 | History 归属 |
|------|------|---------------|-------------|
| Create | 新建块 | `BlockId.generate()` 生成新身份 | 登记为 `EditOperation` 进当前 Transaction |
| Split | 一块按 offset 拆为两块 | 原块保留身份；新块 `BlockId.generate()` | Split 两步登记进同一 Transaction，可原子撤销 |
| Merge | 两块合并为一块 | 被并入块（next）的身份随移除**失效**（in-memory 不可达即销毁）；prev 身份不变 | 与 Split 互逆，登记进同一 Transaction |
| Transform | 块类型转换（如 Paragraph→Heading） | **身份保留**，仅改 `type` 字段 | 登记为 `EditOperation` 进当前 Transaction |
| Delete | 删除块 | 身份随移除**失效**（无显式 free；in-memory 引用不可达即销毁） | 与 Create 互逆 |
| Serialize | AST → Markdown | **不写入 BlockId**（ADR-0008 §9 / ADR-0003；见 M6） | 不进历史（I/O，非编辑动作） |
| Deserialize | Markdown → AST | 加载时 `BlockId.generate()` **重新分配**（D2 in-memory 生命周期） | 不进历史 |

**关键裁定**：
- **ID 生成方**：唯一入口 `BlockId.generate()`（UUID v4），仅 `BlockOperations.create` / `BlockOperations.split` 调用。
- **ID 销毁方**：`BlockId` 无独立销毁 API；其生命周期跟随块从 AST 移除（Delete / Merge 的被并入块）自动失效——因 BlockId 是 in-memory 引用，移除即不可达，无需显式 free。
- **History 保存**：Create / Split / Merge / Transform / Delete 每个动作都作为 `EditOperation` 登记进当前 `Transaction`（D3）；`Transaction.commit()` 后成为历史栈的一个节点（undo/redo 粒度）。Serialize / Deserialize 不进历史。
- **Split / Merge 的光标映射**：由 Selection Transform（Intent / Transaction 层，见 D2 Selection 注记 / ADR-0019 / 0021 候选）负责，不在 Lifecycle Rules 内解决。

### D3 — Command → Transaction（⬜ 待实施）

- **现状**：`BlockOperations` 是 eager apply 的隐式执行器（ADR-0008 §10 记为 acknowledged tech debt）。`EditOperation`（apply/revert）已存在但未纳入显式事务边界。
- **决策**：引入 `TransactionBuilder`，聚合某次编辑手势内的多个 `EditOperation` 为原子 `Transaction`。**编辑态允许 eager apply**——`TextField` 等输入控件可实时改变，对应 `Operation` 在发生时即 apply 并登记进当前 Transaction；`Transaction.commit()` 负责**确认历史节点**（落历史栈），`rollback()` 负责在失败 / 取消时按逆序 revert 恢复。即：Transaction **不要求所有 Operation 延迟执行**，但必须在 Transaction 生命周期内登记 operation，并保证失败时可原子 revert。Undo/Redo 栈以 `Transaction` 为粒度。
- **事务粒度（Owner 评审 §0.1，D3 补强，E 期必须遵守）**：**禁止「每字符一个 Transaction」**。须采用 **typing session 合并（undo grouping，类 VS Code）**：
  - 连续键入 `hello`：`Insert(h/e/l/l/o)` 在键入时即 **eager apply** 并逐个登记进当前 typing Transaction（UI 实时变化，无延迟）；`commit` 在该手势结束时闭合历史节点，Ctrl+Z 一次性回退整词，而非逐字符 `o → l → l → e → h` 五次撤销。
  - 边界判定：同一输入焦点内的连续文本编辑合并入当前 typing Transaction；焦点切换 / 方向键移动 / 工具栏命令 / 粘贴 / 格式操作 触发 commit 并开启新 Transaction。
  - 粘贴（insert N blocks）、格式（wrap selection）、AI 修改（多块替换）、多块操作 各自为**单个** Transaction。
  - 历史栈以 Transaction 为单元，避免「输入一个字 commit 一次」导致性能与历史栈爆炸。
- **与 ADR-0008 关系**：本决策是 ADR-0008 §10「TransactionExecutor 设计方向（Phase 2.8+ 候选）」的落地延续。E 期实施时须复用 ADR-0008 的 `Transaction` 不可序列化约束（§7）：Transaction 仅内存态，不持久化。
- **风险**：高（编辑内核核心抽象变更）。建议 E 期先行 spike，再全量替换 `BlockOperations` 直调点。
- **守门（E 落地后生效）**：TC-ARCH-MODEL-3（禁止在 coordinator/dispatcher 之外直接 `BlockOperations().x()` 提交；必须经 `TransactionBuilder`）。

### D4 — 去边框（🔧 实施中，PR #102 待合并）

- **决策**：块编辑组件（`TextField`/`TextFormField` 的 `decoration`）统一 `InputBorder.none`；聚焦指示改由 caret + 主题 token 的 subtle 背景区分，不再用 box border。涵盖 `heading_block` / `paragraph_block` / `code_block` / `list_block` / `blockquote_block` / `formula_block` 等所有 `base_block_state` 派生编辑组件。
- **风险**：低（纯 UI）。实测 WSL golden 对比无像素差异（块编辑 border 未在 golden 捕获范围内），无需更新基线；若后续引入 focus 背景再评估。
- **守门（已生效）**：TC-ARCH-MODEL-4（扫描块编辑组件 `decoration` 必须为 `InputBorder.none`，禁止 `OutlineInputBorder`/`UnderlineInputBorder`，见 `test/architecture/block_border_gate_test.dart`）。

### D5 — BlockRenderer 不裁决行为（✅ 已落地）

- **决策**：渲染组件只负责画，不监听输入/不派发命令；所有交互经 Intent Layer（ADR-0019）`dispatch → resolve → handle` 管线。
- **现状**：PR #97 已合入 main，TC-ARCH-EDITOR-1 守门（UI 层禁止直接 `coordinator.handle(...)`）已落地。
- **文档缺口**：ADR-0019 文档未落盘（见 §0），建议补写闭合审计。

### D6 — Block 类型扩展克制原则（✅ Accepted 原则，无独立实施期）

- **决策（原则）**：Block 类型（AST 节点种类）的增加**必须由真实编辑语义驱动**，禁止由渲染 / 视觉需求驱动。目的是防止 Block 类型无限膨胀导致 AST 爆炸与维护成本失控。
- **反例（拒绝）**：`BlueTextBlock`、`RedTextBlock`、`LargeTextBlock`——把颜色 / 字号等**表现属性**提升为独立 Block 类型，本质是渲染需求，应改为「同类型 Block + 样式属性 / inline mark」表达。
- **正例（允许）**：`CalloutBlock`（警示语义）、`MathBlock`（公式语义）、`TableBlock`（表格语义）、`QuoteBlock`、`CodeBlock`——承载独立编辑行为（不同 split / merge / 选中 / 序列化规则）的语义单元。
- **判定门槛**：新增 Block 类型前须能回答「它有区别于现有类型的**编辑行为**差异（split / merge / selection / serialize 规则不同）？」若仅视觉不同，不得新增类型，改用样式 / inline mark。
- **守门（D6 落地后生效）**：TC-ARCH-MODEL-5（架构扫描：禁止 Block 子类名含颜色 / 尺寸等渲染语义词，如 `*Color*Block` / `*Size*Block`；新增 Block 类型须在本 ADR 或独立 ADR 登记语义理由）。
- **实施期**：无（原则冻结，自签字起立即生效，无需独立 PR）。

---

## 3. 实施路线图（A–E）

| 期 | 名称 | 对应决策 | 状态 | PR / 落点 |
|----|------|---------|------|-----------|
| A | 冻结引擎（AST 单一真相源） | D1 | ✅ MERGED | #96 |
| B | Intent Layer | D5 | ✅ MERGED | #97 |
| C | 去 UI（去边框） | D4 | 🔧 实施中 | PR #102（chore/block-no-border） |
| E | Transaction（先 spike） | D3 | 🔧 实施中（PR #103） | `refactor/editor-transaction` |
| D | 补类型（BlockId UUID） | D2 | 🔧 实施中（PR #104） | 新分支 `refactor/block-id-uuid` |

**开工顺序（Owner 评审调整）**：**C（低风险纯 UI）→ E（高风险内核抽象，编辑器生命线，先 spike）→ D（机械类型迁移，工程质量提升）**。

> 调整理由：Transaction 改造波及 Command / History / Undo / Paste / AI 修改 / 多块操作，是编辑器生命线；UUID 仅 session 内身份唯一性，属工程质量，优先级后置（详见 §0.1）。
> 注：D6（类型扩展克制）为已接受原则，不占 A–E 实施期，自签字起立即生效。

---

## 4. 架构守门（TC-ARCH-MODEL-1~5）

| 编号 | 守门内容 | 状态 | 文件 |
|------|---------|------|------|
| TC-ARCH-MODEL-1 | presentation 层禁直接读 `Document.content` | ✅ 已生效 | `test/architecture/model_content_gate_test.dart` |
| TC-ARCH-MODEL-2 | 禁止 `BlockId(` 接 int 字面量 | ✅ 已启用（PR #104） | `test/architecture/block_id_type_test.dart` |
| TC-ARCH-MODEL-3 | 编辑操作经 `TransactionBuilder`，禁 `BlockOperations` 直调 | ✅ 已启用 | `test/architecture/transaction_gate_test.dart` |
| TC-ARCH-MODEL-4 | 块编辑 `decoration` 必须为 `InputBorder.none` | ✅ 已启用 | `test/architecture/block_border_gate_test.dart` |
| TC-ARCH-MODEL-5 | 禁止 Block 子类名含渲染语义词（`*Color*Block`/`*Size*Block`）；新增 Block 类型须登记语义理由 | ⬜ D6 生效即启用 | 新增 `test/architecture/block_type_gate_test.dart` |

---

## 5. 验收标准（M1–M7）

| 编号 | 验收项 | 状态 |
|------|--------|------|
| M1 | AST 为唯一编辑态，UI 无 `Document.content` 直读 | ✅（D1） |
| M2 | 回车/退格/工具栏/模板插入全经 Intent Layer dispatch | ✅（D5/B） |
| M3 | 任意块编辑组件无可见 box border（三主题） | ✅（D4/C, PR #102） |
| M4 | BlockId 为 uuid 且会话内稳定、零碰撞 | ✅（D2/D，PR #104） |
| M5 | 多步编辑可原子 undo/redo（Transaction 粒度） | ✅（D3/E spike, PR #103） |
| M6 | 序列化 .md 不含 BlockId / Transaction（单一真相源） | ✅（ADR-0003/0008 约束） |
| M7 | 无渲染需求驱动的 Block 类型（无 `*Color*Block`/`*Size*Block`；新类型有登记语义理由） | ⬜（D6） |

---

## 6. 被否决方案

- **BlockId 持久化进 .md frontmatter**：违反 ADR-0003 §边界约束 5（引入第五套存储）；采纳 §9 的 in-memory 约束。
- **DocumentElement.id 直接复用为 BlockId**：两者是不同命名空间（`DocumentElement.id` 已是 String，用于 AST 节点；`BlockId` 是编辑内核身份）。本期保持独立，未来若需统一须经单独评估（不在本 ADR）。
- **D 期同步做 E（Transaction）**：风险叠加，拆分两期，E 先 spike。
- **BlockId UUID 解决 Selection/Cursor 恢复**：UUID 只改身份类型，不提供 merge/split 时光标/选区映射；Selection Transform 属 Intent/Transaction 层（ADR-0019 / 0021 候选），不在本 ADR。

---

## 7. 后续动作

1. ✅ Human Owner 已签字（2026-07-29），Status → Accepted；本 ADR 正式生效。
2. 补写 ADR-0019 文档（闭合 D5 审计链，§0 缺口）。
3. 按 §3 顺序开工 **C → E → D**，每期独立 PR + 对应 TC-ARCH-MODEL 守门测试。E 期 spike 结论（PR #103）：`BlockOperations` 全仓库仅 `command_handler.dart` 一处实例化（单入口），故「全量替换直调点」无额外工作；唯一缺口是 `CommandHandler` 失败路径此前只 `builder.rollback()`（纯清空）未 revert 已 apply 的 op → 已补 `revertBuilder` helper 闭环 D3 原子性（typing session 粒度在生产已成立：一次焦点输入 = 一个 `UpdateBlockSourceCommand` = 一个 Transaction）。D 期（PR #104）：`BlockId.value` 由 int 自增改为 String UUID v4（in-memory identity，不持久化，对齐 ADR-0008 §9）；分配统一走 `BlockId.generate()`，三个 DocumentEditor 实现（生产 + prototype + Mock）移除 `_nextIdValue` 计数器，117 处测试夹具 `BlockId(int)` → `BlockId('int')` 机械迁移，TC-ARCH-MODEL-2 守门落地。
4. C 期触发 golden 基线更新（RRS `golden-update` job，`workflow_dispatch` + `update_goldens`）。
5. D6 类型扩展克制原则自签字起生效：新增 Block 类型须登记语义理由并过 TC-ARCH-MODEL-5 守门（无独立 PR）。
