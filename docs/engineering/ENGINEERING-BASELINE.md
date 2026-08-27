# Phase 3.10 — Engineering Debt & Historical Decision Review
## FormulaFix Engineering Baseline v1

> **文档性质**：复盘 / 决策文档（Review-only，零代码改动）
> **日期**：2026-08-19
> **版本**：v1.2（v1.0 纯审计推导 → v1.1 补真实代码验证层修正 4 处 → **v1.2 治理收敛**：仅做分类与规则一致性收敛，不扩大复盘范围）
> **作者**：AI Agent 起草，Human Owner 评审决策
> **前置条件**：Phase 3.9 功能审计已积累充分证据（E2E + ADI + Capability Audit + Behavior Audit + Export Audit + 真实消费端）
> **本 Phase 目标**：在"事实层"已建立的前提下，**先把所有历史问题重新分类**，再建立工程基线，而不是立即开始修。
> **v1.2 收敛范围（明确冻结）**：本次仅解决"分类与规则的一致性"——新增 `debt_state` 字段、拆分 Core Stable、补 RULE-FFX-001 的 P0 例外、升级三源真理模型、统一精确计数、补 ADR 复审档期、提升 DEBT-014+015 为架构复审 A-001、重分类 DEBT-032/033、追加单页真相表。**不再扩大复盘对象**。
> **验证纪律（三源真理模型，v1.2 升级）**：v1.0 仅依据审计文档推导，已被指出"未用实际代码验证"，v1.1 已补代码实证层。v1.2 将"代码即真理"细化为 **三源真理模型**，任何结论须能落到三源之一并标注冲突消解规则：
> - **Implementation Truth（实现真相）**：`flutter_app/lib` 真实代码 `file:line` + `git log` 提交史，是最终事实层。
> - **Decision Truth（决策真相）**：已 Accepted 且经 Human Owner 签字的 ADR + 本文档 Debt 判定，是架构意图的权威来源。
> - **Evidence Truth（证据真相）**：Test / Audit / Runtime（经 ADI）可观测证据，用于判定"系统实际是否真的坏了"。
> - **冲突消解**：Implementation Truth 优先于审计文档叙述；Decision Truth（Owner 签字 ADR）优先于无主见的重构冲动；Evidence Truth 用于判定缺陷是否真实存在。三者冲突时显式标注于本文档。

---

## 0. 本复盘的核心纪律

> **没有历史决策，就不要擅自重构。**

这条规则是本次复盘最重要的一条产出。它直接对抗工程复盘最常见的失败模式——

- "看起来丑 → 我重构一下" → 把以前为了某种约束做的东西拆掉；
- "以前的人怎么写成这样" → 陷入找人背锅，而不是判断旧约束是否还存在；
- "既然现在知道这么多历史问题，那全部修掉" → **债务清零幻觉**，把低成本/低风险/用户无感的合理妥协也一并推翻。

本复盘的第一个结论：**FormulaFix 当前最大的技术债，不是代码，而是"已经失效的架构假设仍然被当成规则"**。因此本基线文档的首要读者是未来的 Agent（Claude / Codex / 下一个协作者），让它看到一段"奇怪代码"时，能先知道：

```
这是历史妥协 / 这是已接受技术债 / 这是刻意设计 / 这是已过期设计 / 这是明确该修的 bug
```

而不是默认"该重构"。

---

## 1. 执行摘要（Engineering Baseline v1）

本次复盘将历史问题归并为 **6 大类（A–F）**，对 **30 个 ADR** 做 4 态复盘，并将 45 个已盘点的历史问题（来自 11 个子系统）按状态精确对账为 **5 类最终归属**（Core Stable / Debt Accepted / Refactor Needed / Verification Gap / Research Q，详见 §1.1 与 §8 单页真相表）。

```
              FormulaFix Engineering Baseline v1
                            │
        ┌──────────┬────────┼─────────┬──────────┐
        ↓          ↓        ↓         ↓          ↓
   Core Stable  Debt     Refactor  Verif.     Research
                 Accepted  Needed   Gap        Q (RQ)
   核心稳定      已接受    需重构    验证缺口    研究问题
   (冻结守门)    (保留)   (roadmap) (非产品债) (非债)
```

### 1.1 三条分区的规模（v1.2 精确计数，不再用估计值）

> v1.2 收敛要点：将 §1 宏观三分区与 §8 详细五源真相表对齐，所有数字均为精确计数，且 45 问题总数可完整对账（见下表）。"~"估计值已全部消除。

| 分区 | 含义 | 精确条目数 | 治理动作 |
|------|------|-----------|---------|
| **Core Stable** | 已验证、已测试、架构成立，不应随意改动（细分见 §5.1：Architecture Stable / Behavior Stable） | **12** | 加冻结守门测试，禁止无 ADR 改动 |
| **Debt Accepted** | 当时合理、现在仍有保留价值的妥协 | **16** | 写清"为什么合理"+ 偿还条件，不修 |
| **Refactor Needed** | 局部最优已变全局代价 / 明确未决 bug（产品/架构） | **8** | 进 roadmap，附触发条件与退出判据 |
| **Verification Gap** | 验证基础设施缺口（非产品债，见 DEBT-032） | **1** | 补采集/守门，非功能重构 |
| **Research Q** | 研究问题（非债，见 DEBT-033 → RQ-001） | **1** | 立项研究，非缺陷修复 |

> 注：Refactor Needed 仅 8 条且**绝大多数应排期而非立即做**；真正 P0 仅 **Architecture Review A-001（原 DEBT-014+015）** 1 条。详细五源真相表见 §8。

### 1.1.1 45 问题总数对账（v1.2 精确）

| 状态 | 含义 | 数量 | 条目 |
|------|------|------|------|
| **Resolved** | 已消除 / 已修复 / 已完成（闭环） | 14 | DEBT-008·019·022·023·024·025·026·034（8 债）+ BUG-1~6（6 bug，fuzz 锁死） |
| **Accepted** | 已接受债务（保留 + 偿还条件） | 16 | DEBT-001·002·003·004·007·010·011·013·018·020·021·027·028·029·030·035 |
| **Refactor** | 需重构（产品/架构） | 8 | DEBT-005·006·009(=017)·012·014+015·016·031 |
| **Verification Gap** | 验证基础设施缺口 | 1 | DEBT-032 |
| **Research Q** | 研究问题（非债） | 1 | DEBT-033 → RQ-001 |
| **Obsolete** | 废弃 / 编号占位 | 2 | DEBT-036·037 |
| **Governance** | 治理卫生（并入 ADR 复盘，非独立债） | 3 | ADR-0009 状态不一致 + ADR-0016·0018·0029 状态滞后 |
| **合计** | | **45** | 与 §1 开头"45 个已盘点历史问题"完全一致 |

> 说明：Core Stable 的 12 个锚点（§5.1）是从 Resolved + Accepted 中抽出的"冻结守门"精选集（ADR-0007/0020/0022/0024、BUG-1~6、E2E-CORE-001~006、Phase 3.5/3.7、Design System、文件树/TOC/自动保存/主题、真机 P0 修复），用于"禁止无 ADR 改动"的守门，与上方按状态的对账互为视图，不重复计数。

### 1.2 本 Phase 明确"暂不修"的清单（债务清零幻觉的反例）

