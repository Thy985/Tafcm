# FormulaFix 文档迁移映射表（MIGRATION-MAP）

**日期**: 2026-08-27
**配套**: [INFO-ARCHITECTURE-DESIGN.md](INFO-ARCHITECTURE-DESIGN.md)（目标结构 + 四层原则 + 三种真相）
**原则**: 先提取，再归档，最后精简。**不删除**任何含工程事实的历史文档。
**动作类型**: `保留原位` / `移动`（纯 git mv）/ `重命名`（内容微调）/ `提取`（报告→资产）/ `合并`（多文档→一）/ `删除重复`（内容相同的副本）/ `新增`

---

## 0. 迁移顺序（十步）

1. 建新目录 + canonical 骨架 → 2. 本映射表冻结 → 3. 提取 assets（contracts/regression/golden/evidence）
→ 4. 整理 ADR（decisions/）→ 5. 整理 product/architecture/engineering → 6. RUN/Audit/Spike 移入 archive
→ 7. 重写 README/docs README → 8. 引用检查 + dead link 检查 → 9. FFX/Agent 指向 canonical → 10. Human Review

---

## 1. 根目录（保持 / 微调）

| 文件 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `README.md` | **重写** | 保留原位 | 人类首页：产品是什么/核心能力/当前状态/架构图/快速开始/文档入口/验证入口（100-200 行） |
| `AGENTS.md` | 微调 | 保留原位 | 只保留协作规则/边界/纪律；新增指向 `.agent/CURRENT-STATE.md` |
| `.agent/` | 新增 | `.agent/CURRENT-STATE.md` | Agent 当前状态入口（Current State Truth） |
| `contracts/*.json`（11 个） | **保留原位** | — | ffx `contract_sync.py` 硬编码 `root/contracts/*.json`，不可移动 |
| `design-system/` | 保留 | — | tokens 单一真相源 |
| `flutter_app/` | 保留 | — | lib/test/integration_test/golden 均不动 |
| `tests/verification_cases/` | 保留 | — | 回归案例 corpus 已存在 |
| `tools/ skills/ formulafix-redesign.design/` | 保留 | — | — |

---

## 2. docs/ 顶层 → 目标（62 个文件全映射）

### 2.1 门户（保留）

| 文件 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `README.md` | **重写** | 保留原位 | 按阅读目的导航（5 类读者入口） |
| `INDEX.md` | 更新 | 保留原位 | 全量索引，迁移后同步路径 |

### 2.2 → `docs/product/`（产品真相）

| 文件 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `DESIGN.md` | 提取 | `product/PRODUCT.md` | 产品是什么（设计理念 + 视觉原型引用） |
| `UI_SPEC.md` | 重命名 | `product/UX-GUIDE.md` | 产品体验/设计原则（UI_SPEC v2.0 收敛） |
| `FEATURE-CAPABILITY-COVERAGE-MATRIX-v1.md` | 合并 | `product/CAPABILITY-STATUS.md` | 能力完成度（人类视图） |
| `FEATURE-COMPLETION-EVIDENCE-MATRIX-v1.md` | 合并 | `product/CAPABILITY-STATUS.md` | 完成证据（人类视图） |
| `PHASE3.10-TYPORA-GAP-ANALYSIS.md` | 移动 | `product/TYPORA-GAP-ANALYSIS.md` | 产品差距分析 |

### 2.3 → `docs/architecture/`（架构真相）

| 文件 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `ARCHITECTURE.md` | **瘦身重写** | `architecture/ARCHITECTURE.md` | 只讲"现在是什么"，不再混目标/问题/风险 |
| （ARCHITECTURE 编辑段） | 提取 | `architecture/EDITOR-MODEL.md` | 编辑模型（Parser→AST→Live/Committed→Transaction→History） |
| （ARCHITECTURE 导出段） | 提取 | `architecture/EXPORT-MODEL.md` | 导出架构（SVG/PNG/Word/PDF 管线） |
| `Component-Tree.md` | 重命名 | `architecture/UI-COMPONENT-MODEL.md` | UI 组件模型 |
| `Interaction-Model.md` | 移动 | `architecture/UI-INTERACTION-MODEL.md` | 交互模型 |
| `UI-ARCHITECTURE.md` | 移动 | `architecture/UI-ARCHITECTURE.md` | UI 架构 |
| `FFX-VERIFICATION-ORCHESTRATOR-v1.md` | 移动 | `architecture/AGENT-ENGINEERING.md` | ADI/FFX/验证闭环架构 |
| `CONTRACT-SYNC-MINIMAL.md` | 移动 | `architecture/AGENT-ENGINEERING.md` | 并入 Agent Engineering |

