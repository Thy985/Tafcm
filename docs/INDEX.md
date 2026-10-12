# Tafcm 文档全量索引（INDEX）

**生成日期**: 2026-10-12（本轮文档漂移同步；上轮 2026-08-22）
**用途**: docs/ 下全部文档的单页索引——顶层 + 子目录 + RUN 报告分类表。
**入口**: 新读者从 [README.md](README.md) 进入（分类导航）；本页为全量清单（机器可核对）。

> **计数依据**：2026-10-12 `Get-ChildItem docs -Recurse -Filter *.md -File` 实测，docs/ 共 **224 篇 md**。

---

## 1. 顶层文档（6 篇 md + 若干历史引用锚点）

> docs/ 根目录下实际 6 篇 md：`README.md` / `INDEX.md` / `ENGINEERING.md` / `ROADMAP.md` / `INFO-ARCHITECTURE-DESIGN.md` / `MIGRATION-MAP.md`。
> 下方 §1.1-1.5 沿用历史锚点形式列出曾置于顶层、现已按四层信息架构归位到子目录的关键文档（保持链接可达）。

### 1.1 架构与路线图

| 文档 | 说明 |
|------|------|
| [ENGINEERING.md](ENGINEERING.md) | ★ 工程手册（唯一入口：L0-L5 地图，2026-08-30 新增） |
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

### 2.1 ADR（架构决策记录，33 篇）

见 [ADR/](decisions/ADR/) —— 编号 0001 ~ 0033（0010 跳号占位；0026 / 0027 编号已预留但 ADR 文件尚未创建；0025 与 0032 存在编号重复，分别以 `0025b` / `0032a` / `0032b` 区分，状态见 [decisions/INDEX.md](decisions/INDEX.md)，编号治理待 Owner 决定）。
关键：ADR-0003（存储单一真相源）/ 0024（ADI）/ 0028（CLI before schema）/ 0029（嵌套 AST）/ 0030（Verification Orchestrator）/ 0031（品牌改名 Tafcm，取代 ADR-0001 §1）/ 0033（产品定位收敛 T/F/M）。

### 2.2 contracts（任务契约，16 篇）

见 [contracts/](contracts/) —— phase2.1 ~ phase3.4 各阶段 Task Contract（含 PR 关联 / 验收清单）。

### 2.3 design（设计文档，2 篇）

见 [design/](design/) —— [adi-design-v1.md](design/adi-design-v1.md)（ADI 设计）/ [ui-spec.md](design/ui-spec.md)（UI 规范）。

### 2.4 releases（验证报告，11 篇）

见 [releases/](releases/) —— phase1/2/3 各阶段 Verification Report + 真机验收报告。

### 2.5 archive（历史档案，58 篇，含 35 篇 RUN 报告）

见 [archive/](archive/) —— 已归档/历史文档：audits（CRITICAL-REVIEW / 能力再审计 / 专项审计）/ runs（phase3.11 ×16 + adl ×12 + dogfood ×7）/ spikes（parser / word / officecli / markdown 生态）/ old-designs / governance。

### 2.6 evidence（证据索引，2 篇）

见 [evidence/](evidence/) —— 能力 / 视觉 / 消费证据索引（人类可追溯判定）。

### 2.7 assets（设计资产）

设计稿全量原件见仓库根 [formulafix-redesign.design/](../../formulafix-redesign.design/)（冻结，目录名保留）；
设计 token 真源见 [design-system/tokens.json](../../design-system/tokens.json)；
截图资产见 [assets/screenshots/](assets/screenshots/)（2 张 jpeg，无 md）。

### 2.8 principles（工程原则，4 篇，2026-08-30 新增）

见 [principles/](principles/) —— 稳定总原则（不随 session 变）：
| 文档 | 说明 |
|------|------|
| [engineering-principles.md](principles/engineering-principles.md) | 工程总原则 + 文档准入四问 |
| [architecture-principles.md](principles/architecture-principles.md) | 分层 / 存储 / 编辑器 / 状态 / 渲染原则 |
| [testing-principles.md](principles/testing-principles.md) | 门禁 / 证据等级 / 回归纪律 |
| [agent-collaboration.md](principles/agent-collaboration.md) | Agent 权限 / Memory Distillation |