以下条目经判定为 **低成本 / 低风险 / 功能稳定 / 测试充分 / 用户无感**，本次**不做修复**，仅登记：

- 手写 Markdown Parser 的"非核心语法边缘 case"（已由 fuzz 回归锁死边界）
- 手写 Word OOXML 导出（已从"半成品"转为"可控后端"，债应降级而非重写）
- 两套颜色常量并存（短期接受，P3 语义化治理）
- 代码块语法高亮不随主题切换（Phase 4 前接受）
- 真机 soft-keyboard IME / MS Word Desktop 等"尚未完成的产品边界"（单独管理，非 bug）

---

## 2. Part I — 历史 ADR 复盘（4 态判定）

判定维度不是"当时是否正确"，而是 **"在当前 2026-08-19 的系统规模与需求下，是否仍是最优架构"**。

| 状态 | 含义 | 动作 |
|------|------|------|
| **VALID** | 原则与实现仍成立 | 继续遵守，可加守门测试 |
| **VALID-BUT-COSTLY** | 原则成立，但实现需要重构 | 保留架构，排期重构实现 |
| **SUPERSEDED** | 被新架构替代 | 标记废弃，引用新 ADR |
| **EXPIRED** | 当时特定阶段的临时决策，现在应删除 | 删除或降级为历史注释 |

### 2.1 ADR 状态总表

| ADR | 主题 | 文档状态 | 2026-08-19 判词 | 关键说明 |
|-----|------|---------|----------------|---------|
| 0001 | 项目命名与目录结构 | Accepted | **VALID** | 基础约定，无需动 |
| 0002 | Riverpod 状态管理 | Accepted | **VALID** | 唯一状态方案，禁止引入 bloc/getx |
| 0003 | .md 单一真相源 | Implemented | **VALID** | 仅当未来 SQLite+全文索引才 Deprecated |
| 0004 | 手写 Markdown 解析器 | Proposed | **VALID-BUT-COSTLY** | 保留手写决策正确；但解析器已成需持续维护的复杂设施（BUG-1~6 round-trip 经 fuzz 暴露）。**建议升级为 Accepted 并补 fuzz 回归守门**。代码实证：`lib/core/parser/markdown_parser.dart`（~500 行纯手写，无第三方解析库） |
| 0005 | Exporter facade + DI | Accepted | **VALID** | facade 模式正确；内部 Exporter static 状态污染是已知债（见 DEBT-009 类） |
| 0006 | GitHub Actions CI | Accepted | **VALID** | 选型成立 |
| 0007 | BlockEditor 抽象 | Accepted | **VALID** | Addendum 明确 AST 稳定不重构 |
| 0008 | Editor Transaction Model | Proposed | **VALID-BUT-COSTLY** | 核心模型（操作日志/commit-rollback/coalescing）正确，但 IME coalescing 未实现 + 空 Transaction 守卫（R2）+ §9 与 ADR-0020 冲突已裁定。**是重构主战场之一**。代码实证：`lib/core/editing/transaction_builder.dart:63` + `editor_history.dart:144` `_defaultCanCoalesce`（7 规则）；空事务以 no-op 守卫实现（transaction_builder.dart:168 / editor_history.dart:146），非 `_emptyCurrentState()` |
| 0009 | UI Architecture Design | 文档头 Accepted / ADR-0011 引为 Proposed | **VALID（但状态不一致）** | ⚠️ 状态字段与 ADR-0011 引用冲突，属治理卫生问题，建议统一为 Accepted |
| 0010 | 编号跳号占位 | SKIPPED | **N/A** | 非决策，编号纪律占位 |
| 0011 | Phase 3.3 架构决策 | Accepted | **VALID** | 5 条细化决策成立 |
| 0012 | Live / Committed 双状态分离 | Accepted | **VALID-BUT-COSTLY** | ⭐ **首要重构候选**。当时为输入性能/TextField 生命周期，现在与 Undo / Coalescing / Focus / Selection 均产生张力。保留架构，重构事务桥。代码实证：`live_editing_state.dart:20` `class LiveEditingState` + `_liveSources` Map（`sourceOf` live 优先 fallback 到 `InMemoryDocumentEditor` committed）；`editor_coordinator.dart:37,54` 持有 `_live` |
| 0013 | 自动保存架构 | Accepted | **VALID** | 构建于 ADR-0012，dirty 来源清晰 |
| 0014 | 文档资产管理 | Accepted (v1.2) | **VALID** | 内容寻址 + 原格式保留，架构决策合理 |
| 0015 | 主题架构迁移（static→ThemeExtension） | Accepted | **VALID** | 机制成立 |
| 0016 | 文档仓储边界 | Proposed | **VALID** | 边界原则成立，待 Owner 签字转正 |
| 0017 | Design System Token 对齐 | Accepted | **VALID** | token 单一真相源成立 |
| 0018 | App Shell 导航 | Proposed | **VALID** | 核心冻结（indexedStack / documentListProvider），待签字 |
| 0019 | Editor Interaction Layer | Accepted (v1.1) | **VALID** | Intent Layer 已落地（PR #97） |
| 0020 | Block Model 冻结 | Accepted | **VALID** | 经裁定解决 ADR-0008 §9 冲突，是稳定锚点。代码实证：`document.dart:1` `sealed class DocumentElement`；`:24` `ListElement.nested`（嵌套 AST，解决 BUG-5） |
| 0021 | 仓储完整性策略 | — | **VALID** | 引用成立 |
| 0022 | Renderer Failure Policy | — | **VALID** | UnsupportedBlockFallback 是**刻意守卫**，非缺陷。代码实证：`fallback_block_renderer.dart:1` "落地 ADR-0022"；`:90` `captureError(type:'UnsupportedBlockFallback')` |
| 0023 | Editor Observability | — | **VALID** | 可观测系统是 ADI 前置，成立 |
| 0024 | Agent Diagnostic Interface | Accepted | **VALID** | ADI 成立，v0.1/v0.2 已合入。代码实证：`lib/core/replay/replay_engine.dart` + `lib/core/observability/adi_storage.dart` + `.adi/` 落盘（observations/sessions/traces） |
| 0025 | Issue Triage Agent 架构 | Proposed | **VALID** | 0011 扩展（stateful triage）Pending；LLM reasoner 不可靠 → 升级为状态驱动 |
| 0026 | Change Impact Analysis | （规划中） | **VALID（待立）** | ADI v0.3 拆出独立 ADR |
| 0028 | CLI adi validate before schema | Accepted | **VALID** | schema 收敛合理 |
| 0029 | ListElement 嵌套 AST | Proposed | **VALID** | 解决 BUG-5 round-trip 不保真，待 Owner 签字转正 |

### 2.2 三条最需要 Owner 拍板的 ADR 结论

1. **ADR-0004 / ADR-0008 / ADR-0012 同为 VALID-BUT-COSTLY，且相互耦合**
   三者共同指向"编辑器状态体系"这一最复杂子系统。建议合并为一次**架构复审（Architecture Review）**而非分散修，避免 Command Layer 被三种提交模型反复返工（这正是 ADR-0012 当初冻结要防止的）。**v1.2 定名：Architecture Review A-001 — Editor State & Transaction Model**（涵盖 DEBT-014 Live/Committed + DEBT-015 Transaction 内部张力，相关 IME coalescing / 空事务守卫一并纳入，非逐条打补丁）。

