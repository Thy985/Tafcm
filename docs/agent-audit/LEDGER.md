# Agent Ledger 投影（自动生成，请勿手改）

> 由 `ledger.py project` 从 `ledger.ndjson` 重生成；唯一真相是账本。
> 事件 32 条 / 假设 31 个。
> 生成时间不进正文：投影必须逐字节可复现，否则 CI 没法判"投影与账本一致"。

| hypothesis | dimension | tier | lifecycle | severity | verdict | issue | updated | identity |
|------------|-----------|------|-----------|----------|---------|-------|---------|----------|
| HYP-001 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-002 | correctness_test_gap | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-003 | architecture_data_flow | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-004 | infra_ci | L1 | candidate | low | - | - | 2026-10-03 | script_derived |
| HYP-005 | correctness_test_gap | L1 | retired | medium | - | - | 2026-10-03 | registry_declared |
| HYP-006 | correctness_test_gap | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-007 | architecture_data_flow | L1 | retired | medium | - | - | 2026-10-03 | registry_declared |
| HYP-008 | correctness_test_gap | L1 | retired | medium | - | - | 2026-10-03 | registry_declared |
| HYP-009 | correctness_test_gap | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-010 | correctness_test_gap | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-011 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-012 | architecture_data_flow | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-013 | correctness_test_gap | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-014 | architecture_data_flow | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-015 | correctness_test_gap | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-016 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-017 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-018 | architecture_data_flow | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-019 | architecture_data_flow | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-020 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-021 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-022 | architecture_data_flow | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-023 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-024 | architecture_data_flow | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-025 | correctness_test_gap | L1 | retired | medium | - | - | 2026-10-03 | registry_declared |
| HYP-026 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-027 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-028 | correctness_test_gap | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-029 | infra_ci | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-030 | correctness_test_gap | L1 | active | medium | - | - | 2026-10-03 | registry_declared |
| HYP-031 | architecture_data_flow | L1 | retired | medium | - | - | 2026-10-03 | registry_declared |

## 身份来源告警：8 个注册表标签挂在多个假设上

> 注册表的 `latest_id` 是人写的展示名，不是身份。同一标签对应多个
> fingerprint 说明注册表自己漂了：账本如实记下来，不替它合并——那
> 可能是两个真不同的 Finding 被起了同一个名字。
- `F-2026-09-05-01` → HYP-017、HYP-018
- `F-2026-09-05-02` → HYP-011、HYP-020
- `F-2026-09-07-01` → HYP-021、HYP-026
- `F-2026-09-10-01` → HYP-006、HYP-015
- `F-2026-09-10-02` → HYP-012、HYP-019
- `F-2026-09-12-01` → HYP-013、HYP-028
- `F-2026-09-16-01` → HYP-003、HYP-014
- `F-2026-10-01-01` → HYP-004、HYP-016
