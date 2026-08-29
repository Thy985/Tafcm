# FFX Verification Orchestrator v1 — 设计文档

> **文档性质**：设计评审稿（Design Review Draft，**实现开始前必须提交评审**；未获 Owner 批准不进入实现）
> **日期**：2026-08-19
> **版本**：**v0.2-revision**（v0.1 经 Owner 评审 → 10 条意见全部收敛；本版为修订后 P0 设计）
> **作者**：AI Agent 起草，Human Owner 评审决策
> **关联**：候选 **ADR-0030**（0026 已预留给 Change Impact Analysis；0027 空闲）
> **状态**：✅ **已批准（2026-08-19，Human Owner）—— 进入 P0 实现**（§14 五项决策全部批准：ADR-0030 编号确认 / contracts 反转确认 / Runtime Bridge 方案确认 / consumer adapter 进 P1 确认）
> **文档导航**（2026-08-19 补，防孤儿）：本设计属 Phase 3.10 文档族，关联
> [ADR-0030（架构决策根）](../decisions/ADR/0030-ffx-verification-orchestrator.md)、
> [PHASE3.10-ENGINEERING-BASELINE-v1.md（工程基线锚点）](../engineering/ENGINEERING-BASELINE.md)、
> [docs/README.md（统一导航）](../README.md)

---

## 0. 修订记录（v0.1 → v0.2，10 条评审意见全收敛）

| # | Owner 意见 | v0.2 处置 |
|---|-----------|----------|
| 1 | FFX 不应"自己知道怎么测每个功能"（防巨型 if/else） | §3.1 **Capability Adapter Registry**：统一契约 `discover/prepare/execute/collect_evidence/evaluate`，orchestrator 核心能力无关 |
| 2 | 矩阵不应是唯一机器契约源 | §4.1 **`contracts/*.json` 提升为机器真相源**，Feature Matrix 改为派生投影 + schema 校验 |
| 3 | **Runtime Bridge 缺失**：FFX 现在调不到真实 Dart production path | §3.2 **Runtime Bridge**：`tools/ffx-runtime/` dart capability runner 直调真实 `markdown_parser.dart`/serializer/exporter |
| 4 | Word/PDF 真实导出缺 Producer Bridge | §3.3 **Artifact Producer Adapter**：`ffx/harness/producers/`（dart_exporter.py/flutter_runtime.py），"FFX orchestrates, Tafcm produces" |
| 5 | diagnostic_id 应从故障产生点生成，非事后随机 | §4.3 **Failure Record 不变量**：`diagnostic_id` 必须引用真实 Failure Record；trc_ 来自 ADI 既有 trace、art_ 来自 FFX Artifact Failure Record，禁止虚拟 ID |
| 6 | repair-verify 不应依赖 Agent 声明为证明 | §5.3 **证明 = before/after/regression 实证**，Agent 声明仅是触发条件；输出固定 JSON |
| 7 | P0 顺序调整：diagnose/repair 提前 | §6/§13 **P0 = 最小完整闭环** `verify → diagnose → repair-verify`（markdown 先跑通），word/pdf 移 P1 |
| 8 | 真机编排放 v2 但接口现在定义 | §7 **v2 接口先行**：DeviceExecutor / DeviceArtifactCollector / DeviceRuntimeBridge + Runtime Adapter（local/simulator/device） |
| 9 | 增加 INCONCLUSIVE 退出码 | §5.0 退出码 **0 PASS / 1 FAIL / 2 WARN / 3 INCONCLUSIVE / 127 ENV_MISSING** |
| 10 | 架构图收敛 | §3 采用 Owner 收敛版架构图 |

**冻结的核心原则（将作为 ADR-0030 不变量，见 §10）**：
1. FFX 只编排，不实现领域能力。
2. 失败必须产生真实 diagnostic identity（引用 Failure Record）。
3. **Evidence > Agent 自述**（before/after/regression 实证）。
4. Artifact Consumer 与 Product Runtime 是**不同证据层**。
5. **Environment unavailable ≠ product failure**（127 独立）。
6. Completion 由 Capability Contract + Evidence 决定。
7. verify / diagnose 只读；repair-verify 只验证，不直接修代码。