2. **ADR-0009 状态字段不一致**
   文档自述 Accepted，但 ADR-0011 称其仍为 Proposed。属治理卫生，不影响架构，但应在 `.agent/` 或 AGENTS.md 增加"ADR 状态字段必须与实际签字一致"的守门。

3. **ADR-0016 / 0018 / 0029 是 Proposed 但实现已合入 main**
   状态滞后于代码。建议 Owner 评审后统一转正为 Accepted，避免"已实现却仍标草案"造成的后续误读。

### 2.3 ADR 复审档期 & 重触发条件（v1.2 新增）

所有 ADR 统一记录复审元信息，避免"状态永久不变"导致的过期假设：

- **`last_reviewed`**：2026-08-19（本次 Phase 3.10 复盘统一核定）。
- **`next_review`**：事件驱动，满足任一即触发复审：
  1. 任何 PR 修改该 ADR 覆盖的子系统代码；
  2. 季度例行（每年 Q1）；
  3. 新需求与该 ADR 原则冲突或需豁免。
- **复审动作**：更新 `last_reviewed`、重判 4 态、必要时补守门测试或新 ADR。

**VALID-BUT-COSTLY 必须附重触发（re-trigger）条件**（防止"原则成立但实现已烂"被长期搁置）：

| ADR | 主题 | re-trigger 条件（满足即启动重构实现） |
|-----|------|--------------------------------------|
| 0004 | 手写 Markdown 解析器 | 新增产品需求超出当前 parser 能力边界，且 fuzz 失败率 > 阈值 |
| 0008 | Editor Transaction Model | 新增第 4 个与 Transaction 模型张力的子系统，或 IME coalescing 落地后仍有 undo 失真 |
| 0012 | Live/Committed 双状态 | 纳入 **Architecture Review A-001** 统一处理；re-trigger = A-001 退出判据未达（CORE-004/006 + Behavior 全绿 + IME coalescing） |

---

## 3. Part II — 工程债六类分类（A–F）

字段约定（每条债至少记录）：

```
ID / 名称 / Debt Type / debt_state / 首次引入阶段 / Commit·PR / 当时目的 / 当时为什么合理
/ 当前影响 / 用户影响 / 维护成本 / 是否已被测试覆盖 / 替代方案 / 最终决策
```

> **`debt_state` 字段（v1.2 新增，5 态）**：每条债必须显式标注当前状态，避免"分类"与"所处状态"混淆（这正是 DEBT-007 此前在 B 表判为 Accepted、又在 5.3 误列 P1 的根源）。
> - `accepted` —— 已接受债务，保留 + 偿还条件，本次不修；
> - `refactor` —— 需重构，进 roadmap，附触发/退出判据；
> - `verification-gap` —— 验证基础设施缺口（非产品债，如 DEBT-032）；
> - `resolved` —— 已消除/已修复/已完成（闭环）；
> - `obsolete` —— 废弃/编号占位（如 DEBT-036/037）。
> 注：`research-question`（如 DEBT-033 → RQ-001）**不是债**，不占 debt_state，单独列于 §8 研究问题区。

高信号条目给全字段；其余紧凑登记。

### A. Intentional Debt（主动买下的债，当时正确，现在到期）

当时为赶 Phase / 先跑通 / 先做 Demo / 降低实现复杂度 / 避免引入依赖 / 先验证架构。

| ID | 名称 | 引入 | 当时目的 / 为什么合理 | 当前判词 |
|----|------|------|---------------------|---------|
| DEBT-001 | 手写 Markdown Parser | Phase 1 (ADR-0004) | 快速跑通、避免引入生态库耦合 | **保留但增强**：fuzz 已锁边界；解析器转为需持续维护的设施 |
| DEBT-002 | 手写 Word OOXML 导出 | Phase 2–3 | 先完成导出闭环，不依赖外部 SDK | **债降级**：已从"半成品"转为"可控后端"；Export IR 隔离延后，不重写 |
| DEBT-003 | Seed 数据 / 演示路由 / InMemoryDocumentEditor | Phase 3.0 | 快速建立 UI 运行时基础 | **保留**：演示路径合理，真实数据已接 documentListProvider |
| DEBT-004 | Renderer 有意 fallback（TaskList/List/HorizontalRule/CodeBlock 降级） | Phase 3.2 | 先保证"不崩"，语义渲染后补 | **保留守卫**：ADR-0022 刻意设计，非缺陷 |

**全字段示例 — DEBT-001 手写 Markdown Parser**

```
ID:            DEBT-001
名称:          手写 Markdown Parser
Debt Type:     A. Intentional Debt
引入:          Phase 1 (ADR-0004, P0 #5)
Commit/PR:     da4ab00（补齐解析器）
当时目的:      快速跑通 MVP，避免 markdown 生态库（flutter_markdown 等）与自定义 AST 耦合
当时为什么合理: 项目核心是"AST 驱动编辑器"，通用库会把解析权夺走；自研可对齐 BlockElement
当前影响:      parser/serializer round-trip 仍存在边缘 case（BUG-1~6 已修并回归锁死）
用户影响:      正常文档无感；极端嵌套/特殊字符曾有数据丢失（已修复）
维护成本:      中（需 fuzz 持续守门，860+ 行 parser）
测试覆盖:      Parser/Serializer 一致性集成测试（TC-EDIT-8.4）+ ADL fuzz
替代方案:      迁移 markdown 生态库 → 与 ADR-0007 §1.3 冲突，成本高于收益
最终决策:      保留手写；补 fuzz 回归守门；不重写
偿还条件:      当某次产品需求（如 CommonMark 全量兼容）超出当前 parser 能力边界，且 fuzz 失败率>阈值时，重估
```

### B. Known Unresolved Bugs（文档已明确 TODO / Known Issue / Deferred / Phase 3+）

风险已知、修复成本通常可估、无设计争议 —— 应最优先清理。

