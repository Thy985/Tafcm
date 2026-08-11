# ADR-0024：Agent Diagnostic Interface（Agent 诊断接口）

- **状态**：Accepted（Human Owner 签字 2026-08-10）
- **日期**：2026-08-10
- **决策者**：Human Owner
- **关联**：[ADR-0023 Editor Observability System](./0023-editor-observability-system.md)（直接前置，已完成） / [ADR-0022 Renderer Failure Policy](./0022-renderer-failure-policy.md) / [ADR-0008 Editor Transaction Model](./0008-editor-transaction-model.md) / [ROADMAP.md](../ROADMAP.md) / [ADI Design Document v1.0](../design/adi-design-v1.md)

> **定位声明**
>
> ADI 不是"调试工具"，是 **Agent Runtime Interface**。
>
> 核心问题不是"提供几个接口让 Agent 调用"，而是：
>
> > 如何让 Agent 从 Observation 出发，自主完成 **发现 → 复现 → 定位 → 修复 → 验证** 闭环。
>
> ADI 建立在已完成的 Phase 3.7（ADR-0023）之上，**复用而非重采**——3.7 采集证据，ADI 消费证据并暴露诊断协议给 AI Agent。

> **文档职责分离**
>
> | 文档 | 职责 | 内容 |
> |------|------|------|
> | **本 ADR-0024** | **为什么**这么设计 | Context / Decision / Architecture / Consequences / Alternatives / Exit Criteria |
> | [ADI Design Document v1.0](../design/adi-design-v1.md) | **怎么**实现 | 完整接口签名 / 目录结构 / CLI 命令细节 / 存储格式 / 代码模型 |
>
> 本 ADR §2 保留架构决策性的设计理由与核心模型定义（决策依据），完整实现细节（接口签名、目录结构、CLI 命令表）见 design doc。两文档保持同步：ADR 决策变更 → design doc 跟新实现。

---

## 0. 背景

### 0.1 当前状态

Phase 3.7（Editor Observability System，ADR-0023）已于 2026-08-03 全部完成，提供了完整的证据采集能力：

| 3.7 已有能力 | 实现位置 | 当前消费者 |
|------------|---------|-----------|
| `EditorTraceContext`（跨层 traceId/spanId/parentSpanId） | `lib/core/observability/trace_context.dart:15-48` | 内部 |
| `CommandTracer` / `TransactionTracer` / `InteractionTracer` / `RenderTracer` | `lib/core/observability/*.dart` | 内部 |
| `InvariantChecker`（5 项核心不变量） | `lib/core/observability/invariant_checker.dart` | 内部 |
| `ObservabilityService`（统一 Facade） | `lib/core/observability/observability_service.dart:29-80` | 内部 |
| `ErrorSnapshotter` + `ErrorSnapshot`（结构化 JSON） | `lib/core/observability/error_snapshot*.dart` | 内部 |
| `ExportPipeline`（诊断 zip） | `lib/core/observability/export_pipeline.dart` | 人工导出 |
| `CommandReplayer`（确定性重放，14 类 Command） | `lib/presentation/observability/command_replayer.dart` | 内部测试 |
| `analyze.py`（离线分析脚本） | `tools/ffx-analyze/analyze.py` | 人工 `python` |

### 0.2 核心矛盾

3.7 解决了"**证据采集**"，但没有解决"**证据消费**"——尤其是被 AI Agent 直接消费。

当前 AI Agent（Claude Code / Codex / Cursor）调试 FormulaFix 的实际流程：

```
用户发现 Bug
    ↓
人工导出日志/截图/视频（ExportPipeline 生成 zip）
    ↓
压缩上传
    ↓
Agent 阅读 zip
    ↓
人工描述复现步骤
    ↓
Agent 修改代码
    ↓
人工验证
```

存在问题：

- **信息丢失**：zip 是事后快照，缺因果链的 Agent 可读视图
- **复现困难**：Agent 拿到 zip 后仍需人工描述复现路径
- **状态上下文缺失**：`ErrorSnapshot` 有结构，但 Agent 无法查询"最近一次失败"等聚合视图
- **Trace 与代码无法关联**：`traceId` / `spanId` 存在但无反向映射到源码位置
- **修复无法自动验证**：Agent 改完代码后，无法自动 replay + invariant 验证闭环
- **人工依赖重**：每一步都需要 Human Owner 介入（导出、描述、验证）

### 0.3 触发本 ADR 的事件

1. **AI Agent 协作成为主流调试方式**：AGENTS.md §9 已定义完整的 AI 协作工作流，但 Agent 缺乏直接消费运行时证据的协议接口，导致"理解软件运行状态"这一步仍依赖人工。
2. **3.7 能力未被充分暴露**：`ObservabilityService` 的 RingBuffer、`CommandReplayer` 的重放能力、`InvariantChecker` 的验证能力都已建成，但仅服务于内部和 `analyze.py`，未标准化暴露给 Agent。
3. **zip 导出流程对 Agent 不友好**：`ExportPipeline` 生成 zip 需解压、需 `analyze.py` 二次解析，Agent 无法增量查询，无法直接 `adi latest-error` 式即时获取。

---

## 1. 决策

**新增 Agent Diagnostic Interface（ADI），作为 Agent Runtime Interface，复用 Phase 3.7 已建成的全部采集能力，标准化暴露为 AI Agent 可直接消费的诊断协议。ADI 不重新采集证据，仅做协议封装 + 存储适配 + CLI 入口。**

### 1.1 整体架构

```
                    AI Agent
          (Claude Code / Codex / Cursor)
                    |
                    |
              ADI Protocol  ← 本 ADR 边界
                    |
        ┌───────────┴───────────┐
        │                       │
  Observation API          Action API
   (只读查询)             (replay/validate)
        │                       │
        ↓                       ↓
  ┌─────────────────────────────────────┐
  │      ADI Adapter Layer (新增)        │
  │  ┌──────────┐  ┌──────────────────┐  │
  │  │ Query    │  │ Replay Adapter   │  │
  │  │ Adapter  │  │ (wrap Replayer)  │  │
  │  └──────────┘  └──────────────────┘  │
  └─────────────────────────────────────┘
        │                       │
        ↓                       ↓
  ┌─────────────────────────────────────┐
  │   Phase 3.7 Observability (已建成)   │
  │  ObservabilityService               │
  │  ErrorSnapshotter                   │
  │  CommandReplayer                    │
  │  InvariantChecker                   │
  └─────────────────────────────────────┘
        │                       │
        ↓                       ↓
  .adi/ Storage            Test Harness
  (取代 zip)              (flutter test)
```

### 1.2 设计原则

| 原则 | 含义 | 约束来源 |
|------|------|---------|
| **复用非重采** | ADI 不重新实现 Tracer / Snapshotter / Replayer，全部复用 3.7 | ADR-0023 已建成 |
| **Agent Native** | 输出格式面向 Agent 消费（结构化 JSON / Markdown），非面向人类阅读 | 本 ADR 定位 |
| **零侵入** | ADI 不修改 3.7 任何 public API，仅通过构造注入 / 适配器模式接入 | ADR-0023 §4.3 先例 |
| **自研无第三方** | 不引入 Sentry / OpenTelemetry / HTTP server 框架等第三方依赖 | ADR-0023 §5.1 决策延续 |
| **隐私延续** | LIGHT 模式不写文档正文，遵循 ADR-0023 的 `ObservabilityLevel` 三级模式 | ADR-0023 §3.3 |
| **架构守门合规** | 新增代码通过现有 21 个 `test/architecture/` 守门 | AGENTS.md §6.1 + §11.2 |

### 1.3 与 ADR-0023 的分工

```
ADR-0023 Observability System (已完成)
  职责：采集证据
  产出：ErrorSnapshot / Trace / InvariantReport / Replay 能力
        ↓
   Observation Store (.adi/)
        ↓
ADR-0024 ADI (本决策)
  职责：消费证据 + 暴露诊断协议给 Agent
  产出：CLI / Query API / Replay API / Validation API / Agent Context
        ↓
    AI Agent
```

