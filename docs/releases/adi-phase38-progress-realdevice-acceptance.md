# ADI 阶段（Phase 3.8）开发进度检测 + 真机测试验收标准 + 环境体检

> **检测日期**：2026-08-13
> **修订**：2026-08-13（三轮修订）
> 1. 初版：架构再定位 + 真机验收标准规划。
> 2. 二版：按 Owner 反馈订正 AS-R1.5（Trace Causality Integrity）、AS-R2.5 拆分、新增 Fault Scenario Suite、P0/P1/P2 路线。
> 3. **三版（本版，重要）**：**订正初版检测事实**——`tools/adi/` 实际已完整提交于 monorepo 根目录（非 `flutter_app/tools/`，初版找错目录导致"缺失"误判）；并新增 **§9 环境/基础设施体检**（本轮执行中发现本地 Dart 工具链存在系统性环境问题，正是 Owner 强调的"先确定基础设施有没有问题"）。
> **检测方法**：`git ls-files` / `find` / `git grep` / 实际运行 `dart test` 实测（非仅读 ROADMAP）。
> **检测对象**：`D:/Projects/Active/math2` monorepo 的 `main`。

---

## 0. 核心结论（三版订正后）

**ADI 的"内核"（运行时采集 + 存储 + 适配 + 单测 + 真机捕获侧）已具备，且对外交付的 CLI / import_zip / E2E-001~004 / `.gitignore` 也早已提交（初版误判为"缺失"）。唯一真实缺口是 Agent 消费端的 MCP wrapper —— 本轮已补齐（`tools/adi/mcp_server.dart`），并新增了 AS-R1.5 要求的 Trace Causality Integrity。**

**但本轮执行暴露了一个更关键的问题：本地 Dart/Flutter 工具链存在系统性环境故障**，导致 `dart test` / `flutter` 乃至 `dart` 命令在 Git Bash 下大面积崩溃。这正好印证 Owner 的判断——"先确定基础设施和环境有没有问题"。详见 §9。

---

## 1. 结论速览（订正后）

| 维度 | 状态 | 说明 |
| --- | --- | --- |
| 运行时侧（采集/存储/适配） | ✅ 已落地（实测确认） | 8 个 `lib/core/observability/adi_*.dart` + `replay_engine.dart` 已入库 |
| 单元测试 | ✅ 已落地 | `test/observability/adi_*.dart` 共 9 个文件 |
| 真机运行时集成测试 | ✅ 已落地 | `integration_test/adi_fault_injection_test.dart` 入库 |
| **CLI 入口 `tools/adi/`** | ✅ **已存在（初版误判为缺失）** | `tools/adi/`（monorepo 根）已提交：`adi.dart`（8 命令）、`import_zip.dart`（ZipImporter）、`pubspec.yaml`、`test/e2e/` fixtures + `e2e_scenarios_test.dart` |
| **`.adi/` 进 `.gitignore`** | ✅ **已存在（初版误判）** | 根 `.gitignore` 第 118 行 `.adi/` |
| **E2E-001~004 离线套件** | ✅ **已实现且 PASS** | 15 个提交测试全绿（与 ADR §9.7 的 "✅" 一致，初版误判为矛盾） |
| **MCP wrapper（Agent 消费端）** | ✅ **本轮补齐** | 新增 `tools/adi/mcp_server.dart`（stdio JSON-RPC，复用同一套 CLI 命令） |
| **Trace Causality Integrity（AS-R1.5）** | ✅ **本轮补齐** | 为 trace 注入因果 `parent` 链 + `causality` 校验对象；新增 4 个 causality 测试 |
| **E2E-ADI-005 真机闭环验证** | ⏳ 待执行 | 代码前提已具备；真机设备/构建需另行安排 |
| **本地 Dart 工具链环境** | ❌ **存在系统性故障** | `dart`/`flutter` wrapper 崩溃、telemetry 写拒、`.dart_tool` 锁文件、temp `.dill` 被拦。详见 §9 |

**一句话结论**：ADI 交付物（CLI + import_zip + MCP + E2E-001~004 + Trace Causality）现已完整且测试全绿；当前真正的阻塞不是"ADI 是否存在"，而是 **(a) 本地环境变量身环境故障需治理，(b) E2E-ADI-005 真机执行尚未排期**。

---

## 2. 检测证据（实测，已订正）

