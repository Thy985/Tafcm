# Knowledge Candidates（待升维候选）

> 这些内容"可能"具有更高抽象价值，但当前证据尚不足以支撑升维。
> 规则：不能证明的东西，不应该假装成知识。以下候选均标注缺口与验证路径。

---

## Candidate C-001 · 复杂状态系统"三面分离"原则

- **Hypothesis**: 复杂状态系统中，持久状态（document state）、变更过程（transaction）、历史记录（history/undo）不应共享同一职责边界——三者分离可显著降低状态耦合。
- **Why Interesting**: 若成立，是可迁移到所有富编辑器/状态机的 L4 原则。
- **Current Evidence**: 仅 Tafcm 单一项目（ADR-0008/0012 + E2E 失败触发），S5。
- **Missing Evidence**: 缺少第二个项目的独立验证；未量化"耦合 vs 分离"的收益。
- **Possible Future Validation**: 在 FormulaFix/另一编辑器重构中复用该三面分离，记录耦合度/缺陷率对比。
- **Potential Destination**: General Engineering Principle

---

## Candidate C-002 · "证据强度链 + 禁止跨等级推断"作为发布门禁普遍模型

- **Hypothesis**: 任何发布/质量体系都应显式定义证据强度枚举（synthetic < test < production < virtual < physical < visual < human），并禁止"低等级证据推断高等级结论"（如模拟器通过≠真机通过）。
- **Why Interesting**: Tafcm 的 Evidence Strength 模型是评审过程中被"语义偷换"问题逼出来的，具有普适性。
- **Current Evidence**: Tafcm 完整落地（RUN-007/013 + contracts evidence_strength + FULL-CAPABILITY-REAUDIT），S4。
- **Missing Evidence**: 尚未在非 Flutter/非验证编排语境验证；未形成可复用的"证据等级声明"标准格式。
- **Possible Future Validation**: 在其他项目的 release gate / CI 门禁设计中套用该枚举并记录误判下降。
- **Potential Destination**: Engineering Methodology

---

## Candidate C-003 · 视觉保真"三层分解"（Integrity → Structural → Pixel）可迁移性

- **Hypothesis**: 视觉/主观质量验证应先做"结构层"（可解析的中间表示、结构断言），再谈像素/感知层——结构层比像素稳健、比人工可重复，是自动化视觉验证的甜点。
- **Why Interesting**: 直接回答"如何验证看似只能人工判断的能力"，跨领域价值极高。
- **Current Evidence**: E8 Pipeline 三层 + Structural Fidelity 用 LaTeX AST→期望结构→截图结构断言（RUN-013），S5（模拟器）；VLM structure mode 仅探路（RUN-016）。
- **Missing Evidence**: 只验证了公式渲染单一场景；未验证设计系统/布局/颜色等更广视觉域；VLM 评估器未成 release gate。
- **Possible Future Validation**: 应用到 design-system 视觉回归 / 多场景 golden，验证结构层在不同视觉域的有效性。
- **Potential Destination**: General Verification Methodology

---

## Candidate C-004 · Untrusted Analyzer 三段式的推广边界

- **Hypothesis**: 任何"不可信输入 + AI 分析 + 系统副作用"的自动化（公开 PR、外部爬虫、用户生成内容）都应采用 提取(确定性)→分析(AI 只读)→执行(确定性+白名单) 三段式，AI 段零写权限。
- **Why Interesting**: 直接解决 AI 自动化的注入放大问题。
- **Current Evidence**: issue-triage（ADR-0025）完整实施 + fixture 测试，S4；但只覆盖 GitHub Issue 一类副作用。
- **Missing Evidence**: 未在其他副作用类型（发邮件、改配置、写 DB）验证；未量化注入攻击的成功率下降。
- **Possible Future Validation**: 在另一个"外部输入→AI→副作用"系统（如客服工单、内容审核）复用三段式。
- **Potential Destination**: Agent Engineering Pattern（很可能成为原则，但需多实例）

---

## Candidate C-005 · "Agent 记忆蒸馏"（Memory Distillation）作为知识库治理模式

- **Hypothesis**: Agent 系统应显式定义记忆蒸馏管道：无效→删除、有独立历史价值→归档、可复用→提炼进原则库、"只是想过"→不保存；运行时状态永不入库。
- **Why Interesting**: 解决 AI 协作项目的知识库污染问题，直接关系知识资产可信度。
- **Current Evidence**: Tafcm 长期执行（agent-collaboration §6 + frontmatter 生命周期），S5（本仓）。
- **Missing Evidence**: 这是"团队规范"而非"工程机制"——未工具化（无自动分类/淘汰工具）。
- **Possible Future Validation**: 实现"文档准入四问"的自动化预检，或扩展到个人知识库验证其普适性。
- **Potential Destination**: Knowledge Management / Agent Governance

