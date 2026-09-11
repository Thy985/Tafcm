# Tafcm 重考古 · 增量报告（2026-09-03）

> 方法：`knowledge-archaeology` Skill 全流程（Step 1 代码理解清单 12 视角 → Step 2 五问 → Step 3-5 五层阶梯 + Flow → Step 6 Candidates）。
> 目的：用新增的"开源项目代码理解框架"重走 Tafcm，对比已有 44 对象，识别**机器级增量**——之前考古偏重 docs/ADR 层，这次聚焦代码/测试/工具链暴露的认知。
> 范围：只读，未改仓库。补读：FFX orchestration/failure/evidence/consumers、docx_qa、192 测试文件边界、CI workflows、observability 测试资产。

---

## 一、12 视角系统心智模型（Tafcm 怎么运作）

| 视角 | Tafcm 事实 |
|------|-----------|
| 项目定位 | Flutter 块级 WYSIWYG Markdown 数学文档编辑器（应用），公式渲染 + 跨平台导出为核心差异化；同时是一座 Agent 验证工程实验场 |
| 整体架构 | 六层分层（presentation→providers→domain→data→core→main）；两块独立系统：Flutter App + Python 工具链（ffx-cli/adi） |
| 数据流 | .md → MarkdownParser → AST（sealed 块/内联）→ DocumentState → Serializer（round-trip 不动点）；公式走独立 SVG/PNG 渲染链 |
| 核心抽象 | `DocumentElement` sealed 联合（9 块 + 8 inline）；`TextOperation`/`BlockOperation`（source 级往返）；`CapabilityAdapter`（验证）；`Evidence`/`FailureRecord`（证据） |
| 生命周期 | 编辑事务：Committed → Transaction → Live → Commit → History；IME：4 态 6 事件状态机；失败：Record → Triage → Retry → Resolved |
| 调度控制 | 编辑器命令链：Command → Handler._dispatch → Builder → History.push → ops.apply；验证：Agent → Analyzer → Validator → Policy → Action |
| 扩展机制 | **FFX 双层可插拔：adapters/（CapabilityAdapter 领域适配器）+ consumers/（消费端验证器）**；flutter 侧 Provider 注入 |
| 权限安全 | AGENTS.md 权限矩阵；ffx 只读验证（repair-verify 不修码）；`ENV_MISSING` 显式标注工具缺失 |
| 错误可靠性 | 5 态验证退出码（PASS/FAIL/WARN/INCONCLUSIVE/ENV_MISSING）；Failure Record 持久化；故障注入测试资产（run002~006）；Observability（RingBuffer/tracer/error_snapshotter） |
| 测试体系 | 192 测试文件按系统边界组织（parser/editing/observability/architecture/export…）；roundtrip_fuzz 固定 seed；架构守门（file_access_test）；fault_injection 分层 |
| 技术选型 | Flutter（跨端 + WYSIWYG）；Python+Click（工具链生态）；自写 Markdown 解析器（精确控制保真）；sealed class（类型安全 AST） |
| 模块职责 | core 不反向 import；presentation 不直接 I/O（file_access_test 守门）；工具链与 App 通过 ADI 解耦 |

**结论**：Tafcm 不是"一个 Flutter 编辑器 + 一点 Agent 工具"，而是**两块独立系统**：Flutter 编辑器内核（本体）+ FFX/ADI 验证工具链（围绕"如何证明能力成立"建立的第二套系统）。增量认知主要藏在第二套系统的机器实现里。

---

## 二、增量知识对象（N1-N8 · 五层阶梯）

> 与已有 K-012/K-013/K-023（Evidence Strength / Capability Contract / FFX Orchestrator 概念层）相比，N1-N8 是这些概念的**机器级实现细节**——之前没有落到这个粒度。

### N1 · 验证结果的类型化语义（5 态退出码）