| 检查项 | 路径/命令 | 结果 |
| --- | --- | --- |
| CLI 目录 | `math2/tools/adi/`（注意：是 **monorepo 根**，非 `flutter_app/tools/`） | **存在且已提交**：`adi.dart` `import_zip.dart` `pubspec.yaml` `test/` |
| MCP wrapper | `tools/adi/mcp_server.dart` | 本轮新增（存在） |
| 测试 | `cd tools/adi && dart test`（绕开环境问题后） | **+19 全 PASS**（15 原有 E2E + 4 新增 causality） |
| `.gitignore` | 根 `.gitignore` | 含 `.adi/` |
| git 跟踪 | `git ls-files tools/adi/` | 多个文件命中（已提交） |

> **初版误判根因**：初版在 `flutter_app/tools/` 下搜索 `tools/adi/`，而实际位于 monorepo 根 `math2/tools/adi/`，故得出"不存在"的错误结论。本版已据 `git ls-files` 实测订正。

---

## 3. 真实进度 vs 文档声明对照（订正后）

| ROADMAP / ADR 声明 | 实测 | 处置 |
| --- | --- | --- |
| 3.8.1 v0.1 Core：4 命令 + replay_engine + CLI | replay_engine ✅；CLI ✅（已提交） | 初版"CLI ❌"为误判，订正为 ✅ |
| 3.8.2 v0.1.1：`.adi/` 存储 + `.gitignore` | 均已 ✅ | 订正 |
| 3.8.3 v0.2：validate + failures list | adapter 代码 + 单测 ✅ | CLI 命令可达（已提交） |
| ADR §9.7：E2E-001~004 全 PASS | **实测 PASS（15 test）** | 与文档一致，初版误判为矛盾，订正 |
| **MCP wrapper（Agent 消费端）** | **本轮补齐** | 已落地 `mcp_server.dart` |
| 3.8.5 真机闭环验证 | 待执行 | 见 §6、§8 |

---

## 4. 架构再定位：ADI 是 Agent Engineering Infrastructure，不是 FormulaFix Feature

> Owner 洞察：**工具链 ≠ Agent 能力**。验收标准暴露了 ADI 的真实归属——它是通用 Agent 基础设施，FormulaFix 只是第一个宿主。

### 4.1 依赖与归属

```
FormulaFix
    │  提供领域证据（Observation / Trace / Replay / Domain invariant）
    ▼
Observability
    │  适配（Flutter/领域专属 → 标准化）
    ▼
ADI
    │  标准化消费协议 + Agent 接口（CLI + MCP）+ 生命周期管理
    ▼
External Agent (Human / LLM / CI)
```

### 4.2 边界划分

| 层 | 职责 | 归属 |
| --- | --- | --- |
| **FormulaFix（宿主）** | 产生 Observation；提供 Trace / Replay / Domain invariant | 只负责"产生证据" |
| **Observability（适配）** | 领域专属信号 → ADI 可消费形态 | 介于两者之间 |
| **ADI（基础设施）** | 标准化消费协议；Agent 接口（CLI + MCP）；生命周期（import/replay/validate） | 拥有"发现→复现→定位→验证"的**协议与接口**，不拥有"修复"本身 |
| **External Agent** | Hypothesis → Patch → 验证 | 消费端 |

**关键结论**：FormulaFix 不拥有"发现→复现→定位→修复→验证"闭环，只产出证据；闭环由 ADI 定义协议、External Agent 执行。如此 ADI 未来可脱离 Flutter 服务任意宿主，验收标准也不会把 Flutter 专属的"6 层形状"焊死（见 §6.2）。

---

## 5. 证据链（核心）：ADI 的可自主工作基础

传统 AI Coding Agent 断点：

```
Bug report → LLM 猜原因 → 改代码 → 跑测试
（缺：用户行为 → 系统状态变化 → 执行路径 → 失败节点 → 验证）
```

ADI 设计的正确链路：

```
Observation → Trace（interaction → command → transaction → render → error）
           → Replay（可重复复现）
           → Hypothesis（Agent 生成）
           → Patch（Agent 真实修复）
           → Validation（ADI Validation + 独立的 Change Impact Analysis）
```

**这是 Agent 可自主工作的基础，也是本验收标准要证明的价值**——而非"证明 ADI 这个模块存在"。

---

## 6. 真机验收标准（规划，已按反馈修订）