---

## 1. 问题陈述：FFX 被"低配"了

### 1.1 现状（2026-08-19 实核）

`tools/ffx-cli/cli_anything/ffx/ffx_cli.py` 现有四组命令（click group）：

| 组 | 命令（实核） | 本质 |
|----|-------------|------|
| `project` | info / set-field / save / undo / redo / snapshot / export / diff / status … | **模型台架**（JSON 操作，E4-M） |
| `analyze` | file / adr / audit | 静态分析（**Python 正则，E4-M**） |
| `adi` | doctor 等 12 个 | ADI 数据读取（E4-M） |
| `diag` | health（仅 1 个） | 诊断（近乎空壳） |

关键事实：
- **wpscli / officecli / pdfinfo / pdftotext 均未入 FFX 的 Python 模块**（find+grep 零命中）——消费端验证此前是手动 shell 审计，未编排。
- **FFX 现有"分析/导出"不调真实生产路径**：`ffx analyze` 用 Python 正则、`ffx project export` 写原始字符串——而真实 Parser/Exporter 是 Flutter/Dart（`lib/core/parser/markdown_parser.dart`、`lib/domain/services/exporters/*.dart`）。→ 这正是 §3.2 Runtime Bridge 要根治的。
- `diag` 组仅 `health`，无诊断编排能力。

### 1.2 问题本质

> 当前：**给 Agent 一组命令。**
> 目标：**把复杂软件的能力压缩成 Agent 可以发现、执行、观察、验证的结构化操作面。**

当 Agent 需要验证"Word 导出是否完成"时，现在必须自己串：跑 exporter → 找 docx → 手动调 wpscli → 手动调 officecli → 读多个孤立输出 → 自己判断。FFX Orchestrator 把这条链压缩为一条命令 + 结构化报告。

---

## 2. 组件角色契约（谁负责什么）

| 组件 | 角色 | 职责边界（不越界） |
|------|------|--------------------|
| **FFX** | **Agent Action + Verification Orchestrator** | 调度 Adapter、超时、退出码、Evidence Graph、报告、diagnostic_id；**不实现任何领域能力** |
| **Capability Adapter** | 单能力验证编排单元 | 统一契约五方法（§3.1）；含该能力的验证步骤定义 |
| **Runtime Bridge** | 真实生产路径调用 | `dart run` 直调 Flutter/Dart production classes（parser/serializer/exporter） |
| **Artifact Producer Adapter** | 真实产物生成 | 调 Flutter production exporter → 真实 .docx/.pdf → artifact path + metadata |
| **ADI** | Runtime Observation + Failure Diagnosis | 采集/重放/诊断运行时证据；`adi validate` 保持纯 ADI（AS-R2.5），不并入 flutter test/CI |
| **WPSCLI** | Office Consumer Runtime | word2pdf / pdf2txt |
| **OfficeCLI** | Document Render/Inspection Runtime | 渲染截图 / issue 检查 |
| **Flutter integration_test** | Product Runtime | INT-A/B/C/D 行为验证 |
| **Golden** | Visual Regression Evidence | 像素级回归（仅 WSL，环境三固定） |
| **fuzz / roundtrip** | Round-trip Evidence | 往返保真证据 |
| **`contracts/*.json`** | 机器真相源 | 能力契约（Required/Optional/policy），矩阵为其投影 |

---

## 3. 核心架构（Owner 收敛版）

