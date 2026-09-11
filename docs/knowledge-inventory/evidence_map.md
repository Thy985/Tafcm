# Evidence Map（证据链映射）

> Knowledge → Source → Implementation → Test → Runtime → Human Confirmation 全链路。
> 每条链标注置信度；区分"已闭环"与"部分闭环"。

---

## E-001 · Evidence-backed Capability Verification（契约验证闭环）

- **Knowledge**: K-013 / K-042 — 能力完成 = 机器契约 + 可执行验证 + 证据分级
- **Sources**: contracts/*.json · ADR-0030 · FULL-CAPABILITY-REAUDIT.md
- **Implementation**: `ffx capability verify` / `ffx analyze contract-sync`（tools/ffx-cli，170+ pytest）
- **Validation**: contract-sync schema 校验 + verify 退出码（0/1/2/3/127）
- **Runtime**: FULL-CAPABILITY-REAUDIT 11 能力全量 ffx verify（pass 6 / warn 4 / fail 1 可审计）
- **Human Confirmation**: Human Owner 批准 ADR-0030；RUN-009 meta-validation
- **Confidence**: High（S4-S5）

---

## E-002 · Evidence Strength 分级（release gate 语义）

- **Knowledge**: K-012 — 证据强度链 + 禁止跨等级推断
- **Sources**: PHASE3.11-RUN-007 / RUN-013 · testing-principles.md
- **Implementation**: contracts `evidence_strength` / `minimum_required` 字段 + 枚举冻结
- **Validation**: contract-sync status=ok；枚举语义修正记录（virtual vs physical）
- **Runtime**: Formula achieved=['synthetic','virtual_device_runtime']，minimum_required='physical_device_runtime'
- **Human Confirmation**: 评审 §7 冻结批准
- **Confidence**: High（S4）

---

## E-003 · WYSIWYG 范式重构（编辑/预览 → 块级）

- **Knowledge**: K-001 / K-007 — 范式转向 + 状态双态化
- **Sources**: CRITICAL-REVIEW.md · ADR-0008/0012/0019 · ROADMAP Phase 3
- **Implementation**: `kEnableNewEditor=true`、移除 `previewModeProvider`、Transaction/Command/BlockOperation、Live/Committed
- **Validation**: E2E LIVE-EDIT-01（双态化触发源）+ 全量 widget/单元测试
- **Runtime**: 真机/模拟器编辑器实际运行
- **Human Confirmation**: Phase 3.1-A 关闭判定
- **Confidence**: High（S5）

---

## E-004 · .md 单一真相源迁移

- **Knowledge**: K-005 / K-035 — 多存储收敛
- **Sources**: ADR-0003 · ADR-0014 · CRITICAL-REVIEW §2.1
- **Implementation**: 三层模型 + 原子写 + 幂等迁移 + UUID 文件名 + sha256 资产命名
- **Validation**: storage_repository_test / file_service_decode_test / 迁移测试
- **Runtime**: 应用实际读写 .md
- **Human Confirmation**: Phase 1.2 关闭
- **Confidence**: High（S4-S5）

---

## E-005 · ADI 诊断闭环（Agent 修复真实缺陷）

- **Knowledge**: K-020 / K-028 — ADI + Real Defect Repair Loop
- **Sources**: ADR-0024 · docs/archive/runs/adl/（8 run）· dogfood/（7 run）
- **Implementation**: tools/adi/adi.dart + mcp_server.dart + ErrorSnapshot/AdiRecord/AdiView + 权限模型
- **Validation**: ADL-LOOP-RUN-001~008（含 run005 真实修复 proof、run006 agent loop）
- **Runtime**: DOGFOOD-RUN-005 REAL-REPAIR、DOGFOOD-RUN-004 消费端缺陷修复
- **Human Confirmation**: Human Owner 验收诊断闭环
- **Confidence**: High（S5）

---

## E-006 · FFX 消费端闭环（PDF Real Defect）

- **Knowledge**: K-023 / K-028 / K-029 — Verification Harness + Consumer 证据层
- **Sources**: ADR-0030 · PHASE3.11-RUN-007 · contracts/word_export.json
- **Implementation**: Runtime Bridge 直调 `sanitizeSvgString`（回退 `return input`→`return 'x'` 真实缺陷）+ wpscli/officecli Consumer Adapter
- **Validation**: Golden Loop（verify→diagnose→repair-verify→evidence delta→regression）
- **Runtime**: PDF 首个真实代码缺陷完整闭环（非注入）
- **Human Confirmation**: Human Owner 批准 ADR-0030 + 闭环验证
- **Confidence**: High（S5）

---

## E-007 · E8 视觉保真三层（主观能力可测）

- **Knowledge**: K-027 / K-031 — Visual Fidelity Pipeline
- **Sources**: PHASE3.11-RUN-013/014/015/016
- **Implementation**: E8.1 Screenshot Integrity（PNG valid/尺寸/非空）→ E8.2 Structural Fidelity（LaTeX AST 结构断言：`E=mc^2`→superscript）→ E8.3 Pixel/VLM
- **Validation**: 模拟器截图 + 结构解析 exit=0；E8_PNG_INFO（bytes=4910 w=823 h=168）
- **Runtime**: 模拟器/真机截图管线（私有目录解决 scoped storage）
- **Human Confirmation**: E8 三层评审冻结；VLM 评估器探路（RUN-014/016）
- **Confidence**: High（S5 结构层）/ Medium（像素层，VLM 未成 gate）

---

## E-008 · Issue Triage 三段式（Untrusted Analyzer）

- **Knowledge**: K-019 / K-021 — AI 判断 + 系统执行
- **Sources**: ADR-0025 · .github/workflows/issue-triage.yml
- **Implementation**: fetch_input.sh（context.md 规范化）→ claude-code-action（只读，仅写 findings.json）→ create_issues.sh（白名单校验+三态+去重）
- **Validation**: fixture 测试（提取/创建/去重/越权过滤）+ dry-run 校准
- **Runtime**: PR 事件触发（pull_request_review / review_comment）
- **Human Confirmation**: Human Owner 评审授权；上线需批准 dry_run=false
- **Confidence**: High（S4 契约/测试）/ Medium（真实精度待 dry-run 后校准）

---

## E-009 · 可观测性五层（trace + 回放 + 不变量）

- **Knowledge**: K-009 — Observability 内建
- **Sources**: ADR-0023 · ADR-0024
- **Implementation**: 五层 trace（Interaction/Command/Transaction/ErrorSnapshot/Replay）+ Canonical AST Fingerprint + Invariant Checker + LIGHT/FULL/OFF
- **Validation**: test/observability/（32 文件）
- **Runtime**: 编辑器实际诊断 + ADI 消费
- **Human Confirmation**: ADR-0023 Accepted
- **Confidence**: High（S4）

---

## E-010 · 回归判定四层 Failure Identity

- **Knowledge**: K-014 — 回归纪律
- **Sources**: testing-principles.md · VERIFICATION-POLICY.md · PHASE3.11-RUN-003
- **Implementation**: baseline failure set + fingerprint diff
- **Validation**: regression assets（docs/regression/markdown 等）+ BUG case 包
- **Runtime**: Phase 3.11 回归语义验证
- **Human Confirmation**: 评审确认
- **Confidence**: High（S4）

---

## E-011 · Golden 视觉基线（跨平台限制 + 镜像固定）

- **Knowledge**: K-015 — 视觉基线确定性
- **Sources**: testing-principles.md · ci.yml · GOLDEN-CI-001
- **Implementation**: Linux CI 生成 golden（test/golden/ 15 文件）+ `CI_IMAGE: ubuntu-24.04` 固定 + update_goldens workflow
- **Validation**: golden 测试在 Linux CI 通过；Windows 本地不比对
- **Runtime**: CI 每次合并
- **Human Confirmation**: 镜像固定决策（Tier 2 TEST_GAP_PLAN T2-0）
- **Confidence**: High（S4）

---

## E-012 · Agent 权限与记忆治理

- **Knowledge**: K-018 / K-022 / K-025 — 权限矩阵 + Memory Distillation + 故障归因
- **Sources**: .agent/AI_POLICY.md · AGENTS.md · agent-collaboration.md · ADR-0021
- **Implementation**: 权限矩阵 + Human-Owner 文件 + agent-failure-log + Memory Distillation 管道
- **Validation**: 8 次 ADL 闭环 + 长期 CI 执行
- **Runtime**: 全程协作
- **Human Confirmation**: Human Owner 持续审批
- **Confidence**: High（S5 本仓）

---

## 覆盖缺口（未闭环 / 未验证）

| 知识 | 缺口 | 状态 |
|------|------|------|
| E8.3 Pixel/VLM 视觉判定 | VLM 评估器未成为 release gate | 探路 |
| Issue Triage 真实精度 | dry_run 校准后的 precision/recall 未公开 | 待校准 |
| Word Full Golden Loop | wpscli 环境就绪后待验证 | 部分 |
| 真机 device family（v2） | 接口已定义未实现 | 未实现 |

---
*Generated by Knowledge Archaeology · 只读*
