# Tafcm 文档全量索引（INDEX）

**生成日期**: 2026-08-22（文档整理轮）
**用途**: docs/ 下全部文档的单页索引——顶层 + 子目录 + RUN 报告分类表。
**入口**: 新读者从 [README.md](README.md) 进入（分类导航）；本页为全量清单（机器可核对）。

---

## 1. 顶层文档（40 篇）

### 1.1 架构与路线图

| 文档 | 说明 |
|------|------|
| [ARCHITECTURE.md](architecture/ARCHITECTURE.md) | 架构总览（当前 + 目标 + 问题 + 风险） |
| [ROADMAP.md](ROADMAP.md) | 路线图（Phase 0-4，含 Phase 3.10/3.11） |
| [DESIGN.md](product/PRODUCT.md) | 总体设计 |
| [CRITICAL_REVIEW.md](archive/audits/CRITICAL-REVIEW.md) | 现状严厉批判报告 |
| [COMPREHENSIVE-TEST-REPORT.md](archive/audits/COMPREHENSIVE-TEST-REPORT.md) | 综合测试报告 |
| [FFX-VERIFICATION-ORCHESTRATOR-v1.md](architecture/AGENT-ENGINEERING.md) | FFX 验证编排器设计 |
| [CONTRACT-SYNC-MINIMAL.md](architecture/CONTRACT-SYNC-MINIMAL.md) | Contract Sync 最小版 |

### 1.2 UI 设计与交互

| 文档 | 说明 |
|------|------|
| [UI-ARCHITECTURE.md](architecture/UI-ARCHITECTURE.md) | UI 架构 |
| [UI_SPEC.md](product/UX-GUIDE.md) | 产品视觉设计 source of truth |
| [Component-Tree.md](architecture/UI-COMPONENT-MODEL.md) | 组件树 |
| [Interaction-Model.md](architecture/UI-INTERACTION-MODEL.md) | 交互模型 |
| [UI_STATUS.md](archive/old-designs/UI_STATUS.md) | UI 还原度状态 |
| [UI_FIX_PLAN.md](archive/old-designs/UI_FIX_PLAN.md) | UI 修复实施计划 |

### 1.3 开发流程与规范

| 文档 | 说明 |
|------|------|
| [WORKFLOW.md](engineering/WORKFLOW.md) | 开发流程与 CI/CD |
| [GIT_WORKFLOW.md](engineering/GIT-WORKFLOW.md) | Git 详细流程 |
| [CODING_RULES.md](engineering/DEVELOPMENT-RULES.md) | 详细编码规范 |
| [TEST_SKIP_REGISTRY.md](engineering/VERIFICATION-POLICY-source-skip.md) | 测试 skip 登记 |
| [TEST_GAP_PLAN.md](engineering/VERIFICATION-POLICY-source-gap.md) | 测试缺口计划 |
| [E2E_TEST_PLAN.md](engineering/VERIFICATION-POLICY-source-e2e.md) | E2E 测试计划 |

### 1.4 Phase 3.10/3.11 审计与验证

| 文档 | 说明 |
|------|------|
| [PHASE3.10-ENGINEERING-BASELINE-v1.md](engineering/ENGINEERING-BASELINE.md) | 3.10 工程基线（DEBT 债务表） |
| [PHASE3.10-GATE-REPORT.md](engineering/GATE-REPORT.md) | 3.10 Final Gate 报告（G0-G12） |
| [PHASE3.10-TYPORA-GAP-ANALYSIS.md](product/TYPORA-GAP-ANALYSIS.md) | Typora 差距分析 |
| [FEATURE-CAPABILITY-COVERAGE-MATRIX-v1.md](product/CAPABILITY-STATUS-source-coverage.md) | 能力覆盖矩阵 |
| [FEATURE-COMPLETION-EVIDENCE-MATRIX-v1.md](product/CAPABILITY-STATUS-source-completion.md) | 完成证据矩阵 |
| [FULL-CAPABILITY-REAUDIT.md](archive/audits/FULL-CAPABILITY-REAUDIT.md) | 能力全量再审计 |
| [BEHAVIOR-AUDIT-COVERAGE.md](archive/audits/BEHAVIOR-AUDIT-COVERAGE.md) | Behavior 审计覆盖 |
| [EXPERIENCE-AUDIT-COVERAGE.md](archive/audits/EXPERIENCE-AUDIT-COVERAGE.md) | 体验审计覆盖 |
| [PROJECT-FUNCTION-AUDIT-STATUS.md](engineering/FUNCTION-AUDIT-STATUS.md) | 功能审计状态 |
| [ADI-CLOSED-LOOP-AUDIT.md](archive/audits/ADI-CLOSED-LOOP-AUDIT.md) | ADI 闭环审计 |
| [CLI-ANYTHING-VERIFICATION-STATUS.md](engineering/CLI-VERIFICATION-STATUS.md) | CLI 验证状态 |

