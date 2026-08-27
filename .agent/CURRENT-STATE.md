# CURRENT-STATE —— Agent 当前状态入口

**定位（Current State Truth）**：Agent 进入项目后的第一站。
回答：**现在项目处于什么状态？当前在做什么？下一步做什么？**
不读任何 RUN/AUDIT 即可获得正确状态；追溯历史沿引用回原始证据。

**最近更新**: 2026-08-27（Phase 3.12 信息架构重构进行中）

---

## 1. 当前阶段

| 项 | 值 |
|----|-----|
| 阶段 | **Phase 3.12：信息架构重构**（进行中） |
| 前序 | Phase 0-3.11 全部完成；PHASE_3_11_EXIT 已判定关闭（2026-08-22） |
| 本阶段目标 | 文档四层重构（人类入口 / 工程真相 / 历史档案 / 机器资产）+ DOCUMENT CONSOLIDATION PASS |
| 下一步 | 迁移收尾（链接修复 → 验证 → PR #166 后新一轮） |

## 2. 工程五维状态（2026-08-22 冻结）

| 维度 | 状态 |
|------|------|
| Engineering Foundation | ✅ ~95% |
| Capability Coverage | ✅ COMPLETE（F1-F4） |
| Runtime Validation | ✅ FULLY VALIDATED |
| Real Defect Repair | ✅ VALIDATED（Formula/PDF/Undo） |
| E6/E8 Evidence | ✅ RELEASE-GATE SATISFIED（真机 4/4） |

## 3. 当前活动任务

- Phase 3.12 文档迁移（本仓库工作区进行中，未提交）
- 待 Owner 决策：PR #164/165/166 合并状态；DEBT-006（IME Coalescing）是否单独立项

## 4. 快速入口

| 需求 | 入口 |
|------|------|
| 人类导航 | [docs/README.md](../docs/README.md) |
| 能力状态 | [docs/product/CAPABILITY-STATUS.md](../docs/product/CAPABILITY-STATUS.md) |
| 工程债务 | [docs/engineering/ENGINEERING-BASELINE.md](../docs/engineering/ENGINEERING-BASELINE.md) |
| 决策索引 | [docs/decisions/INDEX.md](../docs/decisions/INDEX.md) |
| 机器资产 | [contracts/](../contracts/)（11 json，ffx 消费） |
| 验证纪律 | [docs/engineering/VERIFICATION-POLICY.md](../docs/engineering/VERIFICATION-POLICY.md) |

## 5. 铁律（不许违反）

- 架构决策类文件（docs/ADR/、AGENTS.md、ROADMAP.md）AI 不 commit（除非明确授权）
- 不直接 push main；PR 流程
- 禁止删除测试 / 隐藏失败
- contracts/*.json 是 ffx 机器资产，路径不可移动
