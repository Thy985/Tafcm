# CURRENT-STATE —— Agent 当前状态入口

**定位（Current State Truth）**：Agent 进入项目后的第一站。
回答：**现在项目处于什么状态？当前在做什么？下一步做什么？**
不读任何 RUN/AUDIT 即可获得正确状态；追溯历史沿引用回原始证据。

**最近更新**: 2026-08-29（Phase 3.12 迁移提交 66ab54d 待 PR 合入；死链收尾轮）

---

## 1. 当前阶段

| 项 | 值 |
|----|-----|
| 阶段 | **Phase 3.12：信息架构重构**（进行中） |
| 前序 | Phase 0-3.11 全部完成；PHASE_3_11_EXIT 已判定关闭（2026-08-22） |
| 本阶段目标 | 文档四层重构（人类入口 / 工程真相 / 历史档案 / 机器资产）+ DOCUMENT CONSOLIDATION PASS |
| 下一步 | 死链收尾轮（已完成）→ `66ab54d` 建 PR 合入 main → 空档期立项决策（产品缺口 / DEBT-006） |

## 2. 工程五维状态（2026-08-22 冻结）

| 维度 | 状态 |
|------|------|
| Engineering Foundation | ✅ ~95% |
| Capability Coverage | ✅ COMPLETE（F1-F4） |
| Runtime Validation | ✅ FULLY VALIDATED |
| Real Defect Repair | ✅ VALIDATED（Formula/PDF/Undo） |
| E6/E8 Evidence | ✅ RELEASE-GATE SATISFIED（真机 4/4） |

## 3. 当前活动任务

- Phase 3.12 迁移提交 `66ab54d` 已在 `feat/phase3.12-info-architecture` 分支，待建 PR 合入 main（PR #166-#173 已全部合入）
- 迁移死链收尾：AGENTS.md / ROADMAP / ARCHITECTURE / ADR 互链 / engineering / releases / loading-rules 已修复（docs/ADR/ → docs/decisions/ADR/），archive / contracts 历史档案按冻结原则保留
- 待 Owner 决策：DEBT-006（IME Coalescing）是否单独立项；空档期产品缺口立项（HTML 导出 / 源码视图切换 / 表格单元格可视化编辑）

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

- 架构决策类文件（docs/decisions/ADR/、AGENTS.md、ROADMAP.md）AI 不 commit（除非明确授权）
- 不直接 push main；PR 流程
- 禁止删除测试 / 隐藏失败
- contracts/*.json 是 ffx 机器资产，路径不可移动