| ID | 名称 | 来源标记 | 当前状态 | 决策 |
|----|------|---------|---------|------|
| DEBT-005 | Undo 空 Transaction 守卫（**原称 R2 断链，v1.1 核实命名不同**） | phase3.1-review-backlog R2 | 延期技术债 | **Refactor Needed**（进 roadmap，但空事务已以 no-op 守卫实现：transaction_builder.dart:168 `if (_ops.isEmpty) return`；editor_history.dart:146 `if (next.ops.isEmpty) return false`） |
| DEBT-006 | IME Transaction Coalescing 未实现 | phase3.3-pr3 §8.2（无 ADR） | 延期 Phase 3.4+ | **Refactor Needed**（2026-08-22 复检：仍存在——editor_command_pairing.dart:9「不实现 Coalescing：两个独立 undo 步骤（Phase 3.4 技术债）」；纳入 A-001 架构复审） |
| DEBT-007 | 选区/光标契约（**原称 3 项 TODO，v1.1 核实无 TODO 残留**） | BEHAVIOR-AUDIT-COVERAGE §4 | **v1.1 降级**：逻辑已实现为常规代码（block_enter_intent_formatter.dart:5,27,42），全仓无对应 TODO 标记 | **Debt Accepted** · `debt_state: accepted` + 子态 `verification-gap`（仅补 golden 覆盖，非重构；已从 5.3 Refactor Needed 移除，统一于此） |
| DEBT-008 | PDF 代码块中文注释乱码 | phase3.5-realdevice 问题6 | **v1.1 已修复**：pdf_exporter.dart:539 加 `cjkFont` fontFallback（"问题 6.4 修复"） | **已消除**（降级出 Refactor Needed） |
| DEBT-009 | UTF8 边界 bug 多轮未根治 | formula_render_plan.dart:114 / svg_to_pdf.dart:23 | 绕行非根治 | **Refactor Needed**（2026-08-22 复检：**部分缓解**——公式路径已切新路线 `parseSvgString → SvgPdfWidget` 绕开 pw.SvgImage utf8 bug（formula_render_plan.dart:113 旧路线注释「未启用」）；但 `sanitizeSvgString` 仍被 mermaid 路径实际调用（pdf_mermaid_renderer.dart:87），作为防御保留） |
| DEBT-010 | 两套颜色常量并存（**仅定义重复，值已同步**） | CRITICAL_REVIEW §6.3（示例过期） | **v1.1 降级**：冗余存在但 `error` 均为 `0xFFC1121F` | **Debt Accepted**（消冗余，非改值） |
| DEBT-011 | 代码块语法高亮不随主题切换 | phase3.5-realdevice 问题6/子1 | 开放 Phase 3.9+ TODO | **Debt Accepted** |
| DEBT-012 | 代码块 language chip 编辑态不显示 | phase3.5-realdevice 问题6/子5 | 开放 | **Refactor Needed**（小） |
| DEBT-013 | 底部栏底色不随主题（editor_bottom_bar.dart:26 TODO） | 源码标记 | 开放 | **Debt Accepted** |
| DEBT-019 | Provider 重复定义（历史） | AGENTS.md §3.2 | **已修复** Phase 1.1 | 历史登记，不再计 |

### C. Local Optimum / Architectural Debt（当时局部最优，现在全局代价）

不是"当时做错"，而是**随系统规模扩大，机会成本已超过最初收益**。最值得架构重构。

| ID | 名称 | 当时局部优化理由 | 现在的全局张力 | 决策 |
|----|------|----------------|----------------|------|
| DEBT-014 | **ADR-0012 Live/Committed 双状态分离** | 避免 TextField 高频 onChanged 直接污染 Transaction；输入性能 | Undo / Coalescing / Focus / Selection 全部与之张力 | ⭐ **Refactor Needed（架构复审）** |
| DEBT-015 | **ADR-0008 Transaction 模型内部张力** | 操作日志省内存、coalescing 避免 batch 污染 | IME coalescing 缺失 + 空 Transaction 断链 + 与 ADR-0007 §4.2 边界 | **Refactor Needed（与 DEBT-014 合并复审）** |
| DEBT-016 | PDF CJK 字体 static 状态污染 | 早期快速接入 pdf 导出 | static `_cjkFont` 跨测试污染，测试相互干扰 | **Refactor Needed**（2026-08-22 复检：**仍存在**——pdf_exporter.dart:29-32 仍为 `static _cjkFont / _cjkFontLoadAttempted / _cjkFontLoadFailedAt`；跨测试静态污染未消除。AGENTS.md §10 列为 Phase 2 修复项「静态状态污染测试」） |
| DEBT-017 | UTF8 导出健壮性（见 DEBT-009） | 逐轮打补丁绕过 XmlDocument.parse 边界 | 多轮修复未彻底，症状反复 | **Refactor Needed（Export IR）** |

**全字段示例 — DEBT-014 Live/Committed State（用户原文 DEBT-014）**

```
ID:            DEBT-014
名称:          Live / Committed State 分离（ADR-0012）
Debt Type:     C. Local Optimum / Architectural Debt
引入:          Phase 2（冻结于 2026-07-24，PR #65）
Commit/PR:     PR #65（随 Phase 3.3 E2E 收尾）
当时目的:      解决"实时字数 vs 失焦才提交"冲突；避免 Command Layer 被三种提交模型返工
当时为什么合理: 当时系统规模小，输入性能优先；双状态清晰隔离 live 与 committed
当前影响:      Undo / Coalescing / Focus / Selection 均与该分离产生张力（coordinator_state 持有 live source/cursor/composing）
用户影响:      真机曾出现"新块点不进编辑态 / 回车 IME 中断"（已修表层，但根因在状态桥）
维护成本:      高（EditorCoordinator + LiveEditingState + InteractionState 三者耦合）
测试覆盖:      E2E-CORE-004 Undo / EXT-005 IME（部分 skip 待真机）
替代方案:      统一为单一编辑态 + 显式 transaction bridge（需架构复审，非局部改）
最终决策:      Keep architecture, refactor transaction bridge
偿还条件(Trigger): EditorHistory + LiveState 维护成本 > 阈值 X，或新增第 4 个与之张力的子系统时
退出判据(Exit):   CORE-004 / CORE-006 + Behavior Audit 全绿，且 IME coalescing 落地
```

### D. Missing Completion（Phase 尚未完成，有 fallback）

不是 bug，是"产品边界尚未闭合"。

| ID | 名称 | 来源 | 状态 | 决策 |
|----|------|------|------|------|
| DEBT-018 | 首页 golden 缺失 + 搜索占位 SnackBar | UI_STATUS §4 #1 | 部分（golden 已补，搜索仍占位） | **Debt Accepted + P2 补 searchPill** |
| DEBT-020 | 3.4.10 选区格式化浮动菜单 | ROADMAP（移 Phase 4） | 未启动 | **Debt Accepted（排 Phase 4）** |
| DEBT-021 | 3.4.5/3.4.6 快捷键 / 打字机 | ROADMAP（移 Phase 4 Desktop） | 未启动 | **Debt Accepted（排 Phase 4）** |
| DEBT-022 | MathBlock 双态（原 3.2.1 延期） | ROADMAP | **已完成** 3.5.1 | 历史登记，不再计 |
| DEBT-023 | Block 交互三件套（原 3.2.7 延期） | ROADMAP | **已完成** 3.5.3-5 | 历史登记，不再计 |

### E. Environment-specific Debt（真机才暴露，模拟器/审查未发现）

很多不是 bug，而是**尚未完成的产品边界**，应单独管理。

| ID | 名称 | 发现方式 | 状态 | 决策 |
|----|------|---------|------|------|
| DEBT-024 | 新块无法进入编辑态（focusOn viewState 缺失） | 真机 Xiaomi | **已修复** P0 | 历史登记 |
| DEBT-025 | 回车分块 IME 中断 | 真机 | **已修复** P0 | 历史登记 |
| DEBT-026 | PDF 中文乱码（字体文件名） | 真机 Xiaomi | **已修复** P0-2 | 历史登记 |
| DEBT-027 | 导出公式依赖 WebView 未挂载 | 真机 + 审查 | 部分（字体修，WebView 就绪检查为建议项） | **Debt Accepted（建议项）** |
| DEBT-028 | 真机文件读写 / GBK 未验证 | CLI-ANYTHING §3.1 | 未验证 | **Debt Accepted（单独验收）** |
| DEBT-029 | MS Word Desktop 兼容性 | DOCX-QA §3 CAP-WORD-G | 未验证（诚实声明） | **Debt Accepted（单独验收）** |
| DEBT-030 | 真实软键盘 IME 按键未覆盖 | EXPERIENCE-AUDIT §4 | 未验证（需人工） | **Debt Accepted（单独验收）** |
| DEBT-031 | 本地 Dart/Flutter 工具链系统故障 | 实测 | 开放（基础设施） | **Refactor Needed（infra 治理）** |
| DEBT-032 | E2E-ADI-005 真机 replay 证据缺口（AS-RG.1） | 真机验收规划 | 开放 P1 堵缺口 | **Verification Gap（验证基础设施缺口，非产品债）**：采集合 commands.jsonl，补 E2E-ADI-005 证据闭环（v1.2 重分类，详见 §8） |
| DEBT-033 | Real LLM Agent 自主修复从未验证 | 代码审查 | 未验证（确定性 harness） | **Research Question RQ-001（研究问题，非债）**：方向验证，非缺陷；移出债表（v1.2 重分类，详见 §8） |

