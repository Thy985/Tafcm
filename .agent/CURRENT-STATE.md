# CURRENT-STATE —— Agent 当前状态入口

**定位（Current State Truth）**：Agent 进入项目后的第一站。
回答：**现在项目处于什么状态？当前在做什么？下一步做什么？**
不读任何 RUN/AUDIT 即可获得正确状态；追溯历史沿引用回原始证据。

**最近更新**: 2026-09-26（同步 #287：Phase 3 系列全部收尾、处于阶段间空档期、Phase 4 未启动）

---

## 1. 当前阶段

| 项 | 值 |
|----|-----|
| 阶段 | **阶段间空档期（Phase 3 系列全部收尾，Phase 4 未启动）** |
| 前序 | Phase 0-3.11 全部完成并合入 main（Phase 3.11 已由 Owner 判定关闭 2026-08-22） |
| 本阶段定位 | 无进行中的大阶段；产品侧已知缺口待 Owner 立项（HTML 导出 / 源码视图切换 / 表格单元格可视化编辑 / 3.4.10 选区格式化菜单）见 [TYPORA-GAP-ANALYSIS](../docs/product/TYPORA-GAP-ANALYSIS.md) §3-4 |
| 下一步 | 由 Human Owner 决定空档期立项；架构决策一律先落 ADR，不启动新大阶段功能 |

## 2. 工程五维状态（2026-08-22 冻结）

| 维度 | 状态 |
|------|------|
| Engineering Foundation | ✅ ~95% |
| Capability Coverage | ✅ COMPLETE（F1-F4） |
| Runtime Validation | ✅ FULLY VALIDATED |
| Real Defect Repair | ✅ VALIDATED（Formula/PDF/Undo） |
| E6/E8 Evidence | ✅ RELEASE-GATE SATISFIED（真机 4/4） |

## 3. 当前活动任务

- **空档期无进行中的大阶段功能**（AGENTS.md §0 空档期禁区：不启动新大阶段功能、不跨阶段实现；架构决策一律先落 ADR）
- 活跃的维护性工作（Ingoing，非新阶段立项）：
  - P0 批次：#238（kAppVersion 版本漂移）、#287（本文档）、#288（audit 单日缺失）修复
  - 已开放 Agent Issues：#289（FINDINGS.md 去重脚本 bug）/ #234 / #246-#250 等，待 Owner 决策优先级
- 待 Owner 决策：DEBT-006（IME Coalescing）是否单独立项；空档期产品缺口立项（HTML 导出 / 源码视图切换 / 表格单元格可视化编辑 / 3.4.10 选区格式化菜单）

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