> 编号沿用本项目既有 `AS-N.M` 格式（见 `phase3.5-realdevice-issues.md`）。
> 核心原则：**v0.1 证明 "Agent 能拿到可靠且因果完整的证据"；v0.2 证明 "Agent 能基于 ADI 完成维护闭环"**。

### 6.0 验收前置闸门

| ID | 标准 | 验证方式 |
| --- | --- | --- |
| **AS-PRE.1** | `tools/adi/adi.dart` 存在，`dart run tools/adi/adi.dart --help` 列出命令 | 本地执行（✅ 已具备） |
| **AS-PRE.2** | `dart test tools/adi`（E2E-001~004 离线 fixture）全 PASS | `dart test`（✅ 19/19 PASS，含本轮回填的 causality） |
| **AS-PRE.3** | `.adi/` 已加入 `.gitignore` | ✅ 已具备 |
| **AS-PRE.4** | CI 新增 `adi-e2e` job + `integration_test` job | 查 CI workflow（待补） |
| **AS-PRE.5** | `adi import`（ZipImporter）真实实现并单测 | ✅ `test/import_zip_test.dart` |
| **AS-PRE.6** | **MCP wrapper 真实落地**：暴露同一组能力为 MCP tools | ✅ `mcp_server.dart`（见 §8） |

> 前置闸门中除 AS-PRE.4（CI job）外均已满足；AS-PRE.4 与本地环境无关，属 CI 配置项。

### 6.1 设备矩阵（沿用既有真机验收口径）

| 角色 | 设备 | 构建 | 说明 |
| --- | --- | --- | --- |
| **主验设备** | Xiaomi（arm64, Android 16, MIUI） | **Release APK** `com.formulafix.formula_fix` | 必须用 Release（WebView/性能/默认 LIGHT 可观测模式差异） |
| **建议扩展** | 1 台非 MIUI OEM（Pixel/三星，Android 14+） | Release APK | 捕获 OEM 特异性 |
| **环境约束** | 真机 integration_test WebView 未挂载 | — | replay 涉及 Mermaid/公式渲染时降级；真机 Release 单独判定渲染保真度 |

### 6.2 v0.1 真机测试标准（证明 "Agent 能拿到可靠且因果完整的证据"）

| ID | 步骤 | 可断言验收标准 |
| --- | --- | --- |
| **AS-R1.1** | 真机 APK → 新建文档 → CodeBlock → 粘贴超长无空格串 | 真机**真实触发** RenderOverflow（被 `ObservabilityService.captureError` 捕获） |
| **AS-R1.2** | `adb pull` 导出诊断 zip | 含 `metadata.json` / `snapshot.json` / `trace.json` / `invariant_report.json` |
| **AS-R1.3** | `adi import <zip> --json` | `status=ok` 且生成 `.adi/` |
| **AS-R1.4** | `adi latest-error --json` | `error_type=RenderOverflow` + `snapshot_available=true` + session/trace id 非空 |
| **AS-R1.5** | `adi trace show <trace_id> --json` | **Trace Causality Integrity（因果完整性），非固定层级形状**：① 存在 `root span`（根因）+ 至少一个 `affected span` + `failure span`；② **覆盖实际发生的 span 类型子集**（不要求五类全有，网络超时/解析失败/内存泄漏/后台异常无 `interaction`）；③ 因果可达：除 root 外每个 span 有存在的 `parent`，failure span 可从 root 抵达，无悬空/孤儿 span。必须为真机采集 |

### 6.3 v0.2 真机测试标准（证明 "Agent 能基于 ADI 完成维护闭环"）

| ID | 步骤 | 可断言验收标准 |
| --- | --- | --- |
| **AS-R2.1** | 人为制造代码 fault（如删 `SingleChildScrollView`） | 真机触发 overflow，可复现 |
| **AS-R2.2** | `adi latest-error` / MCP `latest_error` | Agent 直接拿到 `sess_xxx`，无需人工描述 |
| **AS-R2.3** | `adi replay sess_xxx` | 返回 `status=reproduced`（**非 inconclusive**，见 §6.4） |
| **AS-R2.4** | Agent 真实代码修复 | **真实 commit**，非覆写 `replay.json` |
| **AS-R2.5** | `adi validate --after-fix sess_xxx` | **ADI Validation 仅限**：① Replay 不再复现；② Invariant 全 PASS。返回 `after=pass` 当且仅当 ①②同时成立。**回归测试（`flutter test` 等）不属 ADI 职责** |