```
                         AI Agent
                            │
              ┌─────────────┴─────────────┐
              │                           │
           Reason                         Act
              │                           │
              └─────────────┬─────────────┘
                            ↓
                    FFX Verification
                       Orchestrator
                            │
              ┌─────────────┼─────────────┐
              ↓             ↓             ↓
       Capability      Runtime Bridge   Consumer
        Adapters           │            Adapters
              │             │              │
      ┌───────┼──────┐      ↓       ┌──────┼──────┐
      ↓       ↓      ↓  Flutter    WPSCLI OfficeCLI
    Parser   Word    PDF Runtime
      │       │      │
      └───────┼──────┘
              ↓
        Evidence Graph
              │
       ┌──────┼───────┐
       ↓      ↓       ↓
      ADI   Artifacts Runtime
       │      │       │
       └──────┼───────┘
              ↓
      Completion Decision
              ↓
    PASS / FAIL / WARN / INCONCLUSIVE / ENV
```

### 3.1 Capability Adapter Registry（评审点 1 —— 防巨型 if/else）

每个 capability 提供一个 **Adapter**，实现统一五方法契约：

```python
class CapabilityAdapter(Protocol):
    id: str                        # "markdown" / "word" / ...
    contract: CapabilityContract   # 从 contracts/<id>.json 加载

    def discover(self) -> list[Evidence]          # 环境探测：工具/产物是否存在
    def prepare(self) -> None                     # 准备 corpus / 临时目录（只读，不写仓库）
    def execute(self) -> list[Evidence]           # 跑真实生产路径（经 Runtime/Producer Bridge）
    def collect_evidence(self) -> list[Evidence]  # 聚合所有 stage 证据
    def evaluate(self) -> CapabilityReport        # 对照 contract 判定 status
```

**FFX Orchestrator 核心只做**：调度 → 超时 → 退出码 → Evidence Graph → 报告。**不包含任何 capability 特化逻辑**。

以后加 `ffx capability verify image/mermaid/table` = 新增一个 Adapter 文件，**orchestrator 零改动**。注册方式：`ffx/harness/adapters/registry.py` 按目录扫描 + `id` 声明，不写 if/else。

### 3.2 Runtime Bridge（评审点 3 —— P0 最大技术风险，必须根治）

**问题**：FFX 当前 `analyze`=Python 正则、`project export`=原始字符串，验证的是测试台架而非产品。真实 Parser/Serializer/Exporter 是 Dart 生产类。

**方案**：`tools/ffx-runtime/` Dart capability runner：

```
FFX (Python orchestrator)
  ↓ subprocess
dart run tools/ffx-runtime/bin/capability_runner.dart <capability> <corpus_dir> <out_dir>
  ↓
调用真实 lib/ 生产类：
  markdown_parser.dart / markdown_serializer.dart
  exporters/word_exporter.dart / pdf_exporter.dart
  ↓
返回 JSON（结果 + artifact 路径 + 退出码）
```

**契约**：runner 是**只读生产路径代理**——import 真实 `lib/` 类，不复制逻辑；输出归一化 JSON（`{ok, artifacts, metrics, errors}`）。FFX 侧 `ffx/harness/runtime/dart_bridge.py` 负责 subprocess + 超时 + 输出解析。

> **验收红线**：verify markdown 的 parser 证据必须来自 `markdown_parser.dart` 运行结果，**禁止 Python 侧重新实现解析**。否则"看起来很漂亮的 Orchestrator 验证的仍是台架"。

### 3.3 Artifact Producer Adapter（评审点 4 —— "FFX orchestrates, Tafcm produces"）

`ffx/harness/producers/`：

| 文件 | 职责 |
|------|------|
| `dart_exporter.py` | 经 Runtime Bridge 调 Flutter/Dart production exporter → 真实 .docx/.pdf → 返回 artifact path + metadata |
| `flutter_runtime.py` | 调 integration_test / build 产物（v2 扩展为 device/simulator） |

**明确禁止**：FFX 侧用 Python 重新生成 DOCX/PDF。Producer 只做"调用真实 exporter + 收集产物"，不做领域实现。

### 3.4 Consumer Adapters（薄封装）