### 1.4 ADI Core Principles（ADI 核心原则）

> ADI 提供能力不等于保证 Agent 正确使用。本节是 ADI 协议的**核心原则**，不是附属章节。
> 类比：LSP 提供补全能力，但 IDE 仍需遵守"光标在哪才请求补全"的契约。ADI + Core Principles = 完整的 Agent 诊断协议。
> 这 6 条原则定义了从 "LLM coding" 进入 "Engineering Agent" 的行为边界。

**Agent 使用 ADI 时 MUST 遵守**：

```
1. Query first          — 先 adi latest-error --json 获取 Observation，不凭空假设
2. Inspect before edit  — 改代码前先 adi trace show <id> 理解因果链
3. Replay before modify — 改代码前先 adi replay <id> 确认能复现（不能复现的 bug 不应修）
4. Validate after modify — 改完代码后 adi validate --after-fix 验证闭环
5. Never trust candidate_causes as truth — candidate_causes 是假设非结论，修复决策需 Agent 推理
6. Respect invariant report — invariant_report.violated 非空 = 状态损坏（真 bug）；全通过 = 渲染降级或既定行为（ADR-0022）
```

**强制方式**：

| 条款 | 强制机制 |
|------|---------|
| 1-4（操作顺序） | `adi agent-context` 输出的 `next_actions` 引导；AGENTS.md §9.2 Task Contract 要求 Agent 填写改动前理解 |
| 5（不信任假设） | `AdiView.candidateCauses` 标注 `"confidence": "hypothesis"`；`agent-context` Markdown 标 "Suggested" / "Hypothesis" |
| 6（invariant 语义） | `AdiInvariantView` 含 `violated` + `checked` 双字段 + 语义说明 |

**落地**：ADI Accepted 后，建议 Human Owner 在 `AGENTS.md` §9 增加引用：

```markdown
### 9.5 ADI 诊断工作流（引用 ADR-0024 §1.4）

AI Agent 调试 FormulaFix 时，若使用 ADI，MUST 遵守 ADR-0024 §1.4 ADI Core Principles。
```

---

## 2. 详细设计

> **本节聚焦架构决策性设计理由与核心模型定义**。完整接口签名、目录结构、CLI 命令表、存储格式等实现细节见 [ADI Design Document v1.0](../design/adi-design-v1.md) §5-§7。本 ADR 与 design doc 保持同步。

### 2.1 ADI Protocol（三层模型分离）

**目标**：定义 Agent 可消费的结构化数据模型，映射 3.7 的内部模型。

**核心设计**：三层职责分离，避免单一模型同时承担 runtime event / persistence schema / Agent view model 三个职责导致演进时互相污染。

```
Layer 1: ErrorSnapshot        (3.7 已有，runtime event，不改动)
    ↓ toRecord()
Layer 2: AdiRecord            (新增，.adi/ 持久化 schema，稳定)
    ↓ toView()
Layer 3: AdiView              (新增，Agent 消费视图，可随 Agent 需求演进)
```

**Layer 1：ErrorSnapshot（3.7 已有，复用）**

`lib/core/observability/error_snapshot.dart` 已定义，是 runtime 事件模型。ADI 不修改。

**Layer 2：AdiRecord（持久化 schema，稳定）**

`.adi/` 存储格式，字段集应保持稳定（变更需 schema_version 升级，见 §2.6）：

```dart
/// .adi/ 持久化记录。字段集稳定，变更需 schema_version 升级。
sealed class AdiRecord {
  String get id;
  DateTime get time;
  String get sessionId;
  String get traceId;
  Map<String, Object?> toJson();
}

class AdiErrorRecord extends AdiRecord {
  @override
  final String id;            // obs_001
  @override
  final DateTime time;
  @override
  final String sessionId;     // sess_9e0b
  @override
  final String traceId;       // trc_0219
  final String source;        // Android / iOS / Web
  final String errorType;
  final String message;
  final String? stackHash;
  // 注意：不含 Agent 视图字段（如 candidate_causes / diagnosis_probability）
}

class AdiInvariantRecord extends AdiRecord { ... }
```

**Failure Identity（故障聚合）**：

单个 `AdiErrorRecord` 是一次 occurrence。同一 bug 发生 100 次会产生 100 个 record，Agent 无法知道它们是同一类问题。引入 `AdiFailureRecord` 聚合同一 failure 的多次 occurrence：

```dart
/// 故障聚合记录。同一 bug 的多次 occurrence 归为同一 failure_id。
class AdiFailureRecord {
  final String failureId;           // f_20260810_001（基于 errorType + stackHash 去重）
  final DateTime firstSeen;
  DateTime lastSeen;
  int occurrences;                  // 发生次数
  final String errorType;
  final String? stackHash;          // 去重键：errorType + stackHash
  final List<String> traceIds;      // 关联的 trace 列表
  final List<String> sessionIds;    // 关联的 session 列表
  AdiFailureStatus status;          // open / fixed / recurring
}

enum AdiFailureStatus { open, fixed, recurring }
```

**去重键**：`failureId = hash(errorType + stackHash)`。相同 errorType + 相同 stack trace hash → 同一 failure，`occurrences++`，`lastSeen` 更新。不同 stack hash → 新 failure。

**Agent 消费价值**：Agent 查询 `adi failures list` 时看到的是聚合后的 failure 列表（"TaskList renderer fallback × 47 次"），而非 47 条独立 observation。这让 Agent 能判断"高频 recurring bug" vs "偶发新 bug"。

**Layer 3：AdiView（Agent 消费视图，可演进）**

Agent 实际消费的模型，可随 Agent 能力演进增加字段（如 `candidate_causes` / `diagnosis_probability` / `related_commit`），**不污染存储 schema**：

```dart
/// Agent 消费视图。可自由演进，不持久化，由 AdiRecord 投影生成。
sealed class AdiView {
  String get id;
  String get traceId;
}

class AdiErrorView extends AdiView {
  @override
  final String id;
  @override
  final String traceId;
  final String errorType;
  final String message;
  final bool replayAvailable;
  final String? snapshotPath;
  final AdiObservationQuality quality;            // 证据完整度（LIGHT 模式可能 partial）
  // 演进字段（v0.2+ 可加，不影响存储）：
  final List<AdiHypothesis> hypotheses;            // v0.1 可为空
  final double? diagnosisProbability;              // v0.3 可加
}

/// 显式假设管理。Agent 不应把 hypothesis 当 fact。
class AdiHypothesis {
  final String file;
  final int line;
  final String reason;
  final String confidence;    // 永远是 "hypothesis"，不是 "fact"
  final bool verified;        // Agent 验证后置 true
}

/// 证据完整度。Agent 需知道"我看到的信息是否足够"。
enum AdiObservationQuality {
  complete,   // FULL 模式：全部数据
  partial,    // LIGHT 模式：缺 render data / document content
  degraded,   // 数据损坏或截断
}
```

**投影关系**：

```dart
AdiErrorView toView(AdiErrorRecord record, AdiContext context) {
  return AdiErrorView(
    id: record.id,
    traceId: record.traceId,
    errorType: record.errorType,
    message: record.message,
    replayAvailable: context.hasReplayData(record.sessionId),
    snapshotPath: context.snapshotPath(record.id),
    candidateCauses: context.locateCandidates(record),  // v0.1 可返回空
  );
}
```

**设计理由**：
1. **存储稳定性**：`AdiRecord` 字段集稳定，`.adi/` 旧数据可跨版本读取（配合 §2.6 schema_version）
2. **视图可演进**：`AdiView` 可随 Agent 能力增加 `diagnosis_probability` / `related_commit` 等字段，不触发存储迁移
3. **sealed class**：符合 AGENTS.md §2.2 鼓励的现代 Dart 特性（已在 `document.dart` 的 `DocumentElement` 落地）

### 2.2 Query Adapter（查询适配）

**目标**：把 `ObservabilityService` 的内部能力包装为 Agent 可查询的协议接口。

