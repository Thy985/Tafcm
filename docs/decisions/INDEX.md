# ADR 索引（docs/decisions/INDEX.md）

**定位（L2 Decision Truth）**：架构决策状态总表。人类看"为什么这么做"从这里进；
状态判词来自 [engineering/ENGINEERING-BASELINE.md](../engineering/ENGINEERING-BASELINE.md) §2.1（2026-08-19 评审）。
每个 ADR 自己负责完整内容——无需翻十几个 Audit。

**状态图例**：✅ VALID（有效） / 🟡 VALID-BUT-COSTLY（有效但需复审） / ⚪ Proposed（待签字） / 🚫 已废弃 / ⏭ SKIPPED

---

## 决策状态总表（29 篇）

| ADR | 主题 | 文档状态 | 判词 | 说明 |
|-----|------|---------|------|------|
| [0001](ADR/0001-project-naming-and-structure.md) | 项目命名与目录结构 | Superseded by 0031 | ✅ VALID | §1 命名条款被 ADR-0031 取代；§2 目录结构保留 |
| [0002](ADR/0002-state-management-riverpod.md) | Riverpod 状态管理 | Accepted | ✅ VALID | 唯一状态方案 |
| [0003](ADR/0003-storage-single-source-md-files.md) | .md 单一真相源 | Implemented | ✅ VALID | 存储统一 |
| [0004](ADR/0004-markdown-parser-extension-strategy.md) | 手写 Markdown 解析器 | Proposed | 🟡 VALID-BUT-COSTLY | 保留手写；建议升级 Accepted + fuzz 守门 |
| [0005](ADR/0005-exporter-facade-dependency-injection.md) | Exporter facade + DI | Accepted | ✅ VALID | 内部 static 污染见 DEBT-016 |
| [0006](ADR/0006-ci-github-actions.md) | GitHub Actions CI | Accepted | ✅ VALID | 选型成立 |
| [0007](ADR/0007-blockeditor-abstraction-design.md) | BlockEditor 抽象 | Accepted | ✅ VALID | AST 稳定不重构 |
| [0008](ADR/0008-editor-transaction-model.md) | Editor Transaction Model | Proposed | 🟡 VALID-BUT-COSTLY | **重构主战场**（IME coalescing 未实现） |
| [0009](ADR/0009-ui-architecture-design.md) | UI 架构设计 | 状态不一致 | 🟡 需治理 | 状态字段与 ADR-0011 冲突 |
| [0010](ADR/0010-SKIPPED.md) | 编号跳号占位 | SKIPPED | ⏭ N/A | 编号纪律 |
| [0011](ADR/0011-phase3.3-architecture-decisions.md) | Phase 3.3 架构决策 | Accepted | ✅ VALID | 5 条细化决策 |
| [0012](ADR/0012-live-editing-state.md) | Live / Committed 双状态 | Accepted | 🟡 VALID-BUT-COSTLY | ⭐ 首要重构候选（A-001） |
| [0013](ADR/0013-autosave-architecture.md) | 自动保存架构 | Accepted | ✅ VALID | 构建于 0012 |
| [0014](ADR/0014-document-asset-management.md) | 文档资产管理 | Accepted (v1.2) | ✅ VALID | 内容寻址 |
| [0015](ADR/0015-theme-architecture-migration.md) | 主题架构迁移 | Accepted | ✅ VALID | static→ThemeExtension |
| [0016](ADR/0016-document-repository-boundary.md) | 文档仓储边界 | Proposed | ⚪ 待签字 | 边界原则成立 |
| [0017](ADR/0017-design-system-alignment.md) | Design System Token 对齐 | Accepted | ✅ VALID | token 单一真相源 |
| [0018](ADR/0018-app-shell-navigation.md) | App Shell 导航 | Proposed | ⚪ 待签字 | 核心冻结 |
| [0019](ADR/0019-editor-interaction-layer.md) | Editor Interaction Layer | Accepted (v1.1) | ✅ VALID | Intent Layer 落地 |
| [0020](ADR/0020-block-model.md) | Block Model 冻结 | Accepted | ✅ VALID | 稳定锚点 |
| [0021](ADR/0021-repository-integrity-strategy.md) | 仓储完整性策略 | — | ✅ VALID | 引用成立 |
| [0022](ADR/0022-renderer-failure-policy.md) | Renderer 失败策略 | — | ✅ VALID | UnsupportedBlockFallback 刻意守卫 |
| [0023](ADR/0023-editor-observability-system.md) | Editor Observability | — | ✅ VALID | ADI 前置 |
| [0024](ADR/0024-agent-diagnostic-interface.md) | Agent Diagnostic Interface | Accepted | ✅ VALID | v0.1/v0.2 已合入 |
| [0025](ADR/0025-issue-triage-agent-architecture.md) | Issue Triage Agent 架构 | Proposed | ⚪ Pending | stateful triage 扩展 |
| [0025b](ADR/0025-phase-1.1-stateful-triage-extension.md) | Stateful Triage 扩展 | — | ⚪ Pending | 0025 扩展 |
| [0028](ADR/0028-cli-adi-validation-before-schema.md) | CLI adi validate before schema | Accepted | ✅ VALID | schema 收敛 |
| [0029](ADR/0029-list-element-nested-ast.md) | ListElement 嵌套 AST | Proposed | ⚪ 待签字 | 解决 BUG-5 |
| [0030](ADR/0030-ffx-verification-orchestrator.md) | FFX Verification Orchestrator | Accepted | ✅ VALID | Phase 3.10 根决策 |
| [0031](ADR/0031-rebrand-tafcm.md) | 品牌改名（FormulaFix → Tafcm） | Accepted | ✅ VALID | 取代 ADR-0001 §1；L0+L1+L2 已落地（2026-08-29） |

---

## 需要 Owner 关注（复审候选）

| ADR | 关注点 |
|-----|--------|
| **0012 + 0008** | 合并为 **Architecture Review A-001**（Editor State & Transaction Model）——退出判据：CORE-004/006 + Behavior 全绿 + IME coalescing |
| 0004 | 建议升级 Proposed → Accepted（fuzz 守门已落地） |
| 0009 | 状态字段治理（文档头 vs ADR-0011 引用不一致） |
| 0016 / 0018 / 0029 | 待 Owner 签字转正 |

## 相关

- 判词依据：[engineering/ENGINEERING-BASELINE.md](../engineering/ENGINEERING-BASELINE.md) §2.1
- ADR 正文：[ADR/](ADR/)