### 2.4 → `docs/engineering/`（工程真相）

| 文件 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `PHASE3.10-ENGINEERING-BASELINE-v1.md` | 重命名 | `engineering/ENGINEERING-BASELINE.md` | 工程基线 + DEBT 表（去 v1 版本后缀） |
| `PHASE3.10-GATE-REPORT.md` | 移动 | `engineering/VERIFICATION-POLICY.md` | 验证纪律（Gate 报告并入） |
| `CODING_RULES.md` | 重命名 | `engineering/DEVELOPMENT-RULES.md` | 开发规则 |
| `GIT_WORKFLOW.md` | 重命名 | `engineering/GIT-WORKFLOW.md` | Git 流程 |
| `WORKFLOW.md` | 移动 | `engineering/WORKFLOW.md` | 开发流程 |
| `E2E_TEST_PLAN.md` | 合并 | `engineering/VERIFICATION-POLICY.md` | 验证纪律（测试计划并入） |
| `TEST_GAP_PLAN.md` | 合并 | `engineering/VERIFICATION-POLICY.md` | 验证纪律（缺口并入） |
| `TEST_SKIP_REGISTRY.md` | 合并 | `engineering/VERIFICATION-POLICY.md` | 验证纪律（skip 登记并入） |
| `DOCX-QA-PIPELINE.md` | 移动 | `engineering/QA-PIPELINES.md` | QA 管线（DOCX） |
| `CLI-ANYTHING-VERIFICATION-STATUS.md` | 移动 | `engineering/CLI-VERIFICATION-STATUS.md` | CLI 验证状态 |
| `PROJECT-FUNCTION-AUDIT-STATUS.md` | 移动 | `engineering/FUNCTION-AUDIT-STATUS.md` | 功能审计状态 |

### 2.5 → `docs/decisions/`（决策真相）

| 文件 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `docs/ADR/`（29 篇） | 移动 | `decisions/ADR/` | 纯 git mv，内容不动 |
| （ADR 索引段，现散落 README） | 提取 | `decisions/INDEX.md` | 状态表：有效/需复审/已废弃 |
| `phase3.1-review-backlog.md` | 移动 | `decisions/REVIEW-BACKLOG.md` | 评审 backlog（决策待办） |

### 2.6 → `docs/contracts/`（保留原位，人类版任务契约）

| 文件 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `contracts/phase*.md`（16 篇） | **保留原位** | — | 任务契约是历史记录，不动 |
| `BRANCH_AUDIT_2026-08-25.md` | 移动 | `archive/governance/` | 治理基线（历史） |
| `PR-2_DESCRIPTION.md` / `PR-3_DESCRIPTION.md` / `PR-5_DESCRIPTION.md` | 移动 | `archive/governance/` | PR 说明（历史） |

### 2.7 → `docs/regression/`（L4 回归资产，★ 提取）

| 源（RUN 报告内） | 动作 | 目标 | 备注 |
|------|------|------|------|
| `runs/adl/ADL-LOOP-RUN-008.md` BUG-1（硬换行丢失） | 提取 | `regression/markdown/BUG-001-hard-break/`（case.json + input.md + expected.json + README.md） | 可执行资产 |
| `runs/adl/ADL-LOOP-RUN-008.md` BUG-2（`\|` 行吞掉） | 提取 | `regression/markdown/BUG-002-pipe-line/` | 同上 |
| `runs/adl/ADL-LOOP-RUN-008.md` BUG-3（列表顺序） | 提取 | `regression/markdown/BUG-003-list-order/` | 同上 |
| `runs/adl/ADL-LOOP-RUN-008.md` BUG-5（嵌套列表） | 提取 | `regression/markdown/BUG-005-nested-list/` | 同上 |
| `runs/adl/ADL-LOOP-RUN-008.md` BUG-6（空 mermaid 块） | 提取 | `regression/markdown/BUG-006-empty-mermaid/` | 同上 |
| `runs/phase3.11/RUN-002/003`（markdown/serializer 缺陷） | 提取 | `regression/serializer/BUG-00X-*/` | 同上 |
| 现有 `tests/verification_cases/` | 保留 | — | 已是 corpus，regression/ 只放人类可读 case 包 |