**后端依据**：`ObservabilityService` 已持有 `_lastInvariantReport` 和 `ErrorSnapshotter` 缓冲区（`observability_service.dart:29-80`）。

**接口**：

```dart
abstract class AdiQueryAdapter {
  /// 获取最近一次错误（对应 CLI: adi latest-error）。返回 Agent 视图。
  AdiErrorView? latestError();

  /// 获取完整现场（对应 CLI: adi trace show <id>）。
  AdiTraceView traceView(String traceId);

  /// 列出最近 N 次失败（对应 CLI: adi failures list）。
  List<AdiErrorView> recentFailures({int limit = 20});
}

class AdiQueryAdapterImpl implements AdiQueryAdapter {
  final ObservabilityService _service;
  final AdiStorage _storage;

  AdiQueryAdapterImpl(this._service, this._storage);

  @override
  AdiErrorView? latestError() {
    // 优先从 ObservabilityService 内存缓冲区取（实时）
    final snapshot = _service.latestErrorSnapshot();
    if (snapshot != null) return _toView(snapshot.toRecord(), _context);
    // 回退到 .adi/ 持久化存储（跨 session）
    final record = _storage.latestErrorRecord();
    return record != null ? _toView(record, _context) : null;
  }
}
```

**注意**：`AdiQueryAdapter` 返回 `AdiView`（Layer 3），通过 `toView(record, context)` 从 `AdiRecord`（Layer 2）投影生成。存储层（`AdiStorage`）只返回 `AdiRecord`，视图投影在 Query Adapter 层完成（见 §2.1 三层分离）。

**设计理由**：双源查询（内存实时 + 磁盘跨 session），让 Agent 既能查当前 session 的实时错误，又能查历史 session 的归档错误。

### 2.3 Replay Adapter（重放适配）

**目标**：把 `CommandReplayer` 包装为 Agent 可调用的 Replay 协议。

**后端依据**：`CommandReplayer` 已实现 14 类 Command 的序列化/反序列化与确定性重放（`command_replayer.dart`），`replay_determinism_test.dart` 守门。

**接口**：

```dart
abstract class AdiReplayAdapter {
  /// 重放指定 session（对应 CLI: adi replay <id>）。
  AdiReplayResult replay(String sessionId);
}

class AdiReplayResult {
  final AdiReplayStatus status;       // reproduced / notReproduced / inconclusive
  final String? failedAt;             // lib/presentation/blocks/block_renderer.dart:62
  final int commandsExecuted;
  final String resultTraceId;         // trc_replay_001
  final List<AdiReplayStep> steps;    // 每步结果
}
```

**架构守门注意**：`CommandReplayer` 当前位于 `lib/presentation/observability/`。ADI Replay Adapter 属于 `core/` 层，禁止 import `presentation/`（`layer_dependency_test.dart` 守门）。

**解决方案（Extract 而非 Move）**：从现有 `CommandReplayer` 中 **Extract** 核心重放能力到新文件 `lib/core/replay/replay_engine.dart`（独立子目录，非 `core/observability/`），`presentation/observability/command_replayer.dart` **保持原位**并改为调用 `replay_engine`。

```
core/replay/replay_engine.dart              ← 新增：Extract 出的核心重放引擎
presentation/observability/command_replayer.dart  ← 保持原位，改为委托 replay_engine
```

**ReplayEngine 依赖契约**：

> ReplayEngine **only depends on deterministic command execution contract**, not UI rendering implementation.

Replay 本身不是纯 `core/observability`——它依赖 Command / Document State，但不依赖 Renderer / Widget。因此放在独立子目录 `core/replay/`，与 observability 采集层分离。依赖边界：

```
core/replay/replay_engine.dart
  ✅ depends on: core/editing/ (Command, BlockEditorState, Transaction)
  ✅ depends on: core/observability/ (CommandTraceEntry, 读取 replay 数据)
  ❌ does NOT depend on: presentation/ (Widget, Renderer)
  ❌ does NOT depend on: domain/ (业务服务)
```

此契约由 `layer_dependency_test.dart` 守门。若未来 replay_engine 偷偷依赖 editor domain 或 presentation，守门测试会失败。

**为何 Extract 而非 Move**：
- Move（整体搬迁）会导致 import 大面积变化 + git history 丢失 + regression 风险
- Extract（抽取核心能力）保持 `command_replayer.dart` 原位，仅将其核心逻辑委托给 `replay_engine`，`presentation/` 层保留 UI 集成职责
- 符合"最小改动"原则（AGENTS.md §9.1）：能抽不改搬

此重构属于本 ADR 范围，需保证 0 业务行为变化（AGENTS.md §6.3），由现有 `replay_determinism_test.dart` 守门。

### 2.4 Validation Adapter（验证适配）

**目标**：Agent 修复代码后，自动验证闭环（replay + invariant + tests）。

**后端依据**：`CommandReplayer`（replay）+ `InvariantChecker`（5 项不变量）+ `flutter test`（测试）。

**接口**：

```dart
abstract class AdiValidationAdapter {
  /// 修复后验证（对应 CLI: adi validate --after-fix）。
  AdiValidationResult validate({required String sessionId});
}

class AdiValidationResult {
  final String before;               // "crash" / "fallback" / "invariant_violation"
  final String after;                // "pass" / "still_failing"
  final AdiReplayResult replayResult;
  final AdiTestSummary tests;        // {run: 12, passed: 12, failed: 0}
  final AdiInvariantSummary invariants;  // {violated: []}
}
```

**执行流程（分阶段）**：

v0.2（replay + invariant，不含 test）：

```
Replay (原 session，验证不再复现)
    ↓
Invariant Check (5 项，验证全部通过)
    ↓
Result
```

v0.3（Change Impact Analysis + test 子集）→ **拆为独立 ADR-0026**：

Change Impact Analysis（`git diff` → 依赖图反向查询 → test 子集选择 → `flutter test` 子集）是一个独立系统，涉及 Dependency Graph / Static Analysis / Test Selection / CI Optimization，不属于 ADI Core Protocol 范围。本 ADR-0024 只交付 v0.2（replay + invariant 验证闭环），Change Impact Analysis 留待 **未来 ADR-0026** 独立设计。

**优先级**：P1（v0.2 实现 replay + invariant，本 ADR）；P2（Change Impact Analysis + test 子集，**ADR-0026**）。

### 2.5 Agent Context Generator（上下文生成）

**目标**：生成 Agent 可直接消费的 Markdown 上下文，升级现有 `analyze.py` 的输出。

**后端依据**：`tools/ffx-analyze/analyze.py` 已实现 Timeline + Root Cause Analysis + Recommendation 生成逻辑。

**接口**：

```dart
abstract class AdiContextGenerator {
  /// 生成 Agent 上下文（对应 CLI: adi agent-context）。
  String generateAgentContext();
}
```

**输出示例**：

```markdown
# Current Software State

## Last failure
TaskListItem renderer fallback (non-crash degradation)

## Reproduction
1. Open markdown document
2. Enter "- [ ]" at line start
3. Observe FallbackBlockRenderer instead of dedicated TaskList renderer

## Evidence
- trace_id: trc_0219
- session_id: sess_9e0b
- snapshot: .adi/observations/obs_001.json

## Suspected location
- lib/presentation/blocks/block_renderer.dart:62
  (exhaustive switch routes TaskListItemElement to FallbackBlockRenderer per ADR-0022)

## Invariant status
All 5 invariants satisfied (this is a rendering degradation, not a state corruption)

## Suggested next action
- Confirm: `adi replay sess_9e0b`
- Inspect: `adi trace show trc_0219`
```

**设计理由**：给 Agent **Observation + Context + Hypothesis**，不给确定答案。`candidate_causes` 是假设而非结论，修复决策仍需 Agent 推理（符合 AGENTS.md §9.2 Task Contract 要求）。

**与 ADR-0022 的协同**：`TaskListItemElement → FallbackBlockRenderer` 是 ADR-0022 既定的渲染降级，**不是 bug**。ADI 通过 `invariant_report.violated` 让 Agent 区分"既定 fallback"（invariant 全通过）与"意外 crash"（invariant 违反）。