### F. Abandoned / Obsolete Design（已过期应删除或降级）

| ID | 名称 | 状态 | 决策 |
|----|------|------|------|
| DEBT-034 | `side_panel_host.dart` 占位死代码 | obsolete 占位（UI_STATUS R4） | **v1.1 已消除**：文件已不存在（全仓 Glob 无 `side_panel_host.dart`），债务结清 | **已消除**（无需动作） |
| DEBT-035 | `editor_screen.dart` legacy 单 TextField 编辑器 | 被 editor_shell 取代的 fallback | **Debt Accepted（保留 fallback，标注 deprecated）**（2026-08-22 复检：文件仍存在 479 行且**无任何 `@Deprecated`/legacy 标注**——标注动作尚未落地，待补） |
| DEBT-036 | `previewModeProvider` / 旧双模式 | 已移除 | 历史登记，不再计 |
| DEBT-037 | ADR-0010 SKIPPED 编号占位 | 非决策 | N/A（保留纪律占位） |

---

## 4. Part III — 债务决策矩阵（Debt Decision Matrix）

### 4.1 方法论：不要"债务清零"

优先级不是二元（修 / 不修），而是四维加权：

```
Priority = Impact(1-5) × Frequency(1-5) × UserVisibility(1-5) × FutureCost(1-5)
```

| 维度 | 含义 |
|------|------|
| Impact | 当前对正确性/稳定性的破坏程度 |
| Frequency | 触发概率（稳定复现 vs 偶发） |
| UserVisibility | 用户是否可感知（真机可见 > 仅测试可见） |
| FutureCost | 不处理，未来扩展的代价增速 |

**分桶**：≥200 = P0 立即修；100–199 = P1 排期；40–99 = P2 计划内；<40 = 保留/登记。

### 4.2 二维快判矩阵（实现成本 × 当前影响）

```
                    当前影响
                 低              高
实现成本  低     [保留]          [P0 修复]
         高     [记录]          [架构重构]
```

- DEBT-008（PDF 中文注释乱码）：成本低 × 影响中 → **P1 修复**
- DEBT-012（language chip）：成本低 × 影响低 → **保留/小修**
- DEBT-014/015（Live/Committed + Transaction）：成本高 × 影响高 → **架构重构**
- DEBT-010/011/013（颜色/高亮/底部栏主题）：成本低 × 影响低 → **保留**
- DEBT-031（工具链）：成本高 × 影响中 → **记录 + infra 治理**
- DEBT-034（side_panel_host 死代码）：成本低 × 影响低 → **删除（清理类）**

### 4.3 偿还条件模板（Repayment Condition）

每条进入 Refactor Needed 的债，必须带"触发条件"与"退出判据"，优于裸 `TODO: fix undo`：

```
DEBT-014 Live/Committed State
  Created:      Phase 2
  Reason:       避免 TextField 高频 onChanged 直接污染 Transaction
  Current Cost: Undo / Coalescing / Focus complexity
  Trigger:      EditorHistory + LiveState 维护成本 > X，或新增第 4 个张力子系统
  Decision:     Keep architecture, refactor transaction bridge
  Exit:         CORE-004/006 + Behavior Audit 全绿 + IME coalescing 落地
```

---

## 5. Part IV — Engineering Baseline v1（最终三分区）

### 5.1 Core Stable（核心稳定 — 不再随意改，加冻结守门）

这些经判定为**已验证、已测试、成立**。任何改动必须走新 ADR，且不得在无 Owner 授权下动。v1.2 起拆分为两类——关键是 **Test Stable ≠ Architecture Stable**：

- **Architecture Stable（架构稳定）**：结构/模型决策成立，不应被"美化性重构"动摇；改动须走 ADR。
- **Behavior Stable / Test Stable（行为稳定）**：运行时行为已被测试锁死（绿），但**底层架构可能正是要重构的对象**；重构时须保持行为基线不退化。

> ⚠️ **Test Stable ≠ Architecture Stable**：例如 `E2E-CORE-004 Undo` 行为已稳定（绿），但其底层建立在 ADR-0012 Live/Committed 架构之上——该架构正是 **Architecture Review A-001** 要复审的对象。重构允许改架构，但必须保住 E2E-CORE-004 等行为基线。反之 `ADR-0020 Block Model` 是 Architecture Stable（模型冻结），其行为同样稳定。

#### 5.1.1 Architecture Stable（架构稳定，9 项）

1. **ADR-0003** .md 单一真相源（Implemented）
2. **ADR-0007** BlockEditor 抽象（AST 稳定，Addendum 明确不重构）
3. **ADR-0020** Block Model 冻结（解决 ADR-0008 §9 冲突的锚点，Architecture Stable 范例）
4. **ADR-0022** Renderer Failure Policy（UnsupportedBlockFallback 刻意守卫）
5. **ADR-0024 / ADI** Agent 诊断接口（v0.1/v0.2 已合入）
6. **Phase 3.5 Formula Rendering 架构**（主线 + 主题 + Block 交互三件套）
7. **Phase 3.7 Observability 架构**（5 层 + Invariant + Replay 退出条件）
8. **Design System 对齐**（ADR-0015/0017，主色/字体/暖纸已落地）
9. **文件树 / TOC / 自动保存 / 主题架构**（Phase 3.4 主体）

#### 5.1.2 Behavior Stable（行为稳定 / Test Stable，3 项）

1. **BUG-1~6** Parser round-trip（已修复 + fuzz 回归锁死）
2. **E2E-CORE-001~006**（持久化 / 回车 / 合并 / Undo / Format / Coalescing 全绿；其中 E2E-CORE-004 Undo 为行为基线范例，重构须保住）
3. **真机 P0 修复**（DEBT-024/025/026 新块编辑 / IME 中断 / PDF 中文乱码）

> **冻结守门建议**：Architecture Stable 增 TC-ARCH-* 守门（禁止无 ADR 改动）；Behavior Stable 增/保留 TC/EXT 守门（禁止行为退化）。Core Stable 合计 **12 项（9 架构 + 3 行为）**。

### 5.2 Debt Accepted（已接受债务 — 保留 + 偿还条件，本次不修）

这些**当时合理、现在仍有保留价值**。登记理由，不修。

