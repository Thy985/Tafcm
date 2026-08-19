# ADR-0030: FFX Verification Orchestrator（Agent-Native Verification Harness）

- **状态**: Accepted（2026-08-19，Human Owner 批准）
- **日期**: 2026-08-19
- **决策者**: Human Owner（设计评审通过）+ AI Agent（起草）
- **关联**: `docs/FFX-VERIFICATION-ORCHESTRATOR-v1.md`（v0.2 设计稿，已批准）；`docs/FEATURE-CAPABILITY-COVERAGE-MATRIX-v1.md`（契约投影源）；`docs/FEATURE-COMPLETION-EVIDENCE-MATRIX-v1.md`（L1 完成判定）

## 背景

FFX/CLI-Anything 承担的是"测试工具/项目操作 CLI"（`project/analyze/adi/diag` 平铺命令），未成为 Agent-Native Verification Orchestrator。现有 `ffx analyze` 用 Python 正则、`ffx project export` 写原始字符串——**不调用真实 FormulaFix 生产路径**（Dart `lib/core/parser/`、`lib/domain/services/exporters/`）。同时 wpscli/officecli 等消费端工具未入 FFX 模块，验证证据链断裂。

## 决策

将 FFX 升级为 **Agent Verification Harness**：编排 ADI / WPSCLI / OfficeCLI / integration_test / fuzz / Golden 成 Agent 可发现、执行、观察、验证的结构化操作面。

### 架构（5 边界，冻结）

1. **Orchestrator**：只做调度、超时、退出码、Evidence Graph、报告——能力无关。
2. **Capability Adapter Registry**：每能力一个 Adapter（统一契约 `discover/prepare/execute/collect_evidence/evaluate`）；新能力 = 新 Adapter 文件，核心零改动（杜绝巨型 if/else）。
3. **Runtime Bridge**：`dart run` 直调真实 Dart production classes（parser/serializer/exporter）；禁止 Python 侧重实现生产逻辑。
4. **Artifact Producer Adapter**：FFX orchestrates、FormulaFix produces（真实 DOCX/PDF 由 Flutter exporter 生成）。
5. **Consumer Adapter**：wpscli/officecli/pdfinfo 纯 subprocess 薄封装 + 输出归一化，不重实现。

### 数据契约

- **`contracts/*.json` = 机器真相源**（一等公民），Feature Capability Matrix 为派生投影；`ffx contract sync` 生成 + schema 校验防漂移。
- **Failure Record**：每次 FAIL 写真实故障记录，`diagnostic_id` 必须引用它（`trc_` 出自 ADI 既有 trace；`art_` 出自 Artifact Failure Record；禁虚拟 ID）。

### 退出码（五级）

`0 PASS / 1 FAIL / 2 WARN / 3 INCONCLUSIVE / 127 ENV_MISSING`——环境缺失 ≠ 产品失败；INCONCLUSIVE 覆盖 replay inconclusive / 真机证据缺失 / 视觉未判定。

### v1 命令

`ffx capability verify <name>` / `ffx capability diagnose <failure-id>` / `ffx capability repair-verify <failure-id>`。P0 = markdown 最小闭环（verify→diagnose→repair-verify），P1 = word/pdf（消费端），v2 = 真机编排（接口已定义：DeviceExecutor / DeviceArtifactCollector / DeviceRuntimeBridge）。

## 核心不变量（七条冻结，任何实现不得违背）

1. **FFX 只编排，不实现领域能力**——新能力通过 Adapter 接入，orchestrator 核心保持能力无关。
2. **失败必须产生真实 diagnostic identity**——`diagnostic_id` 引用真实 Failure Record（trc_ 出自 ADI trace，art_ 出自 Artifact Failure Record），禁止虚拟 ID。
3. **Evidence > Agent 自述**——修复的证明是 `before=failed → after=passed → regression=passed` 的实证，不是声明。
4. **Artifact Consumer 与 Product Runtime 是不同证据层**——消费端验证（WPS/OfficeCLI）不能替代产品运行时验证，反之亦然。
5. **Environment unavailable ≠ product failure**——127 独立，Agent 不得把"wpscli 没装"误判为"Word Export broken"。
6. **Completion 由 Capability Contract + Evidence 决定**——不因"测试全绿"或"Agent 声称完成"而下结论。
7. **verify / diagnose 只读；repair-verify 只验证，不直接修代码**——修改与 merge 永远在 Human 边界内（AGENTS.md §5.0）。

## 边界（不变量）外延

- `adi validate` 保持纯 ADI（Replay+Invariant），**不并入** flutter test/CI——那属 Change Impact Analysis，归待建 ADR-0026。
- RULE-FFX-001：verify 是验证不是重构，不触碰 Core Stable / Debt Accepted 代码；发现债务 → 报告，不擅自改。
- 真机编排（v2）接口现在定义，不在 v1 实现。

## 后果

- 正面：功能完成从"静态表"变为"可执行协议"；Agent 获得可计算、可审计的工程状态；避免 FFX 变成第二个测试框架。
- 负面/成本：Runtime Bridge 需维护 dart runner 与 lib/ API 同步；contracts 与矩阵需 sync 防漂移。
- 待办：P0.1（verify markdown 闭环）→ P0.2/P0.3（diagnose/repair-verify）→ P1（word/pdf + consumer adapter）→ v2（device）。