### 2.6 ADI Storage（.adi/ 存储取代 zip）

**目标**：用结构化目录取代 `ExportPipeline` 的 zip，让 Agent 可增量查询、无需解压。

**目录结构**：

```
.adi/
├── schema_version.json          (ADI schema 版本，支持跨版本兼容读取)
├── observations/
│   ├── obs_001.json
│   ├── obs_002.json
│   └── obs_003.json
├── sessions/
│   └── sess_9e0b/
│       ├── commands.jsonl       (CommandTracer 导出)
│       ├── transactions.jsonl   (TransactionTracer 导出)
│       ├── interactions.jsonl   (InteractionTracer 导出)
│       ├── renders.jsonl        (RenderTracer 导出)
│       ├── snapshot.json        (ErrorSnapshot)
│       ├── environment.json
│       └── replay.json          (replay 结果缓存)
├── traces/
│   └── trc_0219.json            (跨层 span 树)
├── replay/
│   └── replay_001.json          (replay 执行记录)
└── index.json                   (v0.1 JSON 索引；v0.2 评估 SQLite)
```

**Schema Versioning**：

`schema_version.json` 内容：

```json
{
  "adi_version": "0.1",
  "schema_version": 1,
  "created_at": "2026-08-10T13:00:00Z"
}
```

**为何需要 schema version**：ADI 工具会演进，`AdiRecord` 字段集变更时 `schema_version` 升级。CLI 读取 `.adi/` 时先检查 `schema_version`，旧版本数据走迁移路径或降级读取，避免半年后旧 session 无法解析。配合 §2.1 三层模型——`AdiRecord`（存储 schema 稳定）与 `AdiView`（Agent 视图可演进）分离，schema_version 仅约束 `AdiRecord`。

**接口**：

```dart
abstract class AdiStorage {
  /// 写入 Record（allowlist 入口，通过 file_access_test.dart TC-ARCH-2 守门）。
  void writeRecord(AdiRecord record);

  /// 查询最近错误记录（返回 Record，View 由 Query Adapter 投影生成）。
  AdiErrorRecord? latestErrorRecord();

  /// 查询指定 trace 的完整现场记录。
  AdiTraceRecord loadTrace(String traceId);

  /// 加载 session 的 command 序列（供 Replay Adapter 使用）。
  List<CommandTraceEntry> loadSessionCommands(String sessionId);

  /// 读取 schema_version，校验兼容性。
  int readSchemaVersion();
}
```

**注意**：`AdiStorage` 只读写 `AdiRecord`（Layer 2 持久化层），不返回 `AdiView`（Layer 3 视图层）。`AdiView` 由 `AdiQueryAdapter` 通过 `toView(record, context)` 投影生成（见 §2.1 / §2.2）。这保证存储层不依赖视图层。

**与现有 `ExportPipeline` 的关系**：

| 维度 | 现有 zip | ADI .adi/ |
|------|---------|-----------|
| 消费者 | 人工下载 + 解压 + analyze.py | Agent 直接读 |
| 查询 | 全量扫描 | index.json 索引 |
| 增量 | 每次全量打包 | 追加写入 |
| Replay | 需手工导入 session | 直接 `adi replay <id>` |

**迁移策略**：v0.1 保留 `ExportPipeline` 作为"人工导出兜底"，`.adi/` 作为"Agent 原生消费"主路径。v0.2 评估是否废弃 zip。

**清理策略（.adi/ 生命周期）**：

| 配额项 | 默认值 | 超额处理 |
|--------|--------|---------|
| `max_sessions` | 20 | 清理最旧 session 目录 |
| `max_storage_size` | 500 MB | 按 LRU 清理最旧 observations + sessions |
| `max_single_snapshot` | 5 MB | 截断 render log / 不截断 error metadata |

清理在 `AdiStorage.writeRecord()` 后异步触发（非写入关键路径），避免影响采集性能。

**Crash-safe write（诊断系统自身不能丢诊断）**：

`.adi/` 写入采用 atomic rename 模式，避免 crash 时写出半截文件：

```
write record
    ↓
write to temp file (obs_001.json.tmp)
    ↓
fsync (确保落盘)
    ↓
rename atomic (obs_001.json.tmp → obs_001.json)
```

`rename` 在同一文件系统上是原子的（POSIX `rename(2)` / Windows `MoveFileEx` with `MOVEFILE_REPLACE_EXISTING`）。crash 发生在 temp 写入中 → 旧 `obs_001.json` 仍完整；crash 发生在 rename 后 → 新文件完整。不会出现半截文件。

**Schema Migration Registry**：

`schema_version.json` 升级时，通过 Migration Registry 链式迁移：

```
schema 1 ──Migration001──→ schema 2 ──Migration002──→ schema 3
```

```dart
abstract class AdiMigration {
  int get fromVersion;
  int get toVersion;
  AdiRecord migrate(AdiRecord record);
}

class AdiMigrationRegistry {
  final List<AdiMigration> _migrations;
  AdiRecord migrateToLatest(AdiRecord record, int currentVersion) { ... }
}
```

v0.1 只有 schema_version=1，无 migration。v0.2+ 字段变更时注册 Migration001 等。CLI 读取 `.adi/` 时先检查 schema_version，旧版本走 `migrateToLatest()`。

**隐私守门**：`.adi/` 存储的 payload 需根据 `ObservabilityLevel` 过滤：

- `off`：不写入 `.adi/`
- `light`：写入 trace/invariant/error，**不写文档内容**（ADR-0023 §3.3 延续）
- `full`：写入全部（仅 debug build）

**架构守门**：`.adi/` 写入只能通过 `lib/core/observability/adi_storage.dart`（allowlist 入口），通过 `file_access_test.dart` TC-ARCH-2 守门。

**`.gitignore`**：`.adi/` 是运行时产物，不入库。需在 ADR-0024 Accepted 时同步更新 `.gitignore`。

### 2.7 CLI Entry（CLI 入口）

**目标**：v0.1 先做 CLI，不引入 HTTP server 依赖（符合 3.7 自研原则）。

**方案**：独立纯 Dart 脚本 `tools/adi/adi.dart`，读 `.adi/` 目录，不依赖 Flutter runtime，Agent 直接 `dart run`。

**命令集**：

| 命令 | 功能 | 优先级 |
|------|------|--------|
| `adi latest-error` | 获取最近失败 | P0 |
| `adi failure show <id>` | 查看指定失败详情 | P0 |
| `adi trace show <id>` | 查看 trace chain | P0 |
| `adi replay <id>` | 重放 session | P0 |
| `adi agent-context` | 生成 Agent 上下文 Markdown | P0 |
| `adi failures list` | 列出最近失败 | P1 |
| `adi validate --after-fix` | 修复后验证 | P1 |
| `adi doctor` | ADI 自检（Agent 首次接入时验证 ADI 是否正常） | P0 |

**`adi doctor`（ADI 自检）**：

Agent 首次接入时需知道"ADI 自己是否正常"，否则 `adi latest-error` 返回空时无法区分"没有 bug"还是"ADI 坏了"：

```bash
adi doctor
```

输出：

```
ADI Health Check
────────────────────────────────
Storage:     ✓ writable (.adi/ exists, 12 MB used / 500 MB quota)
Schema:      ✓ version 1
Observability: ✓ enabled (level=light)
Replay:      ✓ available (replay_engine loaded)
Last failure: 2026-08-10 06:54 (obs_001, 3 hours ago)
────────────────────────────────
Status: healthy
```

`--json` 模式返回结构化结果，含各子系统 `status` 字段（`healthy` / `degraded` / `broken`），Agent 可据此判断是否信任 ADI 输出。

**双模式输出（human / machine）**：

每个命令支持 `--json` 标志，默认输出人类可读格式，加 `--json` 输出 Agent 可直接解析的结构化 JSON：

