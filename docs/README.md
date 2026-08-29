# Tafcm 文档门户（docs/ README）

**定位（L1 人类入口）**：按**阅读目的**导航全部文档，并体现三层知识模型（Principles / Assets / History）与 L0-L5 层级。
新读者路径：`README.md`（产品）→ `CONTRIBUTING.md`（协作）→ **[ENGINEERING.md](ENGINEERING.md)**（工程地图）→ 本页（按需导航）。
机器可核对的全量清单见 [INDEX.md](INDEX.md)。

---

## 我第一次了解这个项目

| 目的 | 入口 |
|------|------|
| 产品是什么 | [product/PRODUCT.md](product/PRODUCT.md)（五维定位 / 核心能力 / 设计理念） |
| 工程地图（唯一入口） | **[ENGINEERING.md](ENGINEERING.md)**（Principles → Architecture → Guides → Decisions） |
| 当前系统长什么样 | [architecture/ARCHITECTURE.md](architecture/ARCHITECTURE.md)（模块 + 数据流 + 边界） |
| 功能做到什么程度 | [product/CAPABILITY-STATUS.md](product/CAPABILITY-STATUS.md)（能力完成度） |
| 产品体验原则 | [product/UX-GUIDE.md](product/UX-GUIDE.md) |
| 下一步做什么 | [ROADMAP.md](ROADMAP.md)（Phase 0-4 路线图） |

## 我准备修改代码

| 目的 | 入口 |
|------|------|
| 工程原则（为什么） | [principles/engineering-principles.md](principles/engineering-principles.md) + [principles/architecture-principles.md](principles/architecture-principles.md) |
| 开发指南（怎么做） | [guides/development.md](guides/development.md)（环境 / 流程 / 规范速查 / 常见坑） |
| 测试指南 | [guides/testing.md](guides/testing.md) + [principles/testing-principles.md](principles/testing-principles.md) |
| 调试指南 | [guides/debugging.md](guides/debugging.md)（ADI 工作流 + 排查手册） |
| 协作规范（必读） | [AGENTS.md](../AGENTS.md)（架构原则 / 编码规范 / 禁止事项 / CI 手册） |
| Agent 协作原则 | [principles/agent-collaboration.md](principles/agent-collaboration.md)（权限 / Memory Distillation） |
| 工程基线 + 已知债务 | [engineering/ENGINEERING-BASELINE.md](engineering/ENGINEERING-BASELINE.md)（DEBT 表） |
| 开发规则 / 流程 | [engineering/DEVELOPMENT-RULES.md](engineering/DEVELOPMENT-RULES.md) · [engineering/WORKFLOW.md](engineering/WORKFLOW.md) |
| Git 流程 | [engineering/GIT-WORKFLOW.md](engineering/GIT-WORKFLOW.md) |
| 编辑模型 / 导出架构 | [architecture/EDITOR-MODEL.md](architecture/EDITOR-MODEL.md) · [architecture/EXPORT-MODEL.md](architecture/EXPORT-MODEL.md) |

## 我需要理解一个架构决策

| 目的 | 入口 |
|------|------|
| 决策状态总表（含归档规则） | [decisions/INDEX.md](decisions/INDEX.md)（30 篇 ADR 状态：Accepted / Superseded / Proposed） |
| 具体决策全文 | [decisions/ADR/](decisions/ADR/)（0001-0031） |

## 我需要验证一个功能

| 目的 | 入口 |
|------|------|
| 能力契约（机器可读） | [contracts/*.json](../contracts/)（ffx 消费） |
| 回归资产（可核对 case 包） | [regression/](regression/)（BUG-001~003 等） |
| 证据资产（截图 + 判定） | [evidence/](evidence/)（capability / visual / consumer） |
| 验证纪律 | [engineering/VERIFICATION-POLICY.md](engineering/VERIFICATION-POLICY.md) |
| Agent 工程架构 | [architecture/AGENT-ENGINEERING.md](architecture/AGENT-ENGINEERING.md)（ADI / FFX / 验证闭环） |

## 我想调查历史问题（L4 History）

| 目的 | 入口 |
|------|------|
| RUN 报告（35 篇） | [archive/runs/](archive/runs/)（phase3.11 / adl / dogfood） |
| 审计报告 | [archive/audits/](archive/audits/)（CRITICAL-REVIEW / 能力再审计 / 专项审计） |
| Spike / 调研 | [archive/spikes/](archive/spikes/)（parser / word / officecli / markdown 生态） |
| 旧设计 | [archive/old-designs/](archive/old-designs/)（UI_STATUS / UI_FIX_PLAN） |
| 已归档历史 | [archive/](archive/)（governance / runs / audits / spikes / investigations / old-designs） |
| 任务契约（历史） | [contracts/](contracts/)（phase2.x / phase3.x task-contract） |
| 验证报告（历史） | [releases/](releases/)（各 Phase Verification Report） |
| 设计文档 | [design/](design/)（adi-design / ui-spec） |

## 三层知识模型与目录地图

```
docs/
├── README.md              ← 本门户（按阅读目的导航）
├── INDEX.md               ← 全量索引（机器可核对）
├── ENGINEERING.md         ★ 工程手册（唯一入口：L0-L5 地图）
├── ROADMAP.md             ← 路线图
│
├── principles/            ★ Principles 层（为什么——稳定，不随 session 变）
│   ├── engineering-principles.md
│   ├── architecture-principles.md
│   ├── testing-principles.md
│   └── agent-collaboration.md
├── guides/                ★ Guides 层（怎么做——开发 / 测试 / 调试）
│   ├── development.md  testing.md  debugging.md
│
├── architecture/          Assets 层（系统怎么工作）
├── decisions/             Assets 层（为什么做这些选择：INDEX + ADR/ 30 篇）
├── design/  product/      Assets 层（产品定义与设计）
├── engineering/           Assets 层（工程记录，原则已提炼至 principles/ 后逐步降级）
│
├── contracts/  regression/  evidence/   L3 证据层
├── releases/              L3 历史验证报告
└── archive/               L4 历史档案（runs / audits / spikes / investigations / old-designs / governance）
```

## 知识层级（L0-L5）

| 层级 | 含义 | 位置 |
|------|------|------|
| **L0 — Public Product** | 用户关心的"发生了什么" | README / CHANGELOG |
| **L1 — Engineering Contract** | 协作与工程契约 | CONTRIBUTING / principles / AGENTS |
| **L2 — System Knowledge** | 系统如何工作 | architecture / guides / ADR / design / product |
| **L3 — Evidence** | 怎么证明正确 | golden / tests / regression / releases / evidence |
| **L4 — History** | 发生过什么 | archive / obsolete records |
| **Lx — Runtime** | Agent 运行时状态（不入库） | .agent/state / .adi / .ffx / .atomcode |

## 文档生命周期

所有 `docs/` 文档 frontmatter 声明 `status: active | draft | deprecated | superseded | archived`。
判断标准（准入四问）：现在还成立吗？新贡献者需要吗？指导未来工程行为吗？能脱离具体 Agent Session 理解吗？四问皆否 → 不进入 docs/。

## 三种真相

| Truth | 载体 | 回答 |
|-------|------|------|
| Decision Truth | `decisions/` | 为什么这么做？ |
| Evidence Truth | `contracts/` `regression/` `evidence/` `.adi/` | 实际发生了什么？ |
| Current State Truth | `.agent/CURRENT-STATE.md` + `product/CAPABILITY-STATUS.md` + `engineering/ENGINEERING-BASELINE.md` | 现在是什么状态？ |

RUN / AUDIT / SPIKE 一律是**历史证据**（可追溯，不污染 Current State）。
