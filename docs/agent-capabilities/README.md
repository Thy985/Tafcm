# Tafcm Agent Capability Registry

> **定位**：对 Tafcm Agent 协作架构中两类执行环境（Cline/GitHub Actions、Doubao/Cloud Computer）的**真实能力边界**进行证据化登记。**不是观点，是证据。**
> **原则**：实际执行成功才记 `proven`；失败记 `failed_under_conditions`；未测记 `unknown`；被权限/环境/工具/策略阻断记 `blocked_by_*`。禁止能力膨胀（一次成功只能证明该细粒度能力）。
> **更新**：每轮实验后增量更新（`experiments/` 留证据），不重新生成整套。
> **关联**：Cline 观察层 `.agent/tafcm-maintainer/` · Doubao 监督层 `docs/agent-supervision/` · 产品侧 ADI 工具 `tools/adi/`（本表为 Agent 自身能力，非产品诊断接口）。

## 状态图例
| status | 含义 |
|---|---|
| `proven` | 实际执行成功，有 Evidence |
| `failed_under_conditions` | 在特定条件下失败（不代表绝对不能做） |
| `unknown` | 未测试 / 无足够证据 |
| `partial` | 部分成功或部分维度达成 |
| `blocked_by_permission/environment/tooling/policy` | 被明确阻断 |
| `conditional` | 仅在特定条件下可达成 |

## Evidence 强度
`synthetic` < `test_runtime` < `production_runtime` < `virtual_device` < `physical_device` < `visual` < `human_confirmed`

## 文件
- `cline.yaml` — Cline / GitHub Actions Agent
- `doubao.yaml` — Doubao / Cloud Computer Agent
- `cross-agent.yaml` — 跨 Agent 交接矩阵
- `experiments/` — 实验证据记录

## 维护规则
1. 能力必须绑定 `evidence:`（实验 ID / run ID / Issue / PR / 本地路径）
2. Unknown 是合法结果，禁止猜测补全
3. 边界结论必须标注边界类型（capability/tool/permission/runtime/environment/policy/prompt/auth）