- **L1 工程事实**：`_STATUS_EXIT = {"pass": 0, "warn": 2, "fail": 1, "inconclusive": 3}`，另加 `127 = ENV_MISSING`（`tools/ffx-cli/cli_anything/ffx/harness/orchestrator.py`，ADR-0030）
- **L2 工程知识**：为什么需要 INCONCLUSIVE 和 ENV_MISSING——"无法验证"和"环境缺失"不能被误报成通过或失败，二值结论会掩盖验证系统的真实状态
- **L3 工程模式**：验证结果三分法（PASS/FAIL/INCONCLUSIVE）+ 环境缺失显式化。同类：CI 的 flaky/skip、测试的 `xfail`、Benchmark 的 N/A
- **L4 认知模型**：**验证结果必须能表达"不确定"；诚实的不确定性优于虚假的确定性**
- **L5 方法论**：任何验证系统都要有显式的不确定通道（inconclusive / skip / env_missing），禁止用 PASS/FAIL 二值掩盖无法验证或环境缺失

### N2 · Evidence Graph 收集/判定分离

- **L1**：`evidence = (stage, tool, exit_code, artifact, summary, detail)`；文件文档字符串原文：**"FFX 只做证据收集与聚合；判定由 Capability Adapter.evaluate 对照契约完成"**（`harness/evidence.py`）
- **L2**：为什么分离——收集证据的编排器不该同时是判定者（裁判不能既是运动员）；判定必须对照显式契约而非编排器的主观判断
- **L3**：管道式验证：收集 → 聚合 → 判定。同类：CI 只收集日志、测试框架判定；linter 报 warning、规则判定
- **L4**：**证据收集与结论判定分离；判定必须对照显式契约**
- **L5**：验证系统中，收集器（EvidenceGraph）、聚合器（Orchestrator）、判定者（Adapter.evaluate）三层职责分离，判定者必须引用契约

### N3 · Failure Record 真实身份约束

- **L1**：`diagnostic_id` 必须引用真实 Failure Record（ADR-0030 不变量）；ID 双类：`trc_XXXX`（ADI trace 的运行时/链路失败）、`art_XXXX`（FFX artifact 的产物/验证失败）；文件原文：**"禁止仅为报告生成虚拟 ID"**（`harness/failure.py`）；持久化 `.ffx/failures/`，id 用 regex `^(trc|art)_\d{4}$` 校验
- **L2**：为什么——诊断结论必须锚定可回看的失败记录；虚拟 ID 让结论不可审计、不可重放
- **L3**：失败也有持久化身份。同类：bug tracker issue id、分布式链路 trace id、异常 correlation id
- **L4**：**诊断引用必须指向真实可追溯的失败证据**
- **L5**：任何诊断/结论都要引用真实失败对象并持久化，禁止为凑报告生成虚拟引用

### N4 · 证据时效性（G10）

- **L1**：G10（2026-08-20）：每个 PASS/FAIL 携带 `git_sha` + `timestamp`；文件原文：**"禁止『之前跑过所以 PASS』——证据必须携带执行时刻与代码版本"**（`harness/orchestrator.py` `_as_of()`）
- **L2**：为什么——证据过期 = 对旧代码的结论，不能证明当前代码；复用旧结果会掩盖回归
- **L3**：证据带时效属性。同类：CI 缓存失效策略、benchmark 必须带版本号、artifact 校验和
- **L4**：**证据的有效性绑定执行时刻与代码版本**
- **L5**：验证证据必须自带时效属性（谁 / 何时 / 哪个 git SHA），禁止"之前跑过所以 PASS"

### N5 · 消费端验证模式

- **L1**：`harness/consumers/` 三层：officecli（`view screenshot` 视觉捕获）、wpscli（`word2pdf` 真实 Office 兼容转换）、pdfinfo（分页/扫描）；docx_qa 做结构验证（OOXML 5 必需 part 无 dangling）+ 语义验证（段落/标题/列表/表格/公式计数）；消费端缺失 → `ENV_MISSING`（"consumer evidence gap — ENV_MISSING"）
- **L2**：为什么——自证（自己解析自己生成的 docx）不能证明"真实用户能打开"；导出器的正确性由真实消费端最终判定
- **L3**：生产者验证 + 消费端验证双层。同类：供应商测试 vs 客户验收、单元测试 vs 生产环境、模拟器 vs 真机
- **L4**：**产出"给别人消费"的工件，其正确性最终由消费端判定**
- **L5**：凡是产出 docx/pdf 等消费型工件，验证必须含真实消费端打开（Office/WPS/PDF）；消费端缺失时诚实标注证据缺口，而非跳过伪造