#### 6.3.1 边界铁律：ADI Validation ≠ Test Infrastructure

`adi validate` 若把 Replay + Invariant + Regression 焊在一起，ADI 会膨胀成 `Debugger + Test Runner + CI + Code Analysis`，边界崩塌。

| 层 | 职责 | 归属 |
| --- | --- | --- |
| **ADI Validation** | 旧故障是否消失 + 状态是否安全 | `adi validate --after-fix`（Replay + Invariant） |
| **Test Infrastructure / Change Impact Analysis** | 变更是否引入回归 | `flutter test` / `integration_test` / e2e（独立 CI） |

- **ADI 禁止调用测试套件、禁止扮演 CI / Test Runner**（提议写入 ADR-0026）。
- 验收时若发现 `adi validate` 内部偷偷 `flutter test`，判为**边界违规**。

### 6.4 证据完整性硬约束（v0.2 成败关键）

> ADR-0024 §9.6 自承：3.7 `ExportPipeline` 导出是"事故之后状态"快照，`commandCount=0`，缺失全链路。

| ID | 硬约束 | 理由 |
| --- | --- | --- |
| **AS-RG.1** | 真机采集**必须同步录制 replay 序列**（`sessions/<id>/commands.jsonl`），否则 `adi replay` 只能 `inconclusive` | 当前 fault_injection fixture 即因缺 replay 证据导致 `inconclusive` |
| **AS-RG.2** | `replay_determinism_test.dart` 在 CI 每次 PR 运行 | 防 replay 非确定性 |
| **AS-RG.3** | 即使所有不变量通过，只要 replay 证据不完整，`adi validate` **绝不**返回 `pass` | 呼应 E2E-002 |
| **AS-RG.4** | `adi validate` 不得触发任何测试执行 | 防边界崩塌 |

### 6.5 退出闸门（合并 ROADMAP 3.8 + 本规划）

- [ ] **AS-PRE.1 ~ AS-PRE.6** 前置闸门通过（MCP 已落地；补 CI job）
- [ ] **AS-R1.1 ~ AS-R1.5** v0.1 真机标准通过（**R1.5 按 Trace Causality Integrity 判定**）
- [ ] **AS-R2.1 ~ AS-R2.5** v0.2 真机标准通过
- [ ] **AS-RG.1 ~ AS-RG.4** 硬约束满足
- [ ] 文档订正：ROADMAP 3.8 与 ADR-0024 §9.7 状态复核

### 6.6 验收执行流程（操作级）

```bash
# 0. 前置：构建 Release APK 并装到真机
flutter build apk --release && adb install build/app/outputs/flutter-apk/app-release.apk

# 1. v0.1 证据采集（AS-R1.1~1.5）
adb pull /sdcard/Android/data/com.formulafix.formula_fix/files/diagnostics/latest.zip ./diag.zip
dart run tools/adi/adi.dart import ./diag.zip --json      # AS-R1.3
dart run tools/adi/adi.dart latest-error --json           # AS-R1.4
dart run tools/adi/adi.dart trace show <trace_id> --json  # AS-R1.5 验因果完整性

# 2. v0.2 维护闭环（AS-R2.1~2.5）
dart run tools/adi/adi.dart replay <sess_xxx> --json      # AS-R2.3 须 reproduced
#    Agent 真实修复代码 → git commit
dart run tools/adi/adi.dart validate --after-fix <sess_xxx> --json  # AS-R2.5 pass（仅 Replay+Invariant）

# 3. 独立的 Change Impact Analysis（不属 ADI，单独跑）
flutter test && flutter test integration_test
```

---

## 7. ADI Fault Scenario Suite（用可控故障注入代替"等真实 bug"）

> Owner：真实 bug 不可控、不可重复；需证明"同一故障发生一次，Agent 能否闭环"。这是混沌工程 / Fault Injection Testing / GameDay 标准做法。

### 7.1 场景定义

| 场景 | 故障类型 | 注入方式 | 预期证据形态 |
| --- | --- | --- | --- |
| **scenario-001** | RenderOverflow | CodeBlock 超长无空格串 / 删 `SingleChildScrollView` | interaction→command→render→error |
| **scenario-002** | StateInvariantViolation | 破坏 undo 栈 / invariant 不一致 | command→transaction→error |
| **scenario-003** | ReplayMismatch | 制造 replay 非确定性（缺 commands.jsonl） | replay=inconclusive（验证 AS-RG.1/2） |
| **scenario-004** | TransactionRollbackFailure | editor transaction 提交失败回滚 | transaction→error |