`ffx/harness/consumers/`：`wpscli.py` / `officecli.py` / `pdfinfo.py`——纯 subprocess 封装 + 输出归一化（exit_code + summary + issues 列表），**不重实现** WPS/Office/PDF 引擎。

### 3.5 Runtime Adapter 抽象（评审点 8 —— v2 接口现在定义）

```
Runtime Adapter
  ├── local      (v1: 本机 dart run / 本机 CLI)
  ├── simulator  (v2)
  └── device     (v2: 真机)
```

v2 接口（**现在只定义接口，不实现**）：

```python
class DeviceExecutor(Protocol):          # build/install/launch/标准操作序列
class DeviceArtifactCollector(Protocol): # 截图/日志/evidence 采集
class DeviceRuntimeBridge(Protocol):     # 真机 ↔ ADI 观测绑定
```

v1 与 v2 共用同一 Capability Adapter 契约，v2 只替换 Runtime Adapter 实现，**不做架构重构**。

---

## 4. 数据契约

### 4.1 `contracts/*.json` = 机器真相源（评审点 2 —— 反转源/投影关系）

**原则**：机器契约是一等公民，人类矩阵是它的**派生投影**。Markdown 表格不适合机器解析、版本控制与 schema validation。

`contracts/markdown_parser.json`：

```json
{
  "id": "FEAT-MD-PARSE",
  "capability": "markdown",
  "required_evidence": ["E1", "E2", "E3"],
  "required_checks": ["paragraph", "heading", "nested_list", "formula", "mermaid"],
  "completion_policy": {
    "unknown_max": 3,
    "blocking_unknown": ["real_device_visual_fidelity"]
  },
  "s0_unsupported": ["autolink", "footnote", "definition_list"]
}
```