> **v1.1 代码验证注**：原 DEBT-010（颜色常量"值分歧"）经代码核对 **不成立**——`AppColors.error` 与 `AppTheme.errorColor` 均为 `0xFFC1121F`（app_constants.dart:34 / app_theme.dart:25），**冗余存在但值已同步**；原 DEBT-008（PDF 代码块中文乱码）**已修复**（pdf_exporter.dart:539 加 `cjkFont` fontFallback，注释"问题 6.4 修复"）。二者已从"开放待修"降级/消除。

| ID | 债务 | 接受理由（一句话） | 代码实证（v1.1） |
|----|------|------------------|------------------|
| DEBT-001 | 手写 Markdown Parser | 已锁边界，重写成本 > 收益 | `lib/core/parser/markdown_parser.dart`（~500 行，纯手写，无第三方解析库） |
| DEBT-002 | 手写 Word OOXML | 已从半成品转可控后端，债降级 | `lib/domain/services/exporters/word_ooxml_builder.dart`（571 行手写 XML 拼接，`:448` `<w:rFonts w:ascii="Courier New">`） |
| DEBT-003 | Seed/演示路由 | 演示路径合理，真实数据已接 | `lib/presentation/editor/in_memory_document_editor.dart` + `seed_documents.dart` 仍存续 |
| DEBT-004 | Renderer 有意 fallback | ADR-0022 刻意守卫 | `lib/presentation/blocks/fallback_block_renderer.dart:1` "落地 ADR-0022"；`:90` `captureError(type:'UnsupportedBlockFallback')` |
| DEBT-007 | 选区/光标契约（**v1.2 统一**） | `debt_state: accepted` + 子态 `verification-gap`；逻辑已实现（block_enter_intent_formatter.dart:5,27,42），无 TODO 残留；仅补 golden 覆盖，非重构 | 见 Part II B 表 `debt_state` 标注；已从 5.3 Refactor Needed 移除 |
| DEBT-010 | 两套颜色常量（**仅冗余，值已同步**） | 短期可接受，P3 语义化治理（消冗余而非改值） | 两处 `error` 均为 `0xFFC1121F`；primary/success/warning 亦一致 → **无值分歧，仅定义重复** |
| DEBT-011 | 代码块高亮不随主题 | Phase 4 前接受 | `lib/presentation/blocks/code/code_block.dart:15` "githubTheme（light）"；`:177` `isDark ? atomOneDarkTheme : githubTheme` |
| DEBT-013 | 底部栏主题 | 仅接阴影令牌，影响低 | `lib/presentation/widgets/editor_bottom_bar.dart:26` `// TODO(UI): 底色应随主题` |
| DEBT-018 | 首页 golden / 搜索占位 | 搜索非核心路径，P2 补 | 见 UI_STATUS §4 #1 |
| DEBT-020/021 | 选区菜单 / 快捷键 / 打字机 | 已明确移 Phase 4 | ROADMAP |
| DEBT-027 | 导出 WebView 就绪检查 | 建议项，非阻断 | 见 phase3.5-realdevice 问题4 |
| DEBT-028/029/030 | 真机 GBK / Word Desktop / 软键盘 IME | 产品边界未闭合，单独验收 | CLI-ANYTHING §3.1 |
| DEBT-035 | editor_screen legacy | 保留 fallback，标 deprecated | `lib/presentation/screens/editor_screen.dart:33` `_controller = TextEditingController()`；`:371` 仍作为活动编辑路径（不仅是 fallback，描述需修正）。**2026-08-22 复检：无 `@Deprecated` 标注，待补** |

### 5.3 Refactor Needed（需重构 — 进 roadmap，附触发与退出）

| 优先级 | ID | 债务 | 触发 / 退出 |
|--------|----|------|------------|
| **P0** | DEBT-014 + DEBT-015 → **Architecture Review A-001** | Editor State & Transaction 模型架构复审（合并 DEBT-014 Live/Committed + DEBT-015 Transaction 内部张力，非分散修） | 触发：维护成本超阈 / 新增张力子系统；退出：CORE-004/006 + Behavior 全绿 + IME coalescing。代码实证：`live_editing_state.dart:20` `_liveSources` Map 与 `InMemoryDocumentEditor` 分离；`transaction_builder.dart:63` `TransactionBuilder` + `editor_history.dart:144` `_defaultCanCoalesce`（7 规则）。**必须保住 Behavior Stable 基线（E2E-CORE-004 等）** |
| **VG·P0** | DEBT-032 | **Verification Gap（验证基础设施缺口，非产品债）**：真机 replay 证据缺口（commands.jsonl 采集） | 触发：已堵 v0.2；退出：E2E-ADI-005 reproduced + validate pass。见 §8 VERIFICATION GAP 列 |
| **P1** | DEBT-006 | IME Transaction Coalescing | 退出：相邻 ime origin 合并为单 undo 单元（v1.1 核实：coalescing 框架在，IME origin 合并规则待补） |
| **P2** | DEBT-005 | Undo 空 Transaction 守卫（**v1.1 更名**） | 退出：redo→undo 链不失真。实证：空事务以 no-op 守卫实现（transaction_builder.dart:168 / editor_history.dart:146），非 `_emptyCurrentState()` 构造器 |
| **P2** | DEBT-009/017 | UTF8 / 导出健壮性 → Export IR | 退出：根治 XmlDocument.parse 边界。实证：formula_render_plan.dart:114 / svg_to_pdf.dart:23 注释"utf8 边界 bug 多轮未彻底" |
| **P2** | DEBT-016 | PDF CJK static 状态污染 | 退出：instance + DI，测试互不污染。实证：pdf_exporter.dart:29 `static pw.Font? _cjkFont` |
| **P2** | DEBT-031 | 本地工具链系统故障 | 退出：本地可重跑全量测试 |
| **小修** | DEBT-012 | language chip 编辑态 | 退出：编辑态显示 chip |
| ~~DEBT-008~~ | ~~PDF 代码块中文乱码~~ | **v1.1 已消除**（pdf_exporter.dart:539 `cjkFont` fontFallback，"问题 6.4 修复"） | 移出 Refactor Needed |
| ~~DEBT-034~~ | ~~side_panel_host 死代码~~ | **v1.1 已消除**（文件已删） | 移出 Refactor Needed |

---

## 6. Part V — 给未来 Agent 的规则（治理建议）

> **RULE-FFX-001：没有历史决策，就不要擅自重构。**
>
> 当未来 Agent 看到一段"奇怪 / 不优雅 / 看似过度设计"的代码时，必须先回答：
> 1. 它属于本基线哪一类？（Core Stable [Architecture/Behavior] / Debt Accepted / Refactor Needed / Verification Gap / Research Q / 已过期）
> 2. 是否有对应 ADR 或 Debt ID 解释"当时为什么合理"？
> 3. 若属于 **Core Stable** 或 **Debt Accepted**：**禁止无 Owner 授权改动**，只能补充守门测试或注释。
> 4. 若属于 **Refactor Needed**：必须引用 Debt ID + 触发条件，且走 ADR 流程，不得"顺手重构"。
> 5. 若找不到任何历史决策：先在本文档或 ADR 库检索；仍无，则**默认保留并登记为 Unknown Debt**，而非立即重构。
>
> **P0 例外（v1.2 新增，可越权即修，但仍须登记）**：以下四类问题**不受"无历史决策不重构"约束**，Agent 可立即介入止血，但修复后须登记 Debt/Incident 并补守门测试：
> - **正确性 / 数据丢失**（如 round-trip 静默丢内容、导出文件损坏）；
> - **安全 / 隐私**（密钥泄露、未授权文件访问、PII 外传）；
> - **发布阻断**（CI 红、构建失败、阻塞 release 的确定性问题）；
> - **确定性崩溃**（稳定复现的 unhandled exception / assert，非偶发）。
> 例外仅授权"止血式修复"，**不授权借机做架构重构**——重构仍走 RULE-FFX-001 主流程 + ADR。