```bash
# 人类模式（默认）
adi latest-error
# → Error: TaskListItemElement unsupported renderer fallback
#   Trace: trc_0219  Session: sess_9e0b  Replay: yes

# Agent 模式（machine）
adi latest-error --json
# → {"status":"error","trace":"trc_0219","session":"sess_9e0b",
#    "replay_available":true,
#    "next_actions":["adi replay sess_9e0b","adi trace show trc_0219"]}
```

**`next_actions` 字段**：machine 模式输出中包含 `next_actions` 数组，给出 Agent 建议的后续命令。这让 Agent 能 `shell("adi latest-error --json")` → 解析 JSON → 执行 `next_actions[0]`，比解析 Markdown 稳定。

**设计理由**：纯 Dart CLI 轻量，不依赖 Flutter runtime，Agent 调用门槛低。App 侧仅负责把 `ObservabilityService` 数据写入 `.adi/`（通过 `adi_storage.dart`），CLI 侧负责读 `.adi/` + 生成 Agent 上下文。双模式输出让同一 CLI 同时服务人类调试和 Agent 自动化。

### 2.8 Agent Operating Contract（见 §1.4）

Agent 操作契约已提升为 ADI 核心原则 §1.4 ADI Core Principles。本节仅作交叉引用，不重复定义。

### 2.9 Agent Evaluation Loop（Agent 评价闭环）

> ADI 不只是 Agent debugger，更是 **Agent learning infrastructure**。记录 Agent 的修复尝试，未来可分析"哪类 bug Agent 容易错"、"哪些 hypothesis 有价值"。

**模型**：

```dart
/// 记录 Agent 的一次诊断-修复尝试。让 ADI 能评价 Agent 行为质量。
class AgentDiagnosisRecord {
  final String diagnosisId;
  final String failureId;           // 关联 AdiFailureRecord
  final List<AdiHypothesis> hypotheses;  // Agent 提出的假设
  final List<String> changedFiles;  // Agent 修改的文件
  final AdiValidationResult? validation;  // 验证结果
  final bool success;               // 修复是否成功
  final DateTime timestamp;
  final int attemptNumber;          // 第几次尝试（同一 failureId）
}
```

**价值**：
- **Agent 自我改进**：Agent 可查 `adi diagnosis history <failure_id>` 看之前尝试，避免重复失败路径
- **系统评价**：聚合分析"哪类 errorType Agent 修复成功率低"→ 针对性改进 ADI 的 hypothesis 生成
- **hypothesis 验证追踪**：`AdiHypothesis.verified` 字段记录哪些假设被证实/证伪

**优先级**：P2（v0.2 可开始记录，v0.3 分析查询）。v0.1 不实现。

### 2.10 Permission Model（权限模型）

> ADI 暴露 stack trace / session / environment / 用户行为，需权限控制。

**三级权限**：

| 权限 | 可执行命令 | 可读数据 |
|------|-----------|---------|
| `readonly` | `adi doctor` / `adi latest-error` / `adi trace show` / `adi failures list` | observations / traces / invariants（不含 environment 敏感字段） |
| `diagnostic` | 上述 + `adi replay` / `adi agent-context` | 上述 + environment + replay |
| `repair` | 上述 + `adi validate --after-fix` + `adi diagnosis` | 全部 |

**默认权限**：CLI 默认 `diagnostic`。`repair` 需显式 `--permission repair`（或配置文件），因为 validate 可能触发 `flutter test` 执行。

**设计理由**：类似 Claude Code 的 read/write/execute 权限模型。Agent 在不同阶段用不同权限：观察阶段 `readonly`，诊断阶段 `diagnostic`，修复阶段 `repair`。

### 2.11 Protocol Versioning（协议版本）

> `schema_version`（§2.6）约束 `.adi/` 存储格式。但 Agent 调用的 CLI 接口/JSON 输出格式也需要独立版本控制。

**双版本**：

```json
{
  "adi_protocol_version": "1.0",   // CLI 接口 / JSON 输出格式版本
  "schema_version": 1              // .adi/ 存储格式版本
}
```

- `adi_protocol_version`：`adi latest-error --json` 的 JSON 字段集变更时升版本。Agent 据此判断输出格式兼容性。
- `schema_version`：`AdiRecord` 字段集变更时升版本。CLI 据此走 Migration Registry。

两者独立演进。`adi doctor --json` 输出双版本，Agent 首次接入时检查 `adi_protocol_version` 兼容性。

---

## 3. 实施计划

### 3.1 目录结构

```
flutter_app/lib/core/observability/
├── adi_record.dart             ← 新增：Layer 2 持久化 schema（AdiRecord / AdiErrorRecord）
├── adi_view.dart               ← 新增：Layer 3 Agent 视图（AdiView / AdiErrorView / AdiCandidateCause）
├── adi_storage.dart            ← 新增：.adi/ 目录读写（allowlist 入口，只读写 AdiRecord）
├── adi_query_adapter.dart      ← 新增：AdiRecord → AdiView 投影 + 查询
├── adi_replay_adapter.dart     ← 新增：replay_engine → Replay 协议
├── adi_context_generator.dart  ← 新增：生成 agent-context Markdown
└── adi_context_generator.dart  ← 新增：生成 agent-context Markdown

flutter_app/lib/core/replay/
└── replay_engine.dart          ← 新增：从 CommandReplayer Extract 的核心重放引擎（依赖 core/editing，不依赖 presentation）

flutter_app/lib/presentation/observability/
└── command_replayer.dart       ← 保持原位，改为委托 core/replay_engine（Extract 非 Move）

tools/adi/
└── adi.dart                    ← 新增：纯 Dart CLI 入口（支持 --json machine mode）

flutter_app/test/observability/
├── adi_storage_test.dart         ← 新增
├── adi_record_test.dart          ← 新增
├── adi_view_test.dart            ← 新增
├── adi_query_adapter_test.dart   ← 新增
├── adi_replay_adapter_test.dart  ← 新增
└── adi_context_generator_test.dart ← 新增
```

**文件行数约束**：每个新增 `.dart` 文件 ≤ 400 行（`file_size_test.dart` TC-ARCH-7 守门）。

### 3.2 分阶段实施

#### v0.1 Core：Agent 诊断核心闭环（P0）

**目标**：Agent 能完成 发现 → 复现 → 定位 闭环的核心命令（不含工程化收尾）。

**交付**：

| 能力 | 后端依据（3.7 已建成） | 新增工作 |
|------|----------------------|---------|
| `adi latest-error`（含 `--json`） | `ErrorSnapshotter` 缓冲区 | Query Adapter + CLI |
| `adi trace show <id>` | `CommandTracer`/`TransactionTracer` RingBuffer | Trace Adapter + CLI |
| `adi replay <id>` | `CommandReplayer`（已实现） | Replay Adapter + CLI + Extract replay_engine |
| `adi agent-context` | `analyze.py` 逻辑迁移 | Context Generator + CLI |

**插入点**：

| 插入位置 | 插入内容 |
|---------|---------|
| `ObservabilityService` 构造 | 注入 `AdiStorage`（可选参数，零侵入） |
| `ErrorSnapshotter.capture()` | 触发 `AdiStorage.writeRecord()` |
| `CommandReplayer` | Extract 核心逻辑到 `core/replay/replay_engine.dart`，原位委托 |

#### v0.1.1：工程化收尾（P0）

**目标**：补齐 v0.1 Core 的工程化配套，使其可合并。

**交付**：
- `.adi/` 基础存储（`observations/` / `sessions/` / `traces/` 目录 + `schema_version.json` 写入 + crash-safe atomic write）
- `adi failure show <id>` 单条详情查询（不做聚合，聚合留 v0.2）
- 架构守门测试通过（`file_access_test.dart` TC-ARCH-2 allowlist + `file_size_test.dart` TC-ARCH-7）
- `.gitignore` 新增 `.adi/` 条目
- LIGHT 模式隐私守门（不写文档正文）
- 新增 6 个 ADI 测试文件全部 PASS
- `flutter analyze` 0 error/warning + `flutter test` 0 regression

