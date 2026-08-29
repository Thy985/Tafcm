# Tafcm 文档门户（docs/ README）

**定位（L1 人类入口）**：按**阅读目的**导航全部文档。不罗列文件名——回答"你现在想做什么"。
新读者从这里进入；机器可核对的全量清单见 [INDEX.md](INDEX.md)。

---

## 我第一次了解这个项目

| 目的 | 入口 |
|------|------|
| 产品是什么 | [product/PRODUCT.md](product/PRODUCT.md)（定位 / 核心能力 / 设计理念） |
| 当前系统长什么样 | [architecture/ARCHITECTURE.md](architecture/ARCHITECTURE.md)（模块 + 数据流 + 边界） |
| 功能做到什么程度 | [product/CAPABILITY-STATUS.md](product/CAPABILITY-STATUS.md)（能力完成度） |
| 产品体验原则 | [product/UX-GUIDE.md](product/UX-GUIDE.md) |
| 下一步做什么 | [ROADMAP.md](ROADMAP.md)（Phase 0-4 路线图） |

## 我准备修改代码

| 目的 | 入口 |
|------|------|
| 协作规范（必读） | [AGENTS.md](../AGENTS.md)（架构原则 / 编码规范 / 禁止事项 / CI 手册） |
| 工程基线 + 已知债务 | [engineering/ENGINEERING-BASELINE.md](engineering/ENGINEERING-BASELINE.md)（DEBT 表） |
| 开发规则 | [engineering/DEVELOPMENT-RULES.md](engineering/DEVELOPMENT-RULES.md) |
| Git 流程 | [engineering/GIT-WORKFLOW.md](engineering/GIT-WORKFLOW.md) |
| 开发流程 | [engineering/WORKFLOW.md](engineering/WORKFLOW.md) |
| 编辑模型细节 | [architecture/EDITOR-MODEL.md](architecture/EDITOR-MODEL.md) |
| 导出架构细节 | [architecture/EXPORT-MODEL.md](architecture/EXPORT-MODEL.md) |

## 我需要理解一个架构决策

| 目的 | 入口 |
|------|------|
| 决策状态总表 | [decisions/INDEX.md](decisions/INDEX.md)（29 篇 ADR 状态：有效 / 需复审 / 已废弃） |
| 具体决策全文 | [decisions/ADR/](decisions/ADR/)（0001-0030） |

## 我需要验证一个功能

| 目的 | 入口 |
|------|------|
| 能力契约（机器可读） | [contracts/*.json](../contracts/)（ffx 消费） |
| 回归资产（可核对 case 包） | [regression/](regression/)（BUG-001~003 等） |
| 证据资产（截图 + 判定） | [evidence/](evidence/)（capability / visual / consumer） |
| 验证纪律 | [engineering/VERIFICATION-POLICY.md](engineering/VERIFICATION-POLICY.md)（规划中：由 GATE-REPORT / e2e / gap / skip 合并） |
| Agent 工程架构 | [architecture/AGENT-ENGINEERING.md](architecture/AGENT-ENGINEERING.md)（ADI / FFX / 验证闭环） |

## 我想调查历史问题

| 目的 | 入口 |
|------|------|
| RUN 报告（35 篇） | [archive/runs/](archive/runs/)（phase3.11 / adl / dogfood） |
| 审计报告 | [archive/audits/](archive/audits/)（CRITICAL-REVIEW / 能力再审计 / 专项审计） |
| Spike / 调研 | [archive/spikes/](archive/spikes/)（parser / word / officecli / markdown 生态） |
| 调查记录 | [archive/investigations/](archive/investigations/) |
| 旧设计 | [archive/old-designs/](archive/old-designs/)（UI_STATUS / UI_FIX_PLAN） |
| 已归档历史 | [archive/](archive/)（governance / runs / audits / spikes / investigations / old-designs） |
| 任务契约（历史） | [contracts/](contracts/)（phase2.x / phase3.x task-contract） |
| 验证报告（历史） | [releases/](releases/)（各 Phase Verification Report） |
| 设计文档 | [design/](design/)（adi-design / ui-spec） |

## 目录地图

```
docs/
├── README.md              ← 本门户（按阅读目的导航）
├── INDEX.md               ← 全量索引（机器可核对）
├── ROADMAP.md             ← 路线图
├── product/               L2 产品真相（PRODUCT / CAPABILITY-STATUS / UX-GUIDE）
├── architecture/          L2 架构真相（ARCHITECTURE / EDITOR-MODEL / EXPORT-MODEL / AGENT-ENGINEERING / UI-*）
├── engineering/           L2 工程真相（ENGINEERING-BASELINE / VERIFICATION-POLICY / DEVELOPMENT-RULES / GIT-WORKFLOW）
├── decisions/             L2 决策真相（INDEX + ADR/ 29 篇）
├── contracts/             L4 人类版任务契约（phase*.md）
├── regression/            L4 回归资产（BUG case 包）
├── evidence/              L4 证据资产（capability / visual / consumer）
├── releases/              L3 历史验证报告
├── design/                L2 设计文档
└── archive/               L3 历史档案（runs / audits / spikes / investigations / old-designs / governance）
```

## 三种真相

| Truth | 载体 | 回答 |
|-------|------|------|
| Decision Truth | `decisions/` | 为什么这么做？ |
| Evidence Truth | `contracts/` `regression/` `evidence/` `.adi/` | 实际发生了什么？ |
| Current State Truth | `.agent/CURRENT-STATE.md` + `product/CAPABILITY-STATUS.md` + `engineering/ENGINEERING-BASELINE.md` | 现在是什么状态？ |

RUN / AUDIT / SPIKE 一律是**历史证据**（可追溯，不污染 Current State）。