**落地建议**（需 Human Owner 决策，非 AI 自决）：
- 将 RULE-FFX-001 加入 `AGENTS.md` §6 禁区 或 `.agent/REPO_POLICY.md`；
- 新增"ADR 状态字段必须与实际签字一致"守门（治理卫生，针对 ADR-0009 不一致）；
- 本 `PHASE3.10-ENGINEERING-BASELINE-v1.md` 作为后续 Phase 的"债务真相源"，新 Debt 经 Owner 评审后追加，不重写历史。

---

## 7. 附录 — 证据索引

本复盘全部结论均来自以下已存在文档（只读，未改动）：

- **审计事实层**：`ADI-CLOSED-LOOP-AUDIT.md`、`ADL-LOOP-RUN-001..008`（含 PLAN）、`WORD-EXPORT-AUDIT.md`、`WORD-EXPORT-PRODUCT-RELIABILITY-AUDIT.md`、`MARKDOWN-ECOSYSTEM-HANDWRITTEN-REVIEW.md`、`BEHAVIOR-AUDIT-COVERAGE.md`、`EXPERIENCE-AUDIT-COVERAGE.md`、`PROJECT-FUNCTION-AUDIT-STATUS.md`、`CLI-ANYTHING-VERIFICATION-STATUS.md`
- **调查/治理**：`INVESTIGATIONS.md`、`git-governance-report.md`、`CRITICAL_REVIEW.md`、`COMPREHENSIVE-TEST-REPORT.md`、`phase3.1-review-backlog.md`、`TEST_SKIP_REGISTRY.md`
- **真机报告**：`releases/phase3.5-realdevice-issues.md`、`releases/adi-phase38-progress-realdevice-acceptance.md`、`releases/adi-e2e-005-realdevice-verification-report.md`
- **状态/路线**：`UI_STATUS.md`、`ROADMAP.md`
- **ADR 库**：`docs/ADR/0001..0029`（30 份，含 0010 SKIPPED、0025 + 0025-phase-1.1）
- **源码标记**：`flutter_app/lib` 内 TODO / Known Issue / 临时 / hack 标注（由 Explore 子代理扫描）
- **v1.1 代码实证**：`lib/presentation/editor/live_editing_state.dart`、`lib/core/editing/{transaction_builder,editor_history}.dart`、`lib/data/models/document.dart`、`lib/presentation/blocks/fallback_block_renderer.dart`、`lib/core/replay/`、`lib/core/parser/markdown_parser.dart`、`lib/domain/services/exporters/{word_ooxml_builder,pdf_exporter}.dart`、`lib/core/constants/app_constants.dart`、`lib/presentation/theme/app_theme.dart`、`integration_test/e2e/core/e2e_core_001..006_*.dart`、`test/parser/roundtrip_fuzz_test.dart`

### 复盘口径声明

- 本 Phase **不产生任何代码改动**，仅分类与建立基线。
- **v1.0 仅依据审计文档推导；v1.1 已对全部 LOAD-BEARING 结论在 `flutter_app/lib` 真实代码逐条核实（file:line 实证）**，并显式纠正了 4 处审计文档过时导致的错误结论（DEBT-010 / DEBT-008 / DEBT-034 / DEBT-007）。
- **三源真理模型（替代"代码即真理"）**：凡审计文档叙述与 Implementation Truth（`file:line` + `git log`）冲突，以实现真相为准；架构意图争议以 Decision Truth（Owner 签字 ADR）为准；"是否真的坏了"以 Evidence Truth（ADI/测试/真机）判定。三者冲突时在本文档显式标注。
- Refactor Needed 条目多数为**排期**而非**立即执行**；真正 P0 仅 **Architecture Review A-001（原 DEBT-014+015，Editor State & Transaction 架构复审）**。DEBT-032 为 Verification Gap（验证基础设施缺口，非产品债）、DEBT-033 为 Research Question RQ-001（研究问题，非债）。

### v1.1 代码验证结果摘要（Code Reality Check）

| # | 被核对结论 | 文档(审计)原判 | 代码实证结果 | 处置 |
|---|----------|--------------|------------|------|
| 1 | ADR-0012 Live/Committed 双状态 | VALID-BUT-COSTLY | **CONFIRMED** `live_editing_state.dart:20` `_liveSources` Map 独立于 `InMemoryDocumentEditor` | 维持，附代码实证 |
| 2 | ADR-0008 Transaction 模型 + coalescing | VALID-BUT-COSTLY | **CONFIRMED** `transaction_builder.dart:63` + `editor_history.dart:144` `_defaultCanCoalesce`（7 规则） | 维持 |
| 3 | ADR-0020 Block Model 冻结 | VALID | **CONFIRMED** `document.dart:1` `sealed class DocumentElement`；`:24` `ListElement.nested` | 维持 |
| 4 | ADR-0022 UnsupportedBlockFallback | VALID | **CONFIRMED** `fallback_block_renderer.dart:90` | 维持 |
| 5 | ADR-0024 ADI | VALID | **CONFIRMED** `lib/core/replay/` + `.adi/` 落盘 | 维持 |
| 6 | BUG-1~6 fuzz 回归锁死 | 已修复 | **CONFIRMED** `test/parser/roundtrip_fuzz_test.dart` + `markdown_parser.dart:224,265` | 维持 |
| 7 | E2E-CORE-001~006 | 全绿 | **CONFIRMED** `integration_test/e2e/core/e2e_core_001..006` | 维持 |
| 8 | **DEBT-010 两套颜色"值分歧"** | 开放待修 | **CONTRADICTED** 两处 `error` 均 `0xFFC1121F`（app_constants.dart:34 / app_theme.dart:25），仅冗余、值已同步 | **降级**：消冗余非改值 |
| 9 | **DEBT-008 PDF 代码块中文乱码** | 开放待修 | **CONTRADICTED** pdf_exporter.dart:539 已加 `cjkFont` fontFallback（"问题 6.4 修复"） | **消除** |
| 10 | **DEBT-034 side_panel_host 死代码** | 待删 | **NOT FOUND** 文件已不存在 | **消除** |
| 11 | **DEBT-007 选区光标 3 个 TODO** | 待实现 | **NOT FOUND** 无对应 TODO 残留，逻辑已实现（block_enter_intent_formatter.dart:5,27,42） | **降级** |
| 12 | DEBT-005 Undo 空 Transaction | R2 断链 | **CONTRADICTED(命名)** 无 `_emptyCurrentState`，空事务以 no-op 守卫实现（transaction_builder.dart:168 / editor_history.dart:146） | 维持但更名 |
| 13 | DEBT-001/002 手写 Parser / Word OOXML | 保留 | **CONFIRMED** `markdown_parser.dart`(~500 行) / `word_ooxml_builder.dart`(571 行) 均为手写 | 维持 |
| 14 | DEBT-016 PDF CJK static | 待重构 | **CONFIRMED** pdf_exporter.dart:29 `static _cjkFont` | 维持 |
| 15 | ADR-0009 状态不一致 | 治理卫生 | **CONFIRMED** 0009 自标 Accepted，0011 坚称 Proposed | 维持（doc-vs-doc） |
| 16 | ADR-0016/0018/0029 Proposed 但已合 | 状态滞后 | **CONFIRMED** 三者代码均已在位 | 维持 |