**生成/校验**：`tools/ffx-cli` 提供 `ffx contract sync`（从当前矩阵提取并生成 contracts/*.json）+ JSON Schema 校验；`ffx contract view` 反向生成人类可读的 Feature Matrix 投影。**漂移防护**：`sync` 输出 diff，矩阵与契约不一致时显式报错，不允许静默漂移。

> 落地路径（待 Owner 确认）：矩阵保持权威人类视图，contracts 为机器真相源，双向由生成器维持一致 + 校验防漂移。

### 4.2 Evidence Graph

每 stage 证据记录：`(stage, adapter, tool, exit_code, artifact_path, summary, as_of)`；`as_of` = git sha + 时间。全部 stage 汇成 Evidence Graph → 供 evaluate 判定与 diagnose 消费。

### 4.3 Failure Record + diagnostic_id 不变量（评审点 5）

```
Observation / Artifact Failure
        ↓
Failure Record（真实故障记录：stage / tool / evidence / 上下文）
        ↓
diagnostic_id（引用该 Record）
        ↓
Evidence Graph
```

**正式不变量**：

> **`diagnostic_id` 必须引用真实 Failure Record，不允许仅为报告生成虚拟 ID。**

- `trc_XXXX`：来自 **ADI 既有 trace**（运行时/链路失败时，复用 ADI trace_id）。
- `art_XXXX`：来自 **FFX Artifact Failure Record**（产物/消费端失败，无 ADI trace 时）。
- 无 ADI trace 时**禁止伪造 trc_ 前缀**（系统检测证据 ≠ 推断）。

---

## 5. v1 三个命令（修订后）

### 5.0 退出码（评审点 9 —— 五级，含 INCONCLUSIVE）

| 码 | 含义 | 使用场景 |
|----|------|---------|
| `0` | PASS | 契约全达标 |
| `1` | FAIL | 契约未达标（必带 `diagnostic_id`） |
| `2` | WARN | 达标但有非阻断 Unknown |
| **`3`** | **INCONCLUSIVE** | **replay inconclusive / 真机证据缺失 / 视觉未判定**——既非 PASS 也非 FAIL |
| `127` | ENV_MISSING | 环境依赖缺失（如 wpscli 未装），**≠ 产品失败** |

### 5.1 `ffx capability verify <name>`

- **输入**：capability 名；从 `contracts/<name>.json` 加载契约。
- **执行**：`discover → prepare → execute（经 Runtime/Producer Bridge）→ collect_evidence → evaluate`，全程只读。
- **输出**：`--json` → Capability Report（`status/coverage/evidence/unknown/next_actions`）；退出码按 §5.0。
- **失败路径**：任一步 FAIL → 写 Failure Record → 生成 `diagnostic_id`（§4.3）→ 报告含失败 stage 与上下文。

### 5.2 `ffx capability diagnose <failure-id>`

- **输入**：`diagnostic_id`（trc_/art_）。
- **执行**：按 Failure Record 拉取 → ADI latest-error / trace / replay（trc_ 时）→ 相关 Consumer evidence（OfficeCLI issues / WPS semantic）→ **Diagnostic Bundle**。
- **输出**：`failure_id` / `hypotheses`（按证据排序）/ `evidence_refs` / `suggested_next_action`。**不自动修复**。

### 5.3 `ffx capability repair-verify <failure-id>`（评审点 6 —— 证明 = 实证）

- **触发条件**：Agent 声明已修复（**仅触发，不是证明**）。
- **证明**：

```
Agent 修改代码
  ↓
repair-verify <id>
  ↓
重新执行 capability（同 5.1 全链）
  ↓
重新收集 evidence
  ↓
对比 before / after
  ↓
回归抽验（此前 PASS 的 capabilities）
  ↓
判定 pass / fail
```

- **固定输出 JSON**：

```json
{
  "before": "failed",
  "after": "passed",
  "regression": "passed",
  "evidence_delta": [{"stage": "ooxml", "before": "bad_zip", "after": "ok"}],
  "diagnostic_id": "art_0007"
}
```

- 边界：repair-verify 只验证；merge 仍归 Human Owner（AGENTS.md §5.0 不变）。

---

## 6. 逐能力执行计划（修订后优先级）

| 阶段 | 能力 | 链路 | 外部依赖 | 出口判据 |
|------|------|------|---------|---------|
| **P0.1** | `markdown` | **Runtime Bridge** → corpus → 真实 parser/serializer → round-trip → fuzz(2001) → integration → 聚合 | 无（dart run 本机） | verify 报告含**真实生产路径证据**（非 Python 台架） |
| **P0.2** | `diagnose` | Failure Record → diagnostic_id → ADI 关联 | 无 | 人为注入失败 → 产出真实 diagnostic_id |
| **P0.3** | `repair-verify` | before/after/regression 闭环 | 无 | 修复后返回固定 JSON |
| P1 | `word` / `pdf` | Producer Bridge → 真实 DOCX/PDF → OOXML/pdfinfo → **wpscli/officecli** | wpscli/officecli/pdfinfo/pdftotext | 真实消费端证据链 |
| P2 | `formula`/`undo`/`autosave`/`file`/`ime`/`theme`/`drag` | 契约化 + 模拟器侧链路 | — | 全 capability 有报告 |
| v2 | 真机编排 | `ffx device verify`（接口见 §7） | 真机 | 另行设计评审 |

> **P0 意义**：第一条完整闭环 `verify → fail → diagnose → fix → repair-verify` 最先在 markdown 跑通——这比把 verify 做成"一大堆测试编排"更有架构价值（评审点 7）。

---

## 7. v2 接口（现在定义，不实现）

```
ffx device verify <capability>
  build/install → launch → 标准操作序列 → runtime evidence → ADI observation → 判定 → session_id/trace_id
```

现在只冻结接口：

```python
class DeviceExecutor(Protocol):
    def build_and_install(self) -> str            # → session_id
    def launch(self, session_id: str) -> None
    def run_standard_ops(self, session_id: str, ops: list[str]) -> list[Evidence]
    def terminate(self, session_id: str) -> None

class DeviceArtifactCollector(Protocol):
    def collect_screenshots(self, session_id: str, out_dir: str) -> list[str]
    def collect_logs(self, session_id: str) -> list[Evidence]

class DeviceRuntimeBridge(Protocol):
    def bind_adi(self, session_id: str) -> str     # → trace_id
```

v1 的 Capability Adapter 契约与 v2 完全复用；v2 仅替换 Runtime Adapter 实现（local→simulator/device），**不做架构重构**（评审点 8）。

---

## 8. 明确不做（Non-Goals，v1）

1. ❌ **不实现领域能力**：不重写 parser/exporter/渲染/诊断——只编排。
2. ❌ **不写巨型 if/else 调度器**：新 capability = 新 Adapter 文件，orchestrator 核心零改动（评审点 1）。
3. ❌ **不用 Python 重实现生产路径**：一律经 Runtime Bridge / Producer Bridge 调真实 Dart/Flutter 类（评审点 3/4）。
4. ❌ **不改 `adi validate` 边界**（不并入 flutter test/CI，AS-R2.5，属待建 ADR-0026）。
5. ❌ **不自动修代码**：repair-verify 只验证；merge 归 Human。
6. ❌ **不做 v2 内容**：真机编排、Golden 全量并入（接口已定义，不实现）。
7. ❌ **不伪造证据**：127 区分环境缺失；3 区分 INCONCLUSIVE；diagnostic_id 必须引用真实 Failure Record。

---

## 9. 治理与边界

| 项 | 约定 |
|----|------|
| ADR | 候选 **ADR-0030**（0026 预留 Change Impact Analysis；0027 空闲）——需 Owner 确认编号 |
| AI 可执行 | `verify` / `diagnose`（只读）✅；`repair-verify` 在 Agent 声明修复后触发 ✅；**push/merge 仍 Human**（AGENTS.md §5.0 不变） |
| RULE-FFX-001 | verify 是**验证**不是**重构**——不触碰 Core Stable / Debt Accepted 代码；发现债务 → 报告，不擅自改 |
| 环境依赖 | wpscli/officecli/pdfinfo/pdftotext 缺失 → 127 + 缺失清单（不伪装失败） |
| 契约源 | **`contracts/*.json` 为机器真相源**；Feature Capability Matrix 为派生投影（§4.1） |

---

## 10. ADR-0030 核心不变量（七条冻结原则）

> 以下七条将写入 ADR-0030，任何实现不得违背：

1. **FFX 只编排，不实现领域能力**——新能力通过 Adapter 接入，orchestrator 核心保持能力无关。
2. **失败必须产生真实 diagnostic identity**——`diagnostic_id` 引用真实 Failure Record（trc_ 出自 ADI trace，art_ 出自 Artifact Failure Record），禁止虚拟 ID。
3. **Evidence > Agent 自述**——修复的证明是 `before=failed → after=passed → regression=passed` 的实证，不是声明。
4. **Artifact Consumer 与 Product Runtime 是不同证据层**——消费端验证（WPS/OfficeCLI）不能替代产品运行时验证，反之亦然。
5. **Environment unavailable ≠ product failure**——127 独立，Agent 不得把"wpscli 没装"误判为"Word Export broken"。
6. **Completion 由 Capability Contract + Evidence 决定**——不因"测试全绿"或"Agent 声称完成"而下结论。
7. **verify / diagnose 只读；repair-verify 只验证，不直接修代码**——修改与 merge 永远在 Human 边界内。

---

## 11. 风险与开放问题（Gap Matrix，修订后）

| # | 风险/缺口 | 影响 | 缓解 |
|---|----------|------|------|
| R1 | wpscli/officecli 未入 FFX Python 模块（手动 shell） | verify word 无法端到端 | P1 前写薄 consumer adapter（subprocess 封装 + 归一化） |
| **R7** | **Runtime Bridge 落地成本**：dart capability runner 需 import 真实 lib/ 类并处理 Flutter 依赖 | P0 核心路径 | P0.1 先做最小 runner（纯 Dart parser/serializer，无 Flutter UI 依赖）；验证 `dart run` 可用性与 corpus 接口 |
| R2 | diagnostic_id ↔ ADI trace 绑定 | diagnose 可能引用空 | **提升为不变量（§4.3/§10.2）**；实现前核对 `ffx adi` 现有 trace_id 字段 |
| R3 | golden 仅 WSL 可跑 | 跨平台证据不一致 | v1 不含 golden；环境三固定不变 |
| R8 | contracts/*.json 与矩阵漂移 | 机器契约失真 | `ffx contract sync` 生成 + schema 校验 + diff 显式报错（§4.1） |
| R4 | 真机链路长 | v2 复杂 | v2 只留接口，v1 不承诺 |
| R5 | 契约 JSON 抽取边界 | 覆盖不全 | P0.1 先抽 markdown_parser.json 一个，跑通后扩 |

---

## 12. 验收标准（文档存在 ≠ 可用）

v1 完成的**唯一判定**：以下端到端在真实环境可复现运行，产出真实证据（非 dry-run 模拟）：

1. **P0 出口（最小闭环）**：
   a. `ffx capability verify markdown` → 经 **Runtime Bridge 调真实 Dart parser/serializer**（非 Python 台架）→ 真实 fuzz 2001 轮 → JSON 报告 + 退出码 0。
   b. 人为注入失败（如篡改 round-trip 断言阈值）→ verify 返回 **FAIL + 真实 diagnostic_id**（引用 Failure Record）。
   c. `ffx capability diagnose <id>` → 产出诊断包。
   d. 修复 → `ffx capability repair-verify <id>` → 返回 `{"before":"failed","after":"passed","regression":"passed"}`。
2. **INCONCLUSIVE 语义验证**：某 capability 缺真机证据时返回 **3**（非 0/1）。
3. **ENV 语义验证**：缺 wpscli 的机器跑 verify word → 退出码 **127** + 缺失清单（不伪装失败）。
4. **P1 出口**：`verify word` 生成真实 DOCX → OOXML → wpscli word2pdf/pdf2txt → officecli screenshot/issues → JSON 报告。

> 每项 PASS 必须绑定验收层级 + 真实证据（real-runtime-acceptance-harness 纪律：禁止用下游 TestClient/单测替代系统级验收）。

---

## 13. 优先级路线图（修订后）

| 阶段 | 内容 | 出口判据 |
|------|------|---------|
| **P0.1** | Adapter Registry 骨架 + Runtime Bridge（dart runner）+ `contracts/markdown_parser.json` + `verify markdown` | §12.1a 可复现 |
| **P0.2** | Failure Record + diagnostic_id + `diagnose` | §12.1b/c 可复现 |
| **P0.3** | `repair-verify`（before/after/regression） | §12.1d 可复现 |
| P1 | producers + consumers adapter → `verify word/pdf` | §12.4 可复现 |
| P2 | 其余 capability 契约化（formula 模拟器侧 + undo/autosave/file/ime/theme/drag） | 全 capability 有报告 |
| v2 | `ffx device verify`（真机编排，接口已定义）+ Golden 并入 | 另行设计评审 |

---

## 14. 待 Owner 决策（修订后）

1. **是否批准 v0.2 进入 P0 实现**（P0.1 `verify markdown` 打通 Runtime Bridge 闭环）？
2. **ADR-0030 编号**是否可用（0026 预留 Change Impact Analysis）？
3. **contracts/*.json 反转**（机器契约 = 一等公民，矩阵 = 派生投影 + `ffx contract sync` 校验）是否认可？
4. **Runtime Bridge 方案**（`tools/ffx-runtime/` dart capability runner，纯 Dart 先跑 parser/serializer）是否认可？
5. **wpscli/officecli adapter** 纳入 P1 是否认可？