### 2.9 guides（开发指南，3 篇，2026-08-30 新增）

见 [guides/](guides/) —— 怎么做：
| 文档 | 说明 |
|------|------|
| [development.md](guides/development.md) | 开发指南（环境 / 流程 / 规范速查 / 常见坑） |
| [testing.md](guides/testing.md) | 测试指南（怎么跑 / 怎么写） |
| [debugging.md](guides/debugging.md) | 调试指南（ADI 工作流 + 排查手册） |

### 2.10 articles（对外宣传文章，2 篇）

见 [articles/](articles/) —— CSDN / 微信等对外发布版本。

### 2.11 knowledge-inventory（知识盘点，10 篇，2026-09 新增）

见 [knowledge-inventory/](knowledge-inventory/) —— 含 re-archaeology（考古式知识挖掘）、evidence_map（证据地图）、decision_patterns / failure_patterns / knowledge_synthesis 等盘点产物。

### 2.12 agent-audit / agent-investigations / agent-supervision（Agent 产物）

- [agent-audit/](agent-audit/)：Maintainer Agent 每日维护审计（INDEX.md + YYYY-MM-DD.md，CI 自动生成），32 篇。
- [agent-investigations/](agent-investigations/)：复杂 Issue 深度调查归档，2 篇。
- [agent-supervision/](agent-supervision/)：独立监督者周报（W36-W40，2026-08 至 2026-10-02），5 篇。
- 规范见 `.agent/tafcm-maintainer/`（PROMPT / POLICY / SCHEMA）。

### 2.13 regression（回归用例包，7 篇）

见 [regression/](regression/) —— README + BUG-001-hard-break / BUG-002-pipe-line / BUG-003-list-order 三个 case 包（各含 case.json / input.md / expected.json / README）。

## 3. RUN 报告（35 篇，按类型归档）

### 3.1 Phase 3.11 Capability Hardening Loop（16 篇）—— [runs/phase3.11/](archive/runs/phase3.11/)

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

### 3.2 ADL Loop（12 篇，含 PLAN）—— [runs/adl/](archive/runs/adl/)

| 文档 | 说明 |
|------|------|
| [RUN-001](archive/runs/adl/ADL-LOOP-RUN-001.md) ~ [RUN-008](archive/runs/adl/ADL-LOOP-RUN-008.md) | ADL 闭环报告（Run #001-008） |
| `*PLAN.md` ×4 | ADL 各轮计划（RUN-002/005/006/008） |

### 3.3 Dogfood（7 篇）—— [runs/dogfood/](archive/runs/dogfood/)

| 文档 | 说明 |
|------|------|
| [RUN-001](archive/runs/dogfood/DOGFOOD-RUN-001-SMOKE.md) ~ [RUN-007](archive/runs/dogfood/DOGFOOD-RUN-007-CONSUMER-ADAPTER.md) | Dogfood 闭环（Smoke → Known-Good/Bad → Real Repair → Regression） |

---

## 4. 索引核对（2026-10-12 实测）

- 顶层 md：6 篇（README / INDEX / ENGINEERING / ROADMAP / INFO-ARCHITECTURE-DESIGN / MIGRATION-MAP）
- architecture：8 篇 | product：7 篇 | engineering：14 篇
- decisions：INDEX 1 篇 + REVIEW-BACKLOG 1 篇 + ADR/ 33 篇（共 35） | contracts：16 篇 | design：2 篇 | releases：11 篇
- principles：4 篇 | guides：3 篇 | articles：2 篇 | knowledge-inventory：10 篇
- agent-audit：32 篇 | agent-investigations：2 篇 | agent-supervision：5 篇
- regression：7 篇 | evidence：2 篇 | assets：0 篇 md（2 张截图）
- archive：58 篇（含 35 篇 RUN 报告：phase3.11 ×16 + adl ×12 + dogfood ×7）
- 合计：**224 篇 md**