### N6 · 能力无关的验证编排 + 领域适配器扩展机制

- **L1**：`orchestrator.py` 一次实现 verify / diagnose / repair-verify 三命令共用；`CapabilityAdapter` 每领域一个（`adapters/`: formula / markdown / word / serializer / assets）
- **L2**：为什么——验证逻辑与领域解耦，新增领域只写 adapter 不碰编排核心
- **L3**：策略/适配器模式在验证领域的实例。同类：K8s 的 controller 框架、VS Code 的 extension API
- **L4**：**验证能力由适配器扩展，编排核心保持稳定**
- **L5**：验证系统设计成"稳定编排核心 + 可插拔领域适配器"；新增能力 = 新增 adapter 而非改核心

### N7 · 故障注入测试资产（fault_injection_run002~006）

- **L1**：`flutter_app/test/observability/fault_injection_run002~006_test.dart` —— 把故障注入做成分层测试资产（run002~006 逐层加深）
- **L2**：为什么——要证明"系统能恢复"，必须先证明"系统会坏"；故障注入是系统性的破坏测试，不是碰运气
- **L3**：故障注入。同类：Chaos Engineering、fault injection testing、Chaos Monkey
- **L4**：**可靠性 = 系统性地注入故障并验证恢复，而非宣称"不会坏"**
- **L5**：生产级系统必须有故障注入资产来验证恢复路径；每层注入（进程/IO/回调/时序）都要有对应恢复断言

### N8 · 测试体系 = 系统边界声明

- **L1**：192 个测试文件按系统边界组织（parser/editing/observability/architecture/export/storage/presentation…）；architecture 目录含 `file_access_test.dart`（presentation 层禁止文件 I/O 守门）、`file_size_test.dart`（400 行守门）、`provider_uniqueness_test.dart`
- **L2**：为什么——测试文件结构本身就是架构边界声明的机器可执行版本；把 AGENTS.md 的分层规则固化为 CI 门禁
- **L3**：测试即边界 / 架构测试。同类：contract test、dependency-cruiser 分层检查
- **L4**：**系统边界通过可执行的架构测试守门**
- **L5**：把分层/大小/唯一性等规则写成架构测试，进 CI，让"规范"从文档变为机器强制

---

## 三、重复结构确认（增量 → 已有原则）

8 个增量对象全部落入已有 `产生→验证→授权→执行→记录` 指纹，并强化了对应原则：

| 增量 | 落入环节 | 强化原则 |
|------|---------|---------|
| N2 收集/判定分离 | 验证环节（收集者≠判定者） | **P5 验证独立于执行** 的机器级实现 |
| N5 消费端验证 | 验证环节（生产者≠判定者） | **P5** 的跨系统扩展 |
| N3 Failure Record | 记录环节（失败也要可追溯身份） | **P1 声明≠证据**（诊断必须引用真实失败） |
| N4 证据时效性 | 记录环节（证据带版本+时刻） | **P1** 的时效维度 |
| N6 适配器扩展 | 授权/执行边界（核心稳定，领域可插拔） | **P2 稳定核心≠可变领域** |
| N1 类型化结果 | 验证环节（诚实的不确定性） | P1 的诚实性维度 |
| N7 故障注入 | 验证环节（恢复需可证明） | 可靠性原则（新增：恢复=系统性注入+断言） |
| N8 测试即边界 | 授权环节（规则机器化） | 治理原则（规范从文档变为门禁） |

**结论**：Tafcm 的架构指纹不是巧合。验证系统的每一层实现（收集/判定/持久化/时效/消费端）都在重复同一个结构——**"谁产生、谁验证、谁判定、谁执行、谁记录"严格分离**。这进一步印证 P1/P2/P5 是从系统结构归纳的，不是想出来的。

---

## 四、新增 Candidates