> **方法论教训（写回基线）**：本次 v1.0→v1.1 的修正证明——**复盘若只信审计文档、不复核代码，会把"已修复/已消除"的债误判为"开放待修"，把"冗余但已同步"误判为"值分歧"**。后续任何 Debt 条目的状态变更，必须以 `git log` + 代码 grep 为最终依据，审计文档仅作线索。

---

## 8. 单页真相表（Single-Page Truth Table）

> **用途**：供 `AGENTS.md` §6 禁区 或 `.agent/REPO_POLICY.md` 直接引用。任何 Agent 改动代码前先查此表；凡落入 Core Stable / Accepted / Refactor 的条目，须先对号入座再行动。
> **精确计数**：CORE 12 + ACCEPTED 16 + REFACTOR 8 + VERIFICATION GAP 1 + RESEARCH 1 = 38 开放项；另 Resolved 14 + Obsolete 2 + Governance 3 = 19 闭环项；**合计 45**（与 §1.1.1 对账一致）。

### 8.1 归属一览（两视角，均精确，互不重复计数）

**视角 A — 45 问题按状态分解（与 §1.1.1 完全一致）**

| 状态 | 数量 | 条目 |
|------|------|------|
| **Resolved**（已闭环） | 14 | DEBT-008·019·022·023·024·025·026·034 + BUG-1~6（6） |
| **Accepted**（已接受债务） | 16 | DEBT-001·002·003·004·007·010·011·013·018·020·021·027·028·029·030·035 |
| **Refactor**（需重构） | 8 | DEBT-005·006·009(=017)·012·014+015·016·031 |
| **Verification Gap**（验证缺口，非债） | 1 | DEBT-032 |
| **Research Q**（研究问题，非债） | 1 | DEBT-033 → RQ-001 |
| **Obsolete**（废弃/占位） | 2 | DEBT-036·037 |
| **Governance**（治理卫生，并入 ADR 复盘） | 3 | ADR-0009 / ADR-0016·0018·0029 |
| **合计** | **45** | |

**视角 B — 冻结守门精选集（Core Stable，12 锚点组）**

> 从 Resolved + Accepted 中抽出的"禁止无授权改动"集合，**按锚点组计（非逐问题）**，与视角 A 互为视图、不重复计数。拆分见 §5.1（Architecture Stable 9 / Behavior Stable 3）。

| 类型 | 数量 | 锚点 |
|------|------|------|
| **Architecture Stable** | 9 | ADR-0003/0007/0020/0022/0024 + Design System(0015/0017) + 文件树/TOC/自动保存/主题架构 + Phase3.5/3.7 架构 |
| **Behavior Stable** | 3 | BUG-1~6（fuzz 锁死）+ E2E-CORE-001~006 + 真机P0(024/025/026) |
| **合计** | **12** | |

### 8.2 禁止无 Owner 授权改动（Core Stable，12 项）

| # | 锚点 | 类型 |
|---|------|------|
| 1 | ADR-0003 .md 单一真相源 | Architecture Stable |
| 2 | ADR-0007 BlockEditor 抽象（AST 冻结） | Architecture Stable |
| 3 | ADR-0020 Block Model 冻结 | Architecture Stable |
| 4 | ADR-0022 Renderer Failure Policy | Architecture Stable |
| 5 | ADR-0024 / ADI 诊断接口 | Architecture Stable |
| 6 | Design System 对齐（0015/0017） | Architecture Stable |
| 7 | 文件树/TOC/自动保存/主题架构 | Architecture Stable |
| 8 | Phase 3.5 Formula 架构 + Phase 3.7 Observability 架构 | Architecture Stable |
| 9 | BUG-1~6 Parser round-trip（fuzz 锁死） | Behavior Stable |
| 10 | E2E-CORE-001~006（含 E2E-CORE-004 Undo 行为基线） | Behavior Stable |
| 11 | 真机 P0 修复（DEBT-024/025/026） | Behavior Stable |
| 12 | Phase 3.5/3.7 行为基线 | Behavior Stable |

> ⚠️ **Test Stable ≠ Architecture Stable**：#10/#11/#12 行为稳定（绿），但其底层架构（如 Live/Committed）可能进入 A-001 重构；**重构须保住行为基线**。

### 8.3 需重构（Refactor，走 ADR + 触发条件，8 项）

| 优先级 | ID | 主题 | 触发 / 退出 |
|--------|----|------|------------|
| **P0** | DEBT-014+015 | **Architecture Review A-001**：Editor State & Transaction 模型 | 退出：CORE-004/006 + Behavior 全绿 + IME coalescing（必须保住行为基线） |
| **P1** | DEBT-006 | IME Transaction Coalescing | 退出：相邻 ime origin 合并为单 undo 单元 |
| **P2** | DEBT-005 | Undo 空 Transaction 守卫（no-op 已实现） | 退出：redo→undo 链不失真 |
| **P2** | DEBT-009/017 | UTF8 / 导出健壮性 → Export IR | 退出：根治 XmlDocument.parse 边界 |
| **P2** | DEBT-016 | PDF CJK static 状态污染 | 退出：instance + DI |
| **P2** | DEBT-031 | 本地工具链系统故障 | 退出：本地可重跑全量测试 |
| **小修** | DEBT-012 | language chip 编辑态 | 退出：编辑态显示 chip |

### 8.4 验证缺口 & 研究问题（非产品债，2 项）

| 类型 | ID | 主题 | 处置 |
|------|----|------|------|
| **VERIFICATION GAP** | DEBT-032 | 真机 replay 证据缺口（commands.jsonl 采集 → E2E-ADI-005 闭环） | 补采集/守门，非功能重构 |
| **RESEARCH Q** | RQ-001（原 DEBT-033） | Real LLM Agent 自主修复可行性（确定性 harness 从未验证） | 立项研究，非缺陷修复 |

### 8.5 治理守门（RULE-FFX-001 摘要）

- **没有历史决策，就不要擅自重构。** 改动前先对号：Core Stable / Accepted → 禁无授权；Refactor → 引用 Debt ID + 触发条件 + ADR；无决策 → 默认保留并登记 Unknown Debt。
- **P0 例外**（可越权止血，仍须登记）：正确性/数据丢失、安全/隐私、发布阻断、确定性崩溃。例外不授权借机架构重构。
- **三源真理**：Implementation Truth（代码/git）> 审计叙述；Decision Truth（Owner 签字 ADR）> 重构冲动；Evidence Truth（ADI/测试/真机）判"是否真坏"。
- **ADR 复审**：`last_reviewed=2026-08-19`，`next_review` 事件驱动（改子系统代码 / 季度 / 需求冲突）；VALID-BUT-COSTLY 须附 re-trigger 条件（见 §2.3）。

---

*本文件为 FormulaFix Engineering Baseline v1。后续历史问题经 Human Owner 评审后，以追加条目方式更新，不覆盖历史决策。*