**v0.1 暂缓项（移至 v0.2，属于 Data Lifecycle Management 而非 Agent Diagnosis MVP）**：
- Schema Migration Registry
- Failure aggregation（`AdiFailureRecord` 聚合）
- `index.json` 索引
- LRU 清理配额

**为何拆 v0.1 / v0.1.1**：v0.1 Core 聚焦核心诊断能力（4 个命令），v0.1.1 聚焦工程化收尾（基础存储/守门/测试/隐私）。分开交付符合工程节奏，避免单 PR 过大。Data lifecycle management（migration/aggregation/index/LRU）留 v0.2，避免"ADI 还没验证价值就开始造数据库"。

#### v0.2：验证闭环 + 索引（P1）

**目标**：补齐验证能力（replay + invariant，不含 test 子集）+ 索引优化。

**交付**：
- `adi validate --after-fix`：**Replay + Invariant**（不含 flutter test 子集，见 ADR-0026）
- `adi failures list`：**Failure aggregation**（`AdiFailureRecord` 聚合查询）+ `index.json` 索引
- `.adi/` **LRU 清理配额**（max_sessions=20 / max_storage_size=500MB / max_single_snapshot=5MB）
- **Schema Migration Registry**（链式迁移 schema_version 升级）
- 评估 SQLite 替代 JSON 索引（需评估是否违反 AGENTS.md §6.5 跨阶段引入 SQLite 禁令——Phase 3.8 若已过 Phase 2 性能优化阶段则可解禁）
- 评估废弃 `ExportPipeline` zip

#### v0.3：拆为独立 ADR-0026（不在本 ADR 范围）

**Change Impact Analysis**（`git diff` → 依赖图 → test 子集 → `flutter test`）+ `candidate_causes` 源码行号映射 + HTTP API 均拆为**独立 ADR-0026**，不属于 ADI Core Protocol。本 ADR-0024 的 v0.2 已交付完整验证闭环（replay + invariant），test 子集选择需独立的 Dependency Graph / Static Analysis 设计，留待 ADR-0026。

### 3.3 性能约束

| 指标 | 目标 | 测量方式 |
|------|------|---------|
| `.adi/` 单次写入耗时 | < 5ms | benchmark 测试 |
| `adi latest-error` 响应 | < 50ms（内存命中）/ < 200ms（磁盘命中） | CLI 集成测试 |
| `adi replay` 单步耗时 | < 10ms（复用 CommandReplayer 性能） | 现有 `replay_determinism_test.dart` |
| `.adi/` 存储增长 | 受 `ObservabilityLevel` + 保留窗口控制 | 存储配额测试 |

**保留窗口**：`.adi/sessions/` 保留最近 N 个 session（默认 N=20），超期清理。避免无限增长。

### 3.4 架构守门合规

新增代码必须通过现有 21 个 `test/architecture/` 守门，特别是：

| 守门测试 | 约束 | ADI 合规措施 |
|---------|------|-------------|
| `file_access_test.dart`（TC-ARCH-1/2） | presentation 层禁止 `File()`/`Directory()`；`writeAs*` 仅 allowlist | `.adi/` 写入仅在 `adi_storage.dart`（allowlist） |
| `file_size_test.dart`（TC-ARCH-7） | 每个 `.dart` 文件 ≤ 400 行 | 拆分 Adapter / Protocol / Storage |
| `layer_dependency_test.dart` | 六层分层依赖方向 | ADI Adapter 属 `core/`，禁止 import `presentation/`；Extract `replay_engine` 到 `core/` |
| `no_print_test.dart` | 禁止 `print()`，必须 `debugPrint()` | CLI 用 `stdout` 输出，内部日志用 `debugPrint()` |
| `provider_uniqueness_test.dart` | 禁止同名 Provider | ADI 不引入新 Provider（构造注入） |

---

## 4. 后果

### 4.1 正面

1. **Agent 自主诊断闭环**：Agent 能独立完成 发现 → 复现 → 定位 → 验证，减少 Human Owner 介入
2. **证据消费标准化**：3.7 的内部能力被标准化暴露，不再仅服务于 `analyze.py`
3. **增量查询**：`.adi/` 取代 zip，Agent 可 `adi latest-error` 即时获取，无需解压
4. **复用非重采**：零采集逻辑重复，全部复用 3.7 已建成 + 已测试的能力
5. **隐私延续**：LIGHT 模式不写文档正文，遵循 ADR-0023 决策
6. **架构守门合规**：新增代码通过现有 21 个守门，不破坏既有架构约束

### 4.2 负面

1. **新增代码量**：约 5 个 Adapter + 1 个 Storage + 1 个 CLI + 4 个测试文件，约 1500-2000 行
2. **`CommandReplayer` Extract 重构**：从 `presentation/` Extract 核心逻辑到 `core/replay/replay_engine.dart`，原文件保持原位委托，需保证 0 业务行为变化（AGENTS.md §6.3）
3. **`.adi/` 存储增长**：需保留窗口清理机制，否则无限增长
4. **CLI 维护成本**：`tools/adi/adi.dart` 是独立 Dart 脚本，需同步 `lib/core/observability/adi_protocol.dart` 的模型变更
5. **Agent 过度信任风险**：`candidate_causes` 是假设非结论，Agent 若过度信任可能误修——通过 `agent-context` 明确标注 "Suggested" / "Hypothesis" 缓解

### 4.3 不产生的影响

1. **不修改 3.7 任何 public API**——`ObservabilityService` / `ErrorSnapshotter` / `InvariantChecker` 的 public API 不变，仅通过构造注入 `AdiStorage`
2. **不增加新 Provider**——ADI 不是 Riverpod Provider，由 `ObservabilityService` 构造注入
3. **不引入第三方依赖**——无 Sentry / OpenTelemetry / HTTP server 框架（ADR-0023 §5.1 决策延续）
4. **不改变 E2E 测试策略**——E2E 仍验证"用户路径是否失败"，ADI 在 E2E 失败时辅助 Agent 诊断
5. **不影响 release build 包大小**——`.adi/` 写入仅在 `ObservabilityLevel != off` 时触发，`off` 模式 tree-shaking 移除
6. **不跨阶段引入 SQLite**——v0.1 用 JSON 索引，SQLite 留 v0.2 评估（AGENTS.md §6.5）

---

## 5. 替代方案

### 5.1 方案 A：沿用 zip + analyze.py，不做 ADI

**思路**：3.7 已有 `ExportPipeline` zip + `analyze.py`，Agent 直接调 `python analyze.py` 即可，无需新增 ADI 层。

**被拒理由**：
- zip 是全量打包，Agent 无法增量查询"最近一次失败"
- `analyze.py` 输出是文本报告，非结构化 JSON / Agent 可消费的 Markdown
- Agent 需先 `adb pull` zip 再 `python analyze.py`，流程长且依赖 Python 环境
- 无 Replay / Validation 协议接口，Agent 无法自动复现 + 验证
- `analyze.py` 逻辑与 `lib/core/observability/` 模型脱节，模型变更需手工同步

### 5.2 方案 B：接入第三方 APM 的 Agent 集成（如 Sentry Agent SDK）

**思路**：接入 Sentry 等已支持 AI Agent 集成的第三方 APM。

**被拒理由**：
- FormulaFix 是离线编辑器，用户可能无网络连接（ADR-0023 §5.1 同理由）
- 编辑器的领域特定诊断（Command Trace / Transaction Trace / 5 项 Invariant）通用 APM 无法覆盖
- 用户隐私：上传文档内容到第三方违反 ADR-0003"文件即隐私"原则
- 3.7 已建成自研能力，接入第三方等于推倒重来，违反"复用非重采"原则

### 5.3 方案 C：HTTP API 优先（不做 CLI，直接做 HTTP server）

**思路**：ADI 直接做 HTTP server，Agent 通过 HTTP 调用，更"标准"。

**被拒理由**：
- 引入 HTTP server 依赖违反 3.7 自研原则（ADR-0023 §5.1）
- Flutter App 内嵌 HTTP server 不现实（生命周期 / 端口管理 / 安全）
- Agent 调用 HTTP 需知道端口 + 处理连接失败，比 `dart run tools/adi/adi.dart` 门槛更高
- v0.1 先 CLI，v0.3 评估 HTTP 必要性（若 Agent 需长连接实时查询再做）