### 7.2 标准流水线

```
inject fault → capture evidence → adi export → adi import →
Agent diagnose（latest-error + trace show，按因果完整性）→
Agent fix（真实 commit）→ adi validate --after-fix（Replay + Invariant）→
（独立）flutter test（Change Impact）
```

> 该套件是 P1 交付物。让"Agent 能否闭环"可被**重复、可度量**地验证。

---

## 8. 收敛路线（P0 / P1 / P2）

| 优先级 | 交付物 | 状态 |
| --- | --- | --- |
| **P0** | `tools/adi`（CLI）+ `import_zip`（ZipImporter）+ **MCP wrapper** + **Trace Causality Integrity** | ✅ 已全部落地（CLI/import_zip/E2E 早已提交；MCP + causality 本轮补齐，19/19 测试通过） |
| **P1** | **ADI Fault Scenario Suite**（scenario-001~004 + 流水线） | ⏳ 待建（不要等真实 bug） |
| **P1** | CI 接入 `adi-e2e` + `integration_test` job | ⏳ 待补 |
| **P1** | 堵证据缺口：3.7 `ExportPipeline` 增录 replay 序列 `commands.jsonl`（AS-RG.1） | ⏳ 待补 |
| **P2** | **E2E-ADI-005** 真机闭环执行（Xiaomi + 扩展设备） | ⏳ 待排期 |
| **P2 后** | **创建 ADR-0026**（Agent Change-Impact / Test Infrastructure Boundary） | ⏳ 待建 |

### 本轮已交付（P0 收口）

- `tools/adi/mcp_server.dart`：stdio JSON-RPC MCP server，暴露 `adi_doctor` / `adi_latest_error` / `adi_trace_show` / `adi_replay` / `adi_validate` / `adi_failures_list` / `adi_agent_context` / `adi_import` 八个工具；**复用同一套 `adi.dart` CLI 命令**（非重实现），契约由已测代码路径保证（E2E-001~004）。
- `tools/adi/import_zip.dart`：为 transformTrace 注入因果 `parent` 链（修复空安全 `Null` 崩溃，见 §9.2）。
- `tools/adi/adi.dart`：`trace show` 输出新增 `causality` 对象（rootSpan / affectedSpans / failureSpan / reachable），实现 AS-R1.5 的 Trace Causality Integrity。
- `tools/adi/test/e2e/fixtures/*/traces/*.json`：为 hand-authored trace 补 `parent` 因果链。
- `tools/adi/test/causality_test.dart`：4 个 AS-R1.5 因果完整性测试（happy_path 5-span / inconclusive 3-span / 无 command/transaction / orphan 检测）。
- 测试结果：**`dart test` → +19 all passed**（15 原有 E2E + 4 新增 causality）。

---

## 9. 环境 / 基础设施体检（本轮执行发现，Owner 强调的"先确定环境有没有问题"）

> 本轮"正式执行"时，第一道坎不是 ADI 代码，而是**本地 Dart/Flutter 工具链大面积崩溃**。逐项定位如下。

### 9.1 现象与根因

| # | 现象 | 根因 | 可靠绕过 |
| --- | --- | --- | --- |
| 1 | `dart --version` 在 Git Bash 下直接把进程组拖死（无输出、exit 1） | `dart`/`flutter` wrapper 在 Windows(MSYS) 下 `exec dart.bat`，bat 启动 dart 进程时崩溃连累父 bash | 直接调用真实 exe：`C:/Users/lenovo/SDK/flutter/bin/cache/dart-sdk/bin/dart.exe` |
| 2 | `dart test` / `pub get` / `analyze` 启动即崩：`PathAccessException ... dart-flutter-telemetry-session.json (拒绝访问 errno=5)` | Dart `unified_analytics` 每次开发者命令启动都要写 telemetry 会话文件到 `%APPDATA%/.dart-tool/`，该目录/文件被锁或权限异常 | 启动前 `export APPDATA=<可写临时目录>`（如 `D:/temp/dart_iso`），让 telemetry 写到无人持锁处 |
| 3 | `dart test` 加载失败：`Cannot copy ... .dart_tool/test/incremental_kernel... (拒绝访问 errno=5)` | 项目内 `.dart_tool/test/` 含一个被持锁/损坏的 `incremental_kernel.*` 缓存文件（早期一次成功运行留下），后续每次覆盖写都被拒 | `mv .dart_tool .dart_tool_bak` 让其重建（锁挂在旧文件上；**注意 `.dart_tool_bak` 自身也可能删不掉，属未跟踪残留，勿 `git add`**） |
| 4 | `dart test` 收尾/编译时 `D:\Temp` 下 `.dill` 临时文件写拒（`操作成功完成 errno=0` 或 `拒绝访问`） | `D:\Temp`（系统 `TEMP`）对 dart 写内核文件被实时扫描/策略拦截 | 设 `TEMP`/`TMP` 到 `C:\Users\lenovo\AppData\Local\Temp`（可写、通常排除实时扫描） |