### 1.5 专项审计 / 调研 / 迁移

| 文档 | 说明 |
|------|------|
| [MARKDOWN-ECOSYSTEM-HANDWRITTEN-REVIEW.md](archive/spikes/MARKDOWN-ECOSYSTEM-HANDWRITTEN-REVIEW.md) | Markdown 生态手写评审 |
| [MIGRATION-SPIKE-MARKDOWN-PARSER.md](archive/spikes/MIGRATION-SPIKE-MARKDOWN-PARSER.md) | Parser 迁移 spike |
| [WORD-MIGRATION-SPIKE.md](archive/spikes/WORD-MIGRATION-SPIKE.md) | Word 迁移 spike |
| [WORD-EXPORT-AUDIT.md](archive/audits/WORD-EXPORT-AUDIT.md) | Word 导出审计 |
| [WORD-EXPORT-PRODUCT-RELIABILITY-AUDIT.md](archive/audits/WORD-EXPORT-PRODUCT-RELIABILITY-AUDIT.md) | Word 导出可靠性审计 |
| [DOCX-QA-PIPELINE.md](engineering/QA-PIPELINES.md) | DOCX QA 管线 |
| [OFFICECLI-RESEARCH.md](archive/spikes/OFFICECLI-RESEARCH.md) | OfficeCLI 调研 |
| [phase3.1-review-backlog.md](decisions/REVIEW-BACKLOG.md) | 3.1 评审待办 backlog |

## 2. 子目录

### 2.1 ADR（架构决策记录，30 篇）

见 [ADR/](ADR/) —— 按编号递增（0001 ~ 0031）。状态机 `Proposed → Accepted → Superseded/Deprecated`。
关键：ADR-0003（存储单一真相源）/ 0024（ADI）/ 0028（CLI before schema）/ 0029（嵌套 AST）/ 0030（Verification Orchestrator）/ 0031（品牌改名 Tafcm，取代 ADR-0001 §1）。

### 2.2 contracts（任务契约，16 篇）

见 [contracts/](contracts/) —— phase2.1 ~ phase3.4 各阶段 Task Contract（含 PR 关联 / 验收清单）。

### 2.3 design（设计文档，2 篇）

见 [design/](design/) —— [adi-design-v1.md](design/adi-design-v1.md)（ADI 设计）/ [ui-spec.md](design/ui-spec.md)（UI 规范）。

### 2.4 releases（验证报告，11 篇）

见 [releases/](releases/) —— phase1/2/3 各阶段 Verification Report + 真机验收报告。

### 2.5 archive（已归档，2 篇）

见 [archive/](archive/) —— 已过期/被取代的历史文档：
| 文档 | 说明 |
|------|------|
| [REFACTOR_DESIGN.md](archive/REFACTOR_DESIGN.md) | 重构方案设计（被 ADR + Phase 3.10 Baseline 取代，2026-08-22 归档） |
| [PHASE1_TEST_PLAN.md](archive/PHASE1_TEST_PLAN.md) | Phase 1 测试计划（Phase 1 已完结，2026-08-22 归档） |

### 2.6 evidence（证据索引）

见 [evidence/](evidence/) —— 能力 / 视觉 / 消费证据索引（人类可追溯判定）。

### 2.7 assets（设计资产）

见 [assets/](assets/) —— `ui-prototype/` 设计稿资产。

## 3. RUN 报告（35 篇，按类型归档）

### 3.1 Phase 3.11 Capability Hardening Loop（16 篇）—— [runs/phase3.11/](runs/phase3.11/)