---

## Candidate C-006 · "FFX 验证编排"与"测试框架"的边界

- **Hypothesis**: Agent 可用的验证层应是"编排器 + 能力适配器注册表"，能力无关；实现领域能力的验证应通过 Adapter 接入，避免变成第二个测试框架。
- **Why Interesting**: 回答"给 Agent 的验证工具如何设计才不腐化"。
- **Current Evidence**: FFX 5 边界 + 7 不变量（ADR-0030），markdown 闭环 P0 验证 + PDF real defect（S5），Word 仅部分。
- **Missing Evidence**: 仅 2 个 Consumer 能力实证；Adapter 注册表在更多能力下的扩展性未验证。
- **Possible Future Validation**: 接入第 3 个能力（真机 device family）观察 orchestrator 核心是否保持零改动。
- **Potential Destination**: Agent Tooling Design

---

## Candidate C-007 · 契约系统自身的元验证（contract 漂移检测）

- **Hypothesis**: 契约驱动系统需要一个"元验证"层——契约与实现、契约与派生投影的漂移必须可检测（如 contract-sync + schema 校验），否则机器验证本身会误报/漏报。
- **Why Interesting**: FULL-CAPABILITY-REAUDIT 真实出现过 unknown_max 未同步导致误报 fail。
- **Current Evidence**: contract-sync + verify 已落地（S4），但误报场景仅记录一次，未形成通用"元验证"方法论。
- **Missing Evidence**: 未系统化"契约漂移的失败模式分类"；未定义契约变更的审批路径。
- **Possible Future Validation**: 在另一契约驱动项目中观察并分类漂移失败模式。
- **Potential Destination**: Contract-Driven Development

---

## Candidate C-008 · 错误成本不对称的自动化阈值设计（三态置信度）

- **Hypothesis**: AI 自动化的决策阈值应由"两类错误的相对成本"决定（漏建成本低、误建污染大 → 高阈值 + 中间建议态），而非单一准确率阈值。
- **Why Interesting**: 直接指导所有 AI 自动化（工单、告警、修改）的策略设计。
- **Current Evidence**: issue-triage 置信度三态 + dry-run 校准（ADR-0025），S4；但阈值（0.8/0.5）未经真实数据校准验证（dry-run 后是否调整未知）。
- **Missing Evidence**: 缺少误建率/漏建率的实际观测数据；未在不同领域验证成本不对称假设。
- **Possible Future Validation**: 记录 issue-triage 上线后的 precision/recall，验证三态阈值有效性。
- **Potential Destination**: Agent Automation Strategy

---

## Candidate C-009 · 阶段门禁（Final Gate）作为"完成"的工程定义

- **Hypothesis**: 复杂长周期项目应以"阶段门禁通过"定义"阶段完成"（可验证事件），而非"功能看起来做完了"；空档期禁止启动未立项大功能。
- **Why Interesting**: 治理长周期 AI 协作项目的完成标准。
- **Current Evidence**: Phase 3.10 Final Gate G0-G12 全通过 + Phase 3.11 关闭判定（S5 本仓）。
- **Missing Evidence**: 门禁项的选择标准未形式化（为什么是 G0-G12 而非别的）；未验证在其他项目可复制。
- **Possible Future Validation**: 沉淀"门禁检查项模板"并用于下一阶段/其他项目。
- **Potential Destination**: Project Governance

---

## 汇总

| 候选 | 主题 | 当前证据 | 主要缺口 | 潜在去向 |
|------|------|---------|---------|---------|
| C-001 | 状态三面分离原则 | S5 单项目 | 需第二项目验证 | General Principle |
| C-002 | 证据强度链门禁模型 | S4 | 需跨领域验证 | Engineering Methodology |
| C-003 | 视觉验证三层分解 | S5 单场景 | 需扩展视觉域 | Verification Methodology |
| C-004 | Untrusted Analyzer 三段式 | S4 单副作用 | 需多副作用验证 | Agent Pattern→Principle |
| C-005 | Agent 记忆蒸馏 | S5 规范级 | 未工具化 | Knowledge Management |
| C-006 | FFX 编排器边界 | S4-S5 部分 | 需更多能力实证 | Agent Tooling |
| C-007 | 契约元验证 | S4 单次误报 | 未系统化 | Contract-Driven Dev |
| C-008 | 错误成本不对称阈值 | S4 未校准 | 缺真实数据 | Agent Automation |
| C-009 | 阶段门禁治理 | S5 单项目 | 未形式化 | Project Governance |

---
*Generated by Knowledge Archaeology · 只读*
