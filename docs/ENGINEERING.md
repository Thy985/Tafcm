# Tafcm Engineering Handbook（工程手册）

> 唯一工程入口——从这一页进入整个知识体系。
> 新贡献者路径：`README.md`（产品）→ `CONTRIBUTING.md`（协作）→ 本页（工程地图）。
> 知识层级：**L0 产品 / L1 工程契约 / L2 系统知识 / L3 证据 / L4 历史 / Lx 运行时**。

---

## 1. Engineering Principles（工程原则）

为什么这样设计——稳定条款，不随开发轮次变化。

- [Engineering Principles](principles/engineering-principles.md) —— 总原则 + 文档准入四问
- [Architecture Principles](principles/architecture-principles.md) —— 分层 / 存储 / 编辑器 / 状态 / 渲染
- [Testing Principles](principles/testing-principles.md) —— 门禁 / 证据等级 / 回归纪律
- [Agent Collaboration](principles/agent-collaboration.md) —— Agent 如何参与 + Memory Distillation

## 2. Architecture（系统怎么工作）

- [ARCHITECTURE.md](architecture/ARCHITECTURE.md) —— 系统总览（当前 + 目标 + 问题）
- [AGENT-ENGINEERING.md](architecture/AGENT-ENGINEERING.md) —— Agent 工程闭环（ADI → FFX → contracts → regression）
- [UI-ARCHITECTURE.md](architecture/UI-ARCHITECTURE.md) —— UI 心智模型 / 状态模型 / 组件结构
- [UI-COMPONENT-MODEL.md](architecture/UI-COMPONENT-MODEL.md) —— 组件树
- [UI-INTERACTION-MODEL.md](architecture/UI-INTERACTION-MODEL.md) —— 交互模型
- [CONTRACT-SYNC-MINIMAL.md](architecture/CONTRACT-SYNC-MINIMAL.md) —— 契约同步

## 3. Development（怎么开发）

- [Development Guide](guides/development.md) —— 环境 / 工作流 / 规范速查
- [Testing Guide](guides/testing.md) —— 怎么跑验证 / 怎么写测试
- [Debugging Guide](guides/debugging.md) —— 怎么排查问题（ADI 诊断）

## 4. Testing & Verification（怎么证明正确）

- [Testing Principles](principles/testing-principles.md) —— 门禁与证据等级
- [VERIFICATION-POLICY.md](engineering/VERIFICATION-POLICY.md) —— 验证纪律单一真相
- [ENGINEERING-BASELINE.md](engineering/ENGINEERING-BASELINE.md) —— 工程基线 + DEBT 债务表
- [GATE-REPORT.md](engineering/GATE-REPORT.md) —— Final Gate 报告

## 5. Decision Records（为什么做这些选择）

- [ADR 索引](decisions/INDEX.md) —— 全量状态表
- [ADR 目录](decisions/ADR/) —— 30 篇决策记录（0001~0031）

## 6. Product & Design（当前产品定义）

- [PRODUCT.md](product/PRODUCT.md) —— 产品设计总纲（五维定位）
- [UX-GUIDE.md](product/UX-GUIDE.md) —— UI 规范（Typora 化）
- [TYPORA-GAP-ANALYSIS.md](product/TYPORA-GAP-ANALYSIS.md) —— 产品缺口分析
- [CAPABILITY-STATUS.md](product/CAPABILITY-STATUS.md) —— 能力状态

## 7. Historical Records（过去发生过什么）

- [docs/archive/](archive/) —— 归档：审计 / run 报告 / spike / 旧设计 / 治理记录
- [docs/releases/](releases/) —— 各阶段发布验证报告
- [docs/regression/](regression/) —— 回归 case 包（BUG-001~003）
- [docs/evidence/](evidence/) —— 证据索引

## 8. AI / Agent Collaboration（Agent 如何参与工程）

- [Agent Collaboration](principles/agent-collaboration.md) —— 权限 / 协议 / Memory Distillation
- [AGENTS.md](../AGENTS.md) —— AI 协作强制规范（六层架构 / 禁止事项 / CI 手册）
- [.agent/](../.agent/REPO_POLICY.md) —— 仓库治理层（安全 / git / 命令规则）

---

## 知识层级（L0-L5）

| 层级 | 含义 | 位置 |
|------|------|------|
| **L0 — Public Product** | 用户关心的"这是什么" | README / CHANGELOG |
| **L1 — Engineering Contract** | 协作与工程契约 | CONTRIBUTING / principles / AGENTS |
| **L2 — System Knowledge** | 系统如何工作 | architecture / guides / ADR / design / product |
| **L3 — Evidence** | 怎么证明正确 | golden / tests / regression / releases / evidence |
| **L4 — History** | 发生过什么 | archive / obsolete records |
| **Lx — Runtime** | Agent 运行时状态（不入库） | .agent/state / .adi / .ffx / .atomcode |

**维护约定**：本页只做导航，不承载规范正文；新增文档必须挂到本页对应小节。