### C-014 · 验证结果类型化语义的普适性
- **Hypothesis**：任何生产级验证系统都应采用"三值+环境缺失"的结果语义（PASS/FAIL/INCONCLUSIVE/ENV_MISSING），二值掩盖不确定
- **Current Evidence**：Tafcm 一个系统（S4 测试验证 + S5 运行验证）
- **Missing**：其他 CI/验证系统的独立复现
- **Validation**：检查 FormulaFix 的 CI、其他开源 CI 工具是否有显式 inconclusive 通道
- **Potential**：Verification / CI Engineering

### C-015 · 消费端验证作为导出器正确性的最终判据
- **Hypothesis**：导出类功能（docx/pdf）的验证必须包含真实消费端打开，自证不可信
- **Current Evidence**：Tafcm 三层消费端（officecli/wpscli/pdfinfo）+ docx_qa 双验（结构+语义）
- **Missing**：其他导出项目（报告生成器、Office 文档库）是否也做消费端验证
- **Validation**：用任意 docx 生成库 + 真实 WPS 打开做对照实验
- **Potential**：Export Engineering / Compatibility

### C-016 · 失败记录应有持久化身份（trc/art 双类）
- **Hypothesis**：失败对象需要持久化 ID 且区分来源（运行时 trace vs 产物验证），诊断必须引用真实记录
- **Current Evidence**：ADR-0030 不变量 + `_ID_RE` 校验（S4）
- **Missing**：跨项目验证（其他诊断系统是否强制真实引用）
- **Validation**：对比开源 diagnostic/triage 系统的失败身份设计
- **Potential**：Diagnostics / Agent Engineering

---

## 五、对照已有 44 对象

**强化（已存在，本次补机器级实现）**：K-012（Evidence Strength）← N1/N4；K-013（Capability Contract）← N2/N6；K-023（FFX Orchestrator）← N2/N3/N4/N5/N6；K-004（Observability）← N7。

**新增（44 对象未覆盖）**：N1（类型化结果）、N3（Failure Record 真实身份）、N4（证据时效性 G10）、N5（消费端验证）、N6（稳定核心+领域适配器）、N7（故障注入资产）、N8（测试即边界）。

**按五问自检**：
- N5 若 Tafcm 消失仍有价值？是——"导出正确性由消费端判定"是跨项目知识 → 知识对象
- 能否改变未来决策？是（N1/N4/N5 直接指导验证系统设计）→ 高价值
- "我认为"还是"项目证据"？全部锚定代码原文/ADR → 证据支撑
- 会否在另一项目再现？是（导出器/CI/诊断系统）→ Cross-project Candidates C-014~016
- 偶然还是结构？N2/N4/N5 是同一"验证独立"结构的多个侧面 → 结构性

---

## 六、认知状态与价值分级

| 对象 | 层级 | 价值 | 证据 | 认知状态 |
|------|------|------|------|---------|
| N5 消费端验证 | L4 | A | S4+S5 | Validated Pattern（Tafcm-originated） |
| N2 收集/判定分离 | L4 | A | S4+S5 | Validated Pattern |
| N3 失败真实身份 | L4 | A | S4（代码+ADR 不变量） | Validated Pattern |
| N4 证据时效性 | L4 | A | S5（G10 已上线） | Validated Pattern |
| N1 类型化结果 | L3 | B | S4 | Validated Pattern |
| N6 适配器扩展 | L3 | B | S4 | Validated Pattern |
| N7 故障注入资产 | L3 | B | S4（测试资产） | Validated Pattern |
| N8 测试即边界 | L3 | B | S4（架构测试守门） | Validated Pattern |

## 七、Most Important Finding

> 这次重考古最关键的收获：Tafcm 的验证系统不是"为 Agent 造的工具"，而是一套**独立于 Agent 的、机器强制的证据生产机器**。它的每一层——收集/判定分离、失败持久化、证据时效、消费端验证、故障注入——都在回答同一个问题：**"如何让'功能成立'这个声明变得可审计、可重放、不可伪造？"** 这比"Agent 需要验证"高一个层次：它是一套把"信任"工程化的具体机制。而且这些机制（N1-N8）大多藏在工具链代码里而不是 docs 里——这正是当初"只读 ADR 会漏掉的东西"。