| 文档 | 说明 |
|------|------|
| [RUN-001](archive/runs/phase3.11/PHASE3.11-RUN-001-RUNNER-IZATION.md) | 独立 runner 化（7 能力真实执行） |
| [RUN-002](archive/runs/phase3.11/PHASE3.11-RUN-002-MARKDOWN-HARDENING.md) | Markdown 加固 Golden Loop |
| [RUN-003](archive/runs/phase3.11/PHASE3.11-RUN-003-REGRESSION-SEMANTICS-SERIALIZER.md) | regression 语义升级 + Serializer Golden Loop |
| [RUN-004](archive/runs/phase3.11/PHASE3.11-RUN-004-FORMULA-EVIDENCE-LAYER.md) | Formula 跨证据层 Golden Loop |
| [RUN-005](archive/runs/phase3.11/PHASE3.11-RUN-005-TAXONOMY-FREEZE.md) | taxonomy / 优先级冻结 |
| [RUN-006](archive/runs/phase3.11/PHASE3.11-RUN-006-FOUR-STATE-AND-GENERALIZATION.md) | target_failure 四态 + Word/PDF 泛化 |
| [RUN-007](archive/runs/phase3.11/PHASE3.11-RUN-007-EVIDENCE-STRENGTH-PDF-REAL-DEFECT.md) | Evidence Strength 冻结 + PDF Real Defect |
| [RUN-008](archive/runs/phase3.11/PHASE3.11-RUN-008-BEHAVIOR-STRESS-TEST.md) | Behavior Family 压力测试（Undo） |
| [RUN-009](archive/runs/phase3.11/PHASE3.11-RUN-009-CONTRACT-SYNC-META-VALIDATION.md) | Contract-Sync Meta-Validation |
| [RUN-010](archive/runs/phase3.11/PHASE3.11-RUN-010-F3-RUNTIME-REAL-DEFECT.md) | F3 Runtime Real Defect Loop（Formula） |
| [RUN-011](archive/runs/phase3.11/PHASE3.11-RUN-011-WORD-FULL-GOLDEN-LOOP.md) | Word Full Golden Loop |
| [RUN-012](archive/runs/phase3.11/PHASE3.11-RUN-012-E6-PHYSICAL-RUNTIME.md) | E6 Physical Runtime（渲染 + 截图） |
| [RUN-013](archive/runs/phase3.11/PHASE3.11-RUN-013-E8-VISUAL-FIDELITY-PIPELINE.md) | E8 Visual Fidelity Pipeline（三层） |
| [RUN-014](archive/runs/phase3.11/PHASE3.11-RUN-014-E8-EVALUATOR.md) | E8 Evaluator（AST Diff 语义验证） |
| [RUN-015](archive/runs/phase3.11/PHASE3.11-RUN-015-E8-VISION-WIRING.md) | E8 真实视觉提取 + FFX verify 接线 |
| [RUN-016](archive/runs/phase3.11/PHASE3.11-RUN-016-VLM-STRUCTURE-MODE.md) | E8 VLM 结构模式（三态判定） |

### 3.2 ADL Loop（12 篇，含 PLAN）—— [runs/adl/](runs/adl/)

| 文档 | 说明 |
|------|------|
| [RUN-001](archive/runs/adl/ADL-LOOP-RUN-001.md) ~ [RUN-008](archive/runs/adl/ADL-LOOP-RUN-008.md) | ADL 闭环报告（Run #001-008） |
| `*PLAN.md` ×4 | ADL 各轮计划（RUN-002/005/006/008） |

### 3.3 Dogfood（7 篇）—— [runs/dogfood/](runs/dogfood/)

| 文档 | 说明 |
|------|------|
| [RUN-001](archive/runs/dogfood/DOGFOOD-RUN-001-SMOKE.md) ~ [RUN-007](archive/runs/dogfood/DOGFOOD-RUN-007-CONSUMER-ADAPTER.md) | Dogfood 闭环（Smoke → Known-Good/Bad → Real Repair → Regression） |

---

## 4. 索引核对

- 顶层 md：40 篇（含本 INDEX）
- ADR：30 篇 | contracts：16 篇 | design：2 篇 | releases：11 篇 | archive：2 篇
- RUN 报告：35 篇（phase3.11 ×16 + adl ×12 + dogfood ×7）
- 合计：**136 篇**