### 2.8 → `docs/evidence/`（L4 证据资产，★ 提取）

| 源 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `runs/phase3.11/RUN-012~016` E6/E8 截图 + 判定 | 提取 | `evidence/visual/formula/`（screenshot + meta.json + verdict） | 视觉证据可追溯 |
| `vlm_corpus/` + `vlm_corpus_physical/`（若存在） | 移动 | `evidence/visual/formula/` | E8 语料 |
| `runs/phase3.11/RUN-007/011` Word/PDF 验证 | 提取 | `evidence/consumer/` | 消费端证据 |
| E6 模拟器/真机截图产物 | 移动 | `evidence/capability/formula/` | 能力证据 |

### 2.9 → `docs/archive/`（L3 历史档案）

| 文件 | 动作 | 目标 | 备注 |
|------|------|------|------|
| `runs/`（35 篇：phase3.11/adl/dogfood） | 移动 | `archive/runs/` | RUN 报告降级为历史 |
| `CRITICAL_REVIEW.md` | 移动 | `archive/audits/CRITICAL-REVIEW.md` | 历史严厉批判（已大部分落实） |
| `COMPREHENSIVE-TEST-REPORT.md` | 移动 | `archive/audits/` | 测试报告（历史） |
| `FULL-CAPABILITY-REAUDIT.md` | 移动 | `archive/audits/` | 能力再审计（历史） |
| `BEHAVIOR-AUDIT-COVERAGE.md` | 移动 | `archive/audits/` | 审计覆盖（历史） |
| `EXPERIENCE-AUDIT-COVERAGE.md` | 移动 | `archive/audits/` | 审计覆盖（历史） |
| `WORD-EXPORT-AUDIT.md` | 移动 | `archive/audits/` | 专项审计（历史） |
| `WORD-EXPORT-PRODUCT-RELIABILITY-AUDIT.md` | 移动 | `archive/audits/` | 专项审计（历史） |
| `ADI-CLOSED-LOOP-AUDIT.md` | 移动 | `archive/audits/` | ADI 闭环审计（历史） |
| `MIGRATION-SPIKE-MARKDOWN-PARSER.md` | 移动 | `archive/spikes/` | spike（历史） |
| `WORD-MIGRATION-SPIKE.md` | 移动 | `archive/spikes/` | spike（历史） |
| `OFFICECLI-RESEARCH.md` | 移动 | `archive/spikes/` | 调研（历史） |
| `MARKDOWN-ECOSYSTEM-HANDWRITTEN-REVIEW.md` | 移动 | `archive/spikes/` | 调研（历史） |
| `INVESTIGATIONS.md` | 移动 | `archive/investigations/` | 调查（历史） |
| `UI_STATUS.md` | 移动 | `archive/old-designs/` | UI 状态（历史快照） |
| `UI_FIX_PLAN.md` | 移动 | `archive/old-designs/` | UI 修复计划（历史快照） |
| `ROADMAP.md` | **保留原位**（docs/ 顶层） | — | 路线图是 Current State 一部分，文档门户直接链接 |
| 顶层重复 `PHASE3.11-RUN-*.md`（16 个） | **删除重复** | — | 与 `docs/runs/phase3.11/` 内容相同（PR #164 顶层副本 + PR #166 runs 副本并存） |
| `docs/archive/` 既有（3 篇） | 保留 | — | 2026-08-12 snapshot / PHASE1_TEST_PLAN / REFACTOR_DESIGN 已归档 |

---

## 3. 迁移后 docs/ 顶层仅剩

```
docs/
├── README.md          # 文档门户（按阅读目的导航）
├── INDEX.md           # 全量索引
├── ROADMAP.md         # 路线图（Current State 入口）
└── INFO-ARCHITECTURE-DESIGN.md  # 本设计（迁移完成后可移 archive/ 或删除）
```

其余全部落入 product/ architecture/ engineering/ decisions/ contracts/ regression/ evidence/ archive/。

---

## 4. 一致性检查清单（迁移后必做）

- [ ] 全部引用更新（README/AGENTS/ffx-cli/INDEX 指向新路径）
- [ ] dead link 扫描 = 0（不含预期占位）
- [ ] `root/contracts/*.json` 路径未被移动（ffx 依赖）
- [ ] 顶层 RUN 重复副本已删除
- [ ] git mv 保留历史（不 copy+delete）
- [ ] 每个 archive 文件可从 CAPABILITY-STATUS/INDEX 追溯