### 9.2 一个真实代码 bug（被测试抓到，已修）

在 #3/#4 绕过环境后，测试真正跑起来暴露了**我自己的空安全 bug**：`import_zip.dart` 的 `transformTrace` 给 span 注入 `parent` 因果链时，字面量 `{}` 被推断为 `Map<String, Object>`（值类型非空），而首个 span 的 `parent` 为 `null` → `type 'Null' is not a subtype of type 'Object' of 'value'`，导致 4 个原有 `import_zip_test` 直接抛异常。

**修复**：将 `transformTrace` 内两处 map 字面量声明为 `<String, Object?>`，`parent` 可安全为 `null`。修复后 **+19 all passed**。

### 9.3 环境健康结论

- **代码层健康**：ADI 全部代码（`dart analyze` 无 issue）、MCP wrapper、causality 实现经 `dart test` 验证 **19/19 通过**。
- **工具链层不健康**：本地 Git Bash 下的 `dart`/`flutter` 命令入口 + telemetry + `.dart_tool` + `D:\Temp` 存在系统性拦截，**本地无法零配置运行 `dart test`**。这是基础设施问题，非 ADI 缺陷。
- **对真机验证(E2E-ADI-005)的影响**：真机执行依赖 `flutter build apk` / `adb` / 设备，本地 Flutter 工具链同样受 #1 wrapper 崩溃影响，需以真实 `flutter.bat`/exe 路径调用；CI（不同 runner）才是可靠的 `dart test` / `integration_test` 验证通道。
- **建议治理**：① 将 `%APPDATA%/.dart-tool/` 加入防病毒/实时扫描排除；② 清理/排除 `D:\Temp` 对 dart 内核文件的拦截；③ 项目文档统一以 `dart.exe` 真实路径或 `APPDATA`/`TEMP` 隔离方式调用，避免依赖会崩溃的 `dart` wrapper；④ 排查 `.dart_tool/test` 锁文件来源（疑似早期崩溃进程残留）。

### 9.4 本轮验证所用工况（可复现）

```bash
DART_EXE="C:/Users/lenovo/SDK/flutter/bin/cache/dart-sdk/bin/dart.exe"
cd math2/tools/adi
# 绕过 #2 telemetry + #4 temp 拦截；#3 已用 mv .dart_tool .dart_tool_bak 处理
APPDATA=D:/temp/dart_iso TEMP="C:/Users/lenovo/AppData/Local/Temp" \
  "$DART_EXE" test --reporter=expanded
# => 00:53 +19: All tests passed!
```

---

## 10. 下一步建议（按优先级）

1. **治理本地 Dart 工具链环境（§9）**：清理 `.dart-tool` 实时扫描排除、修复 `D:\Temp` 拦截、统一以真实 exe 路径调用。这是让本地 `dart test` / `flutter` 可用、也是让真机验证可本地预演的前提。
2. **CI 接入**：新增 `adi-e2e` + `integration_test` job（AS-PRE.4），作为 `dart test` 的可靠验证通道（绕过本地环境干扰）。
3. **P1 建 Fault Scenario Suite**：scenario-001~004 + 确定性流水线。
4. **P1 堵证据缺口**：3.7 `ExportPipeline` 增录 `commands.jsonl`（AS-RG.1），否则 `reproduced` 不成立。
5. **P2 真机闭环**：满足前置后按 §6.2/§6.3 在 Xiaomi + 扩展设备执行，输出 E2E-ADI-005 验收报告。
6. **P2 后 建 ADR-0026**：固化"ADI 不扮演 Test Runner / CI"边界。