### 5.4 方案 D：ADI 纳属 presentation 层（不 Extract core）

**思路**：ADI Adapter 放 `presentation/observability/`，直接复用 `CommandReplayer`，不 Extract 核心逻辑到 `core/`。

**被拒理由**：
- 违反 `layer_dependency_test.dart` 守门：ADI 是诊断基础设施，应属 `core/` 层
- `presentation/` 层的 ADI 无法被 `tools/adi/adi.dart` 纯 Dart CLI 复用（CLI 不依赖 Flutter runtime）
- Extract `replay_engine` 到 `core/` 是必要重构，使 `presentation/` 仅留 UI 集成委托

---

## 6. 退出条件

### v0.1 Core 退出条件（P0）

- [ ] `adi latest-error`（含 `--json`）在有错误时返回结构化 `AdiErrorView`，无错误时返回 `{"status": "no_error"}`
- [ ] `adi trace show <id>` 输出跨层 span 树（interaction → command → transaction → render → error）
- [ ] `adi replay <id>` 能复现 3.7 测试中已知的 fallback 场景（如 `TaskListItemElement → FallbackBlockRenderer`）
- [ ] `adi agent-context` 输出 Markdown 可被 Claude Code 直接作为上下文消费
- [ ] `replay_engine.dart` 从 `CommandReplayer` Extract 核心逻辑，`command_replayer.dart` 原位委托，0 业务行为变化（`replay_determinism_test.dart` 守门）

### v0.1.1 退出条件（P0 工程化收尾）

- [ ] `.adi/` 基础存储实现（`observations/` / `sessions/` / `traces/` + `schema_version.json` 写入 + crash-safe atomic write）
- [ ] `adi failure show <id>` 输出完整 trace chain + candidate_causes（单条，不做聚合）
- [ ] `.adi/` 存储通过 `file_access_test.dart` TC-ARCH-2 守门（写入仅在 `adi_storage.dart` allowlist）
- [ ] 新增文件全部 ≤ 400 行（`file_size_test.dart` TC-ARCH-7）
- [ ] LIGHT 模式不写入文档正文（隐私守门，ADR-0023 §3.3 延续）
- [ ] `.gitignore` 新增 `.adi/` 条目
- [ ] `flutter analyze --no-fatal-infos --fatal-warnings` 0 error/warning
- [ ] `flutter test` 0 regression（现有 70 architecture + 35 commands + 64 editor + 16 observability 测试全部 PASS）
- [ ] 新增 6 个 ADI 测试文件全部 PASS

### v0.2 退出条件（P1）

- [ ] `adi validate --after-fix` 能执行 **Replay + Invariant** 验证（不含 flutter test 子集，留 ADR-0026）
- [ ] `adi failures list` 通过 **Failure aggregation**（`AdiFailureRecord`）+ `index.json` 索引查询
- [ ] `.adi/` **LRU 清理配额**生效（max_sessions=20 / max_storage_size=500MB / max_single_snapshot=5MB）
- [ ] **Schema Migration Registry** 实现链式迁移（schema_version 升级）
- [ ] 评估 SQLite 替代 JSON 索引的必要性 + AGENTS.md §6.5 合规性

### v0.3 退出条件 → 见独立 ADR-0026

v0.3（Change Impact Analysis + test 子集 + Source Mapper + HTTP）已拆为独立 ADR-0026，退出条件见该 ADR。本 ADR-0024 的验证闭环在 v0.2（replay + invariant）完成。

---

## 7. Open Questions

1. **ADI 是否纳入 ROADMAP Phase 3.8？** 原 Phase 3.8（文件树侧栏）已合并到 3.4.2（PR #77）。ADI 若纳入 ROADMAP 应作为 Phase 3.8 新定义。需 Human Owner 决策（架构决策类文件）。
2. **`CommandReplayer` Extract 的 0 行为变化如何验证？** 需复用现有 `replay_determinism_test.dart` + 新增 Extract 前后行为对比测试。
3. **`candidate_causes` 源码反向映射如何实现？** v0.1 可只给 trace chain（无源码行号），v0.3 实现 Source Mapper（P2）。需评估是否引入 source_map 依赖。
4. **`flutter test` 子集选择策略（v0.3 Change Impact Analysis）？** 如何根据 Agent 改动文件选相关测试子集。方案：基于 `test/architecture/layer_dependency_test.dart` 的依赖图反向查询。v0.2 先交付 replay + invariant 闭环，test 子集留 v0.3。
5. **`.adi/` 跨设备同步？** 用户在手机产生 `.adi/`，Agent 在电脑消费。v0.1 假设 `.adi/` 已在 Agent 可访问路径（通过 `adb pull` 或共享目录）。v0.2 评估自动同步必要性。

---

## 8. 与 AGENTS.md 的合规声明

本 ADR 遵守 AGENTS.md 全部硬规则：

| 规则 | 合规措施 |
|------|---------|
| §1.1 六层分层 | ADI Adapter 属 `core/`，Extract `replay_engine` 到 `core/`，禁止 `core` import `presentation` |
| §1.2 单一职责 | 每文件 ≤ 400 行，拆分 Record / View / Adapter / Storage / CLI |
| §2.2 现代 Dart | `sealed class` 用于 `AdiRecord` / `AdiView` 联合 |
| §3.1 Provider 选择 | ADI 不引入新 Provider，构造注入 |
| §4.1 单一真相源 | `.adi/` 是运行时产物，不入库（`.gitignore`），不与 ADR-0003 存储冲突 |
| §6.1 业务禁区 | 不在 `core/` import `presentation/`；不新增同名 Provider；不 `print()` |
| §6.2 工程禁区 | `.adi/` 入 `.gitignore`；不提交含密钥文件 |
| §6.3 AI 协作禁区 | 不凭空设计（基于 ADR-0023 已建成）；不跨阶段（Phase 3.8 在 Phase 3 之后）；重构 0 行为变化 |
| §6.4 AI/Human 分工 | 本 ADR 由 AI 起草，待 Human Owner 签字 Accepted；commit 需 Human Owner 授权 |
| §6.5 当前阶段禁止 | 不修改 UI 行为（Phase 3 UI 重写期）；不跨阶段引入 SQLite（v0.1 用 JSON 索引） |

---

## 9. E2E Test Plan（Agent Diagnostic Protocol E2E）

> ADI 的 6 条 MUST 契约（§1.4）是**协议级**约束，不能仅靠单元测试覆盖——需在
> **协议闭环**层面验证：Agent 按契约顺序驱动 CLI，每个命令的输出作为下一个命令
> 的输入。本 §9 定义 E2E 测试计划，作为本 ADR 的验收手段之一。

### 9.1 定位与边界

- **不是 Flutter integration_test**：E2E 驱动纯 Dart CLI（`tools/adi/adi.dart`），
  不依赖 Flutter runtime（延续 §2.7 / §4.3.4 决策）。
- **闭环验证对象**：Agent Interaction Contract 的 6 条 MUST——
  Query first / Inspect before edit / Replay before modify / Validate after modify /
  Never trust candidate_causes / Respect invariant report。
- **数据来源**：001–003 为合成 fixture（随仓库提交）；004 为真实设备数据，
  经 ZipImporter（v0.1 兼容层，见 §9.6）导入，已落地（见 §9.4 E2E-ADI-004）。

### 9.2 测试夹具与 Runner

```
tools/adi/test/e2e/
├── e2e_runner.dart           ← Process.run 封装：staging fixture → temp/.adi → 跑 CLI
├── e2e_scenarios_test.dart   ← package:test 三个场景（001–003）
└── fixtures/
    ├── happy_path/.adi/        (合成：制造错误 + trace + replay=reproduced + invariant 全通过)
    ├── inconclusive/.adi/      (合成：错误 + trace，但缺 replay.json → 证据不完整)
    └── aggregation/.adi/       (合成：5 条 observation，4×RenderOverflow + 1×NullPointer)
```

**Runner 关键设计**（落地 §2.7 双模式输出契约）：
1. `stageAdi(name)` 把 fixture 复制到系统临时目录并重命名为 `.adi/`，
   CLI 以该临时目录为 CWD 运行（`adi.dart` 读 `<cwd>/.adi`）。
2. 每个场景**隔离、可重复**：committed fixture 永不被修改；"修复"通过
   runner 覆写临时副本的 `sessions/<id>/replay.json` 模拟。
3. `runAdiJson(args)` 调用 `dart run tools/adi/adi.dart <args> --json` 并解析 stdout。

### 9.3 场景总表

| 场景 | 数据来源 | 覆盖契约 | 验证重点 |
|------|---------|---------|---------|
| E2E-ADI-001 Happy Path | 合成 | 全部 6 条 | 制造错误 → latest-error → trace → replay → 修复 → validate(pass) |
| E2E-ADI-002 Inconclusive | 合成 | Query first / Respect invariant | 跨 session validation → 证据不完整 → inconclusive（绝不误判 pass） |
| E2E-ADI-003 Failure Aggregation | 合成 | Replay before modify | 多次相同错误 → aggregate → failures list 合并 + status 保留 |
| E2E-ADI-004 Real Device Render Overflow | debug/02 真机 | 全部 6 条 | 真机 sess RenderLine overflow → 经 ZipImporter → CLI 完整闭环（已落地，见 §9.4） |

### 9.4 场景细节

**E2E-ADI-001 Happy Path（全部 6 条契约）**
- `adi latest-error --json` → `status=error`，拿到 `session`/`trace`（Query first）。
- `adi trace show <traceId> --json` → 返回原始 trace，`sessionId` 可见、5 层 span 树完整（Inspect before edit）。
- `adi replay <sessionId> --json` → 修复前 `status=reproduced`，确认可复现（Replay before modify）。
- 修复前 `adi validate --after-fix <sessionId> --json` → `after=still_failing`。
- runner 覆写 `replay.json` 为 `notReproduced`（模拟代码修复生效）。
- 修复后 `adi validate --after-fix <sessionId> --json` → `after=pass`
  （replay 不再复现 + invariant 全通过）。
- `candidate_causes` 不在 CLI 输出中，修复决策由 Agent 推理（Never trust candidate_causes）。

**E2E-ADI-002 Inconclusive（Query first / Respect invariant）**
- `adi latest-error` → 错误可见（Query first）。
- `adi trace show` → trace 可见（Inspect before edit）。
- fixture 故意**不提供** `sessions/<id>/replay.json` → `adi replay` → `status=inconclusive`。
- `adi validate --after-fix` → invariant `failedNames=[]`（全通过），但 replay 证据缺失
  → `after=inconclusive`，**断言 `after != pass`**。
- 安全语义：即使所有不变量通过，只要 replay 证据不完整，就**绝不**判 pass（Respect invariant report）。
- 跨 session 维度：验证一个与错误 session 不同的 session（无数据）→ 返回 `no_data`
  （仅 `status` 字段，无 `after`），不被误判为 pass。注：cross-session *warning* 由
  App 侧 `AdiValidationAdapterImpl` 强制（`crossSessionDataWarning → inconclusive`，
  见 `adi_validation_adapter.dart`）；CLI 层以 `no_data` 兜底，二者语义一致。

**E2E-ADI-003 Failure Aggregation（Replay before modify）**
- 5 条 observation：4×`RenderOverflow`(同 stackHash) + 1×`NullPointer`。
- `adi failures aggregate` → 2 个 failure（`aggregated=2`），RenderOverflow `occurrences=4`。
- `adi failures list` → 列出 2 个 failure。
- 标记 RenderOverflow failure 的 `status=fixed`，再 `adi failures aggregate` 一次
  → `occurrences` 合并保持 4、`status` 保留为 `fixed`（不被重置为 `open`）。
- 验证聚合的"去重键 = hash(errorType+stackHash)"与"既有 status 优先"两条不变量。

**E2E-ADI-004 Real Device Render Overflow（全部 6 条契约）**
- 数据来源：3.7 `ExportPipeline` 导出（内容级一致：JSON 字段/值/顺序逐一对齐 `debug/02/`，仅换行符由 git `text=auto` 归一化），提交为合成
  fixture `tools/adi/test/e2e/fixtures/real_device/`
  （`metadata.json`/`snapshot.json`/`trace.json`/`invariant_report.json`）。
- `adi import <real_device_dir> --json` → `status=ok`，生成 `.adi/`
  （schema_version + observations + traces + sessions/<sid>/invariant_report + metadata）。
  **不生成** `replay.json`（真机导出无 replay 证据）。
- `adi latest-error --json` → `status=error`、`errorType=GlobalError`、message 含
  `RenderLine overflowed`、`session=sess_6b62`（Query first）。
- `adi trace show <traceId> --json` → 2 个 `render` span（Inspect before edit）。
- `adi replay sess_6b62 --json` → `status=inconclusive`（无 replay 证据；Replay before modify）。
- `adi validate --after-fix sess_6b62 --json` → replay 证据不完整 + invariant `not_checked`
  → `after=inconclusive`，**断言 `after != pass`**（Respect invariant report + 安全网）。
- 配套：`tools/adi/import_zip.dart` 的 `ZipImporter` 单测
  （`tools/adi/test/import_zip_test.dart`）固定 `ExportPipeline -> .adi/` 映射契约；
  `re-import` 幂等（merge，不重复）。

### 9.5 数据来源约束

- **001–003 合成 fixture** 随仓库提交于 `tools/adi/test/e2e/fixtures/`，CI 可离线运行。
- **004 真实设备数据**：来自 3.7 `ExportPipeline` 导出（如 `debug/02/` 的
  `snapshot.json`/`trace.json`/`metadata.json`/`invariant_report.json`），已提交为
  合成 fixture `tools/adi/test/e2e/fixtures/real_device/`，经 ZipImporter 转换后由 CLI 消费。
  ZipImporter（v0.1）已落地，004 已接入。

### 9.6 已知差距与演进（ZipImporter 兼容层）

3.7 的 `ExportPipeline` 导出是**"事故之后状态"快照**，不是运行时完整链路：
`debug/02` 中 `commandCount=0`/`interactionCount=0` 即表明缺失
`用户输入 → Command → Transaction → Render → Error` 全链路（证据缺失）。
因此 ZipImporter 解决**格式兼容**，不解决**证据完整性**——它定位为 ADI 的
**兼容/迁移层**，而非 ADI 本身。

演进路线（用户 2026-08-11 确认）：
- **v0.1**：不改 3.7，新增 `tools/adi/import_zip.dart`（`adi import <zip>`），
  把 `ExportPipeline` 格式转写为 `.adi/`，立即可用现有真机数据验证 CLI。
  **（已落地：2026-08-11，本 PR 内）**
- **v0.1.1**：建立 `AdiStorage` 一等公民，新错误直接写 `.adi/`（不再经 zip）。
- **v0.2**：废弃人工导出 zip；Agent 直接 `adi latest-error` 读运行时状态。

> 本 §9 收录已落地的 001–004 全部测试代码（含 ZipImporter 单测）；004 与 ZipImporter
> 已于 2026-08-11 同 PR 接入。

### 9.7 退出条件（E2E）

- [x] `tools/adi/test/e2e/` 含 runner + 001–004 场景，纯 Dart 驱动 CLI
- [x] `dart test`（tools/adi）四个场景全 PASS
- [x] CI 新增 `adi-e2e` job 运行 `dart test tools/adi`
- [x] E2E-004 真机场景接入（ZipImporter v0.1 已落地）

---

*本 ADR 由 AI Agent（CodeArts / GLM-5.2）起草于 2026-08-10，基于 ADR-0023 已完成的 Phase 3.7 代码实况。Human Owner 于 2026-08-10 评审签字 Accepted。实施未开始；实施后需在 §6 退出条件逐项打勾并更新本声明。*