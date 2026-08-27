# ADI (Agent Diagnostic Interface) Design Document v1.2

> **状态**：Proposed（同步 ADR-0024 v4 Accepted 架构收敛）
> **前置**：[ADR-0024 Agent Diagnostic Interface](../decisions/ADR/0024-agent-diagnostic-interface.md)（架构决策，Accepted） / [ADR-0023 Editor Observability System](../decisions/ADR/0023-editor-observability-system.md)（Phase 3.7 已完成）
> **定位**：**怎么实现**文档（完整接口签名 / 目录结构 / CLI 命令 / 存储格式 / 代码模型）
> **与 ADR 分工**：ADR-0024 负责"为什么"，本文档负责"怎么实现"

---

## 1. Overview

### 1.1 背景

当前 AI Agent 调试 FormulaFix 的实际流程：

```
用户发现 Bug → 人工导出 zip → 压缩上传 → Agent 阅读 → 人工描述复现 → Agent 改代码 → 人工验证
```

存在问题：信息丢失 / 复现困难 / 状态上下文缺失 / Trace 与代码无法关联 / 修复无法自动验证。

### 1.2 与 Phase 3.7 的关系

Phase 3.7（ADR-0023）**已完成**，提供完整证据采集能力。ADI **复用而非重采**——3.7 采集证据，ADI 消费证据并暴露诊断协议给 Agent。

### 1.3 设计定位

> ADI 不是"调试工具"，是 **Agent Runtime Interface**。
> 核心问题：如何让 Agent 从 Observation 出发，自主完成 **发现 → 复现 → 定位 → 修复 → 验证** 闭环。

### 1.4 Agent Interaction Contract

> 见 [ADR-0024 §1.4](../decisions/ADR/0024-agent-diagnostic-interface.md#14-agent-interaction-contractagent-交互契约--核心原则)。6 条 MUST 契约（Query first / Inspect before edit / Replay before modify / Validate after modify / Never trust candidate_causes / Respect invariant report）。

---

## 2. Design Goals

- **G1 Zero-friction Observation**：Agent 不需要 zip/截图/手工日志，直接 `adi latest-error --json`
- **G2 Deterministic Replay**：任何错误能回答"能不能再次发生"，`adi replay <id>`
- **G3 Agent Native Diagnosis**：给 Observation + Context + Hypothesis，不给确定答案
- **G4 复用非重采**：全部复用 3.7 的 Tracer / Snapshotter / Replayer，零采集逻辑重复

---

## 3. Architecture

```
                    AI Agent (Claude Code / Codex / Cursor)
                    |
              ADI Protocol  ← ADR-0024 边界
                    |
        ┌───────────┴───────────┐
  Observation API          Action API
   (只读查询)             (replay/validate)
        │                       │
        ↓                       ↓
  ┌─────────────────────────────────────┐
  │      ADI Adapter Layer (新增)        │
  │  Query Adapter | Replay Adapter     │
  │  Context Generator | Validation     │
  └─────────────────────────────────────┘
        │                       │
        ↓                       ↓
  ┌─────────────────────────────────────┐
  │   Phase 3.7 Observability (已建成)   │
  │  ObservabilityService               │
  │  ErrorSnapshotter                   │
  │  CommandReplayer → replay_engine    │
  │  InvariantChecker                   │
  └─────────────────────────────────────┘
        │                       │
        ↓                       ↓
  .adi/ Storage            Test Harness
  (取代 zip)              (flutter test)
```

---

## 4. Core Concepts（三层模型 + Failure Identity）

### 4.1 三层模型分离

> 架构决策见 [ADR-0024 §2.1](../decisions/ADR/0024-agent-diagnostic-interface.md#21-adi-protocol三层模型分离)。

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
}

class AdiInvariantRecord extends AdiRecord {
  @override
  final String id;
  @override
  final DateTime time;
  @override
  final String sessionId;
  @override
  final String traceId;
  final List<String> violated;
  final List<String> checked;
}
```

**Layer 3：AdiView（Agent 消费视图，可演进）**

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
    quality: context.observationQuality(record),
    hypotheses: context.locateHypotheses(record),  // v0.1 可返回空
  );
}
```

### 4.2 Failure Identity（故障聚合）

> 架构决策见 [ADR-0024 §2.1 Failure Identity](../decisions/ADR/0024-agent-diagnostic-interface.md)。

单个 `AdiErrorRecord` 是一次 occurrence。同一 bug 发生 100 次会产生 100 个 record。引入 `AdiFailureRecord` 聚合：

```dart
class AdiFailureRecord {
  final String failureId;           // f_20260810_001
  final DateTime firstSeen;
  DateTime lastSeen;
  int occurrences;
  final String errorType;
  final String? stackHash;          // 去重键：errorType + stackHash
  final List<String> traceIds;
  final List<String> sessionIds;
  AdiFailureStatus status;          // open / fixed / recurring
}

enum AdiFailureStatus { open, fixed, recurring }
```

**去重键**：`failureId = hash(errorType + stackHash)`。相同 → 同一 failure，`occurrences++`。

**Agent 消费价值**：`adi failures list` 看到的是聚合后的 failure 列表（"TaskList renderer fallback × 47 次"），而非 47 条独立 observation。

### 4.3 Session

一次用户生命周期，映射到 `EditorTraceContext.sessionId`：

```
session (sess_9e0b)
  ├── interactions   (InteractionTracer)
  ├── commands        (CommandTracer)
  ├── transactions    (TransactionTracer)
  ├── renders         (RenderTracer)
  └── errors          (ErrorSnapshotter)
```

### 4.4 Trace

一次因果链，映射到 `EditorTraceContext` 的 `traceId` / `spanId` / `parentSpanId`：

```
traceId: trc_0219
  Interaction (span_01) "UserInput: '- [ ]'"
      ↓
  Command (span_02) InsertTextCommand
      ↓
  Transaction (span_03) commit (Paragraph → TaskListItem)
      ↓
  Render (span_04) BlockRenderer.switch → FallbackBlockRenderer
      ↓
  Error (span_05) RendererFallback
```

### 4.5 Replay

映射到 `replay_engine`（从 `CommandReplayer` Extract）。确定性由 `replay_determinism_test.dart` 守门。

### 4.6 Invariant Report

映射到 `InvariantChecker` 5 项不变量：`CursorExists` / `SelectionValid` / `BlockTreeAcyclic` / `ParentChildValid` / `HistoryConsistent`。

---

## 5. Interface Design

### 5.1 Query Adapter

> 架构决策见 [ADR-0024 §2.2](../decisions/ADR/0024-agent-diagnostic-interface.md#22-query-adapter查询适配)。

```dart
abstract class AdiQueryAdapter {
  AdiErrorView? latestError();
  AdiTraceView traceView(String traceId);
  List<AdiErrorView> recentFailures({int limit = 20});
  List<AdiFailureRecord> recentFailureGroups({int limit = 20});  // 聚合查询
}

class AdiQueryAdapterImpl implements AdiQueryAdapter {
  final ObservabilityService _service;
  final AdiStorage _storage;

  @override
  AdiErrorView? latestError() {
    final snapshot = _service.latestErrorSnapshot();
    if (snapshot != null) return _toView(snapshot.toRecord(), _context);
    final record = _storage.latestErrorRecord();
    return record != null ? _toView(record, _context) : null;
  }
}
```

**注意**：返回 `AdiView`（Layer 3），通过 `toView(record, context)` 从 `AdiRecord`（Layer 2）投影。Storage 只返回 Record。

### 5.2 Replay Adapter

> 架构决策见 [ADR-0024 §2.3](../decisions/ADR/0024-agent-diagnostic-interface.md#23-replay-adapter重放适配)。

```dart
abstract class AdiReplayAdapter {
  AdiReplayResultView replay(String sessionId);
}

class AdiReplayResultView {
  final AdiReplayStatus status;       // reproduced / notReproduced / inconclusive
  final String? failedAt;             // lib/presentation/blocks/block_renderer.dart:62
  final int commandsExecuted;
  final String resultTraceId;
  final List<AdiReplayStepView> steps;
}
```

**ReplayEngine 依赖契约**（[ADR-0024 §2.3](../decisions/ADR/0024-agent-diagnostic-interface.md)）：

```
core/replay/replay_engine.dart
  ✅ depends on: core/editing/ (Command, BlockEditorState, Transaction)
  ✅ depends on: core/observability/ (CommandTraceEntry)
  ❌ does NOT depend on: presentation/ (Widget, Renderer)
  ❌ does NOT depend on: domain/ (业务服务)
```

### 5.3 Validation Adapter（v0.2）

> 架构决策见 [ADR-0024 §2.4](../decisions/ADR/0024-agent-diagnostic-interface.md#24-validation-adapter验证适配)。

```dart
abstract class AdiValidationAdapter {
  AdiValidationResult validate({required String sessionId});
}

class AdiValidationResult {
  final String before;               // "crash" / "fallback" / "invariant_violation"
  final String after;                // "pass" / "still_failing"
  final AdiReplayResultView replayResult;
  final AdiInvariantSummary invariants;  // {violated: []}
}
```

v0.2 只做 **Replay + Invariant**。flutter test 子集选择（Change Impact Analysis）拆为 **ADR-0026**。

### 5.4 Agent Context Generator

> 架构决策见 [ADR-0024 §2.5](../decisions/ADR/0024-agent-diagnostic-interface.md#25-agent-context-generator上下文生成)。

```dart
abstract class AdiContextGenerator {
  String generateAgentContext();  // Markdown 格式
}
```

输出示例：

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

## Suspected location (Hypothesis, not confirmed)
- lib/presentation/blocks/block_renderer.dart:62

## Invariant status
All 5 invariants satisfied (rendering degradation, not state corruption)

## Suggested next action
- Confirm: `adi replay sess_9e0b`
- Inspect: `adi trace show trc_0219`
```

**关键**：给 **Observation + Context + Hypothesis**，不给确定答案。`hypotheses` 标 `confidence: "hypothesis"`。

### 5.5 Agent Evaluation Loop（Agent 评价闭环）

> 架构决策见 [ADR-0024 §2.9](../decisions/ADR/0024-agent-diagnostic-interface.md#29-agent-evaluation-loopagent-评价闭环)。

ADI 不只是 Agent debugger，更是 **Agent learning infrastructure**。记录 Agent 的修复尝试，未来可分析"哪类 bug Agent 容易错"、"哪些 hypothesis 有价值"。

```dart
/// 记录 Agent 的一次诊断-修复尝试。让 ADI 能评价 Agent 行为质量。
class AgentDiagnosisRecord {
  final String diagnosisId;
  final String failureId;                  // 关联 AdiFailureRecord
  final List<AdiHypothesis> hypotheses;    // Agent 提出的假设
  final List<String> changedFiles;         // Agent 修改的文件
  final AdiValidationResult? validation;   // 验证结果
  final bool success;                      // 修复是否成功
  final DateTime timestamp;
  final int attemptNumber;                 // 第几次尝试（同一 failureId）
}
```

**价值**：
- **Agent 自我改进**：Agent 可查 `adi diagnosis history <failure_id>` 看之前尝试，避免重复失败路径
- **系统评价**：聚合分析"哪类 errorType Agent 修复成功率低"→ 针对性改进 ADI 的 hypothesis 生成
- **hypothesis 验证追踪**：`AdiHypothesis.verified` 字段记录哪些假设被证实/证伪

**优先级**：P2（v0.2 可开始记录，v0.3 分析查询）。v0.1 不实现。

### 5.6 Permission Model（权限模型）

> 架构决策见 [ADR-0024 §2.10](../decisions/ADR/0024-agent-diagnostic-interface.md#210-permission-model权限模型)。

ADI 暴露 stack trace / session / environment / 用户行为，需权限控制。

**三级权限**：

| 权限 | 可执行命令 | 可读数据 |
|------|-----------|---------|
| `readonly` | `adi doctor` / `adi latest-error` / `adi trace show` / `adi failures list` | observations / traces / invariants（不含 environment 敏感字段） |
| `diagnostic` | 上述 + `adi replay` / `adi agent-context` | 上述 + environment + replay |
| `repair` | 上述 + `adi validate --after-fix` + `adi diagnosis` | 全部 |

**默认权限**：CLI 默认 `diagnostic`。`repair` 需显式 `--permission repair`（或配置文件），因为 validate 可能触发 `flutter test` 执行。

**设计理由**：类似 Claude Code 的 read/write/execute 权限模型。Agent 在不同阶段用不同权限：观察阶段 `readonly`，诊断阶段 `diagnostic`，修复阶段 `repair`。

---

## 6. CLI Design

> 架构决策见 [ADR-0024 §2.7](../decisions/ADR/0024-agent-diagnostic-interface.md#27-cli-entrycli-入口)。

纯 Dart 脚本 `tools/adi/adi.dart`，不依赖 Flutter runtime，Agent 直接 `dart run`。

### 6.1 命令集

| 命令 | 功能 | 优先级 |
|------|------|--------|
| `adi doctor` | ADI 自检（Agent 首次接入验证 ADI 是否正常） | P0 |
| `adi latest-error` | 获取最近失败 | P0 |
| `adi trace show <id>` | 查看 trace chain | P0 |
| `adi replay <id>` | 重放 session | P0 |
| `adi agent-context` | 生成 Agent 上下文 Markdown | P0 |
| `adi failure show <id>` | 查看指定失败详情 | P0 |
| `adi failures list` | 列出最近失败（聚合视图） | P1 |
| `adi validate --after-fix` | 修复后验证（replay + invariant） | P1 |

### 6.2 双模式输出（human / machine）

每个命令支持 `--json` 标志：

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

`next_actions` 字段让 Agent 能 `shell("adi latest-error --json")` → 解析 JSON → 执行 `next_actions[0]`。

### 6.3 adi doctor

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

`--json` 模式返回各子系统 `status`（`healthy` / `degraded` / `broken`），Agent 据此判断是否信任 ADI 输出。

---

## 7. Storage Design

> 架构决策见 [ADR-0024 §2.6](../decisions/ADR/0024-agent-diagnostic-interface.md#26-adi-storageadi-存储取代-zip)。

### 7.1 目录结构

```
.adi/
├── schema_version.json          (ADI schema 版本)
├── observations/
│   ├── obs_001.json
│   └── obs_002.json
├── failures/
│   └── f_20260810_001.json      (AdiFailureRecord 聚合记录)
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
│   └── replay_001.json
└── index.json                   (v0.1 JSON 索引；v0.2 评估 SQLite)
```

### 7.2 Schema Versioning（双版本）

> 架构决策见 [ADR-0024 §2.11](../decisions/ADR/0024-agent-diagnostic-interface.md#211-protocol-versioning协议版本)。

**双版本独立演进**：

```json
{
  "adi_version": "0.1",
  "adi_protocol_version": "1.0",
  "schema_version": 1,
  "created_at": "2026-08-10T13:00:00Z"
}
```

| 版本字段 | 约束范围 | 升版本时机 |
|---------|---------|-----------|
| `adi_protocol_version` | CLI 接口 / JSON 输出格式 | `adi latest-error --json` 的 JSON 字段集变更 |
| `schema_version` | `.adi/` 存储格式（`AdiRecord` 字段集） | `AdiRecord` 字段增删/语义变更 |

两者独立演进。CLI 读取 `.adi/` 时先检查 `schema_version`，旧版本走 `migrateToLatest()`。Agent 首次接入时通过 `adi doctor --json` 检查 `adi_protocol_version` 兼容性，据此判断输出格式是否可解析。

### 7.3 Storage 接口

```dart
abstract class AdiStorage {
  void writeRecord(AdiRecord record);           // allowlist 入口
  AdiErrorRecord? latestErrorRecord();           // 返回 Record，非 View
  AdiTraceRecord loadTrace(String traceId);
  List<CommandTraceEntry> loadSessionCommands(String sessionId);
  int readSchemaVersion();
  AdiFailureRecord? loadFailure(String failureId);  // 聚合查询
}
```

**注意**：Storage 只读写 `AdiRecord`（Layer 2），不返回 `AdiView`（Layer 3）。View 由 QueryAdapter 投影。

### 7.4 清理策略

| 配额项 | 默认值 | 超额处理 |
|--------|--------|---------|
| `max_sessions` | 20 | 清理最旧 session 目录 |
| `max_storage_size` | 500 MB | 按 LRU 清理最旧 observations + sessions |
| `max_single_snapshot` | 5 MB | 截断 render log / 不截断 error metadata |

清理在 `writeRecord()` 后异步触发，不影响采集性能。

### 7.5 Crash-safe Write

```
write record → write to temp (obs_001.json.tmp) → fsync → rename atomic (→ obs_001.json)
```

`rename` 在同一文件系统上是原子的。crash 在 temp 写入中 → 旧文件仍完整；crash 在 rename 后 → 新文件完整。不会出现半截文件。

### 7.6 Schema Migration Registry

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

v0.1 只有 schema_version=1，无 migration。v0.2+ 字段变更时注册 Migration001 等。

### 7.7 隐私守门

- `off`：不写入 `.adi/`
- `light`：写入 trace/invariant/error，**不写文档内容**（ADR-0023 §3.3 延续）
- `full`：写入全部（仅 debug build）

### 7.8 与 ExportPipeline 的关系

| 维度 | 现有 zip | ADI .adi/ |
|------|---------|-----------|
| 消费者 | 人工下载 + 解压 + analyze.py | Agent 直接读 |
| 查询 | 全量扫描 | index.json 索引 |
| 增量 | 每次全量打包 | 追加写入 |
| Replay | 需手工导入 session | 直接 `adi replay <id>` |

v0.1 保留 zip 作人工兜底，v0.2 评估废弃。

---

## 8. Agent Workflow

完整诊断闭环：

```
Agent 接到 bug 报告
    ↓
adi doctor                           (验证 ADI 健康)
    ↓
adi latest-error --json              (发现)
    ↓
获取 Observation + next_actions
    ↓
adi replay <session>                 (复现)
    ↓
确认复现 / 获取 failed_at
    ↓
adi trace show <trace_id>            (定位)
    ↓
分析 trace chain + hypotheses (Hypothesis)
    ↓
修改代码（Agent 推理，不信任 hypotheses 为真）
    ↓
adi validate --after-fix             (验证)
    ↓
replay 不再复现 + invariant 通过
    ↓
提交 PR
```

**Agent Interaction Contract**（[ADR-0024 §1.4](../decisions/ADR/0024-agent-diagnostic-interface.md)）：6 条 MUST 约束 Agent 操作顺序。

---

## 9. 与现有系统的关系

```
ADR-0023 Observability (已完成) → 采集证据
        ↓
   .adi/ Observation Store
        ↓
ADR-0024 ADI (本设计) → 消费证据 + 暴露诊断协议
        ↓
   AI Agent
        ↓
ADR-0026 Change Impact Analysis (未来) → test 子集选择 + 源码反向映射
```

**与 ADR-0022 的协同**：`TaskListItemElement → FallbackBlockRenderer` 是 ADR-0022 既定降级，非 bug。ADI 通过 `invariant_report.violated` 区分"既定 fallback"（全通过）与"意外 crash"（违反）。

**与 analyze.py 的关系**：升级为 `adi agent-context` 的 Context Generator 后端。

---

## 10. MVP Scope

> 架构决策见 [ADR-0024 §3.2](../decisions/ADR/0024-agent-diagnostic-interface.md#32-分阶段实施)。

### v0.1 Core（P0）

| 能力 | 后端依据（3.7 已建成） | 新增工作 |
|------|----------------------|---------|
| `adi doctor` | — | CLI + health check |
| `adi latest-error`（含 `--json`） | `ErrorSnapshotter` 缓冲区 | Query Adapter + CLI |
| `adi trace show <id>` | `CommandTracer`/`TransactionTracer` RingBuffer | Trace Adapter + CLI |
| `adi replay <id>` | `CommandReplayer`（已实现） | Replay Adapter + CLI + Extract replay_engine |
| `adi agent-context` | `analyze.py` 逻辑迁移 | Context Generator + CLI |

### v0.1.1（P0 工程化收尾）

- `.adi/` **基础存储**（`observations/` / `sessions/` / `traces/` 目录 + `schema_version.json` 写入 + crash-safe atomic write）
- `adi failure show <id>` 单条详情查询（不做聚合，聚合留 v0.2）
- 架构守门测试通过（TC-ARCH-2 allowlist + TC-ARCH-7 400 行）
- `.gitignore` 新增 `.adi/`
- LIGHT 模式隐私守门
- 新增 6 个 ADI 测试文件全部 PASS
- `flutter analyze` 0 error/warning + `flutter test` 0 regression

**v0.1 暂缓项（移至 v0.2，属于 Data Lifecycle Management 而非 Agent Diagnosis MVP）**：
- Schema Migration Registry
- Failure aggregation（`AdiFailureRecord` 聚合）
- `index.json` 索引
- LRU 清理配额

**为何拆 v0.1 / v0.1.1**：v0.1 Core 聚焦核心诊断能力（4 个命令），v0.1.1 聚焦工程化收尾（基础存储/守门/测试/隐私）。分开交付符合工程节奏，避免单 PR 过大。Data lifecycle management（migration/aggregation/index/LRU）留 v0.2，避免"ADI 还没验证价值就开始造数据库"。

### v0.2（P1）

- `adi validate --after-fix`：**Replay + Invariant**（不含 test 子集）
- `adi failures list`：**Failure aggregation**（`AdiFailureRecord` 聚合查询）+ `index.json` 索引
- `.adi/` **LRU 清理配额**（max_sessions=20 / max_storage_size=500MB / max_single_snapshot=5MB）
- **Schema Migration Registry**（链式迁移 schema_version 升级）
- 评估 SQLite 替代 JSON 索引（需评估 AGENTS.md §6.5 跨阶段引入 SQLite 合规性）
- 评估废弃 `ExportPipeline` zip

### v0.3 → 独立 ADR-0026

Change Impact Analysis + test 子集 + Source Mapper + HTTP API 拆为 **ADR-0026**，不在本设计范围。

---

## 11. Implementation Plan

### 11.1 目录结构

```
flutter_app/lib/core/observability/
├── adi_record.dart             ← Layer 2 持久化 schema（AdiRecord / AdiErrorRecord / AdiFailureRecord）
├── adi_view.dart               ← Layer 3 Agent 视图（AdiView / AdiErrorView / AdiHypothesis）
├── adi_storage.dart            ← .adi/ 读写（allowlist，只读写 AdiRecord，crash-safe write）
├── adi_query_adapter.dart      ← AdiRecord → AdiView 投影 + 查询
├── adi_replay_adapter.dart     ← replay_engine → Replay 协议
└── adi_context_generator.dart  ← agent-context Markdown

flutter_app/lib/core/replay/
└── replay_engine.dart          ← 从 CommandReplayer Extract（依赖 core/editing，不依赖 presentation）

flutter_app/lib/presentation/observability/
└── command_replayer.dart       ← 保持原位，委托 replay_engine

tools/adi/
└── adi.dart                    ← 纯 Dart CLI（支持 --json machine mode + adi doctor）

flutter_app/test/observability/
├── adi_storage_test.dart
├── adi_record_test.dart
├── adi_view_test.dart
├── adi_query_adapter_test.dart
├── adi_replay_adapter_test.dart
└── adi_context_generator_test.dart
```

### 11.2 插入点

| 插入位置 | 插入内容 |
|---------|---------|
| `ObservabilityService` 构造 | 注入 `AdiStorage`（可选参数，零侵入） |
| `ErrorSnapshotter.capture()` | 触发 `AdiStorage.writeRecord()` + `AdiFailureRecord` 聚合更新 |
| `CommandReplayer` | Extract 核心逻辑到 `core/replay/replay_engine.dart`，原位委托 |

### 11.3 架构守门合规

| 守门 | 约束 | 合规 |
|------|------|------|
| `file_access_test.dart` TC-ARCH-1/2 | presentation 禁 File()；writeAs* 仅 allowlist | `.adi/` 写入仅在 `adi_storage.dart` |
| `file_size_test.dart` TC-ARCH-7 | 每文件 ≤ 400 行 | 拆分 Record / View / Adapter / Storage |
| `layer_dependency_test.dart` | 六层依赖方向 | `replay_engine` 在 `core/replay/`，禁 import presentation/domain |
| `no_print_test.dart` | 禁 print() | CLI 用 stdout，内部用 debugPrint() |
| `provider_uniqueness_test.dart` | 禁同名 Provider | ADI 不引入新 Provider |

---

## 12. Risks & Trade-offs

| 风险 | 缓解 |
|------|------|
| `.adi/` 无限增长 | 清理配额（20 session / 500MB / 5MB） |
| LIGHT 模式信息不足 | `agent-context` 标注 `observability_level`，Agent 据此判断证据强度 |
| Replay 确定性破坏 | `replay_determinism_test.dart` 守门 + ReplayAdapter 检测非确定性 |
| Agent 过度信任 hypotheses | Contract §1.4 MUST "Never trust as truth" + `confidence: "hypothesis"` |
| Extract replay_engine 引入 regression | 0 行为变化 + `replay_determinism_test.dart` 守门 |
| crash 时 .adi/ 写半截 | atomic rename（temp → fsync → rename） |
| schema 升级旧数据不可读 | Migration Registry 链式迁移 |

---

## 13. Open Questions

1. ADI 是否纳入 ROADMAP Phase 3.8？（需 Human Owner 决策）
2. `replay_engine` Extract 的 0 行为变化如何验证？（复用 `replay_determinism_test.dart` + Extract 前后对比）
3. `hypotheses` 源码反向映射？（v0.3 / ADR-0026 Source Mapper）
4. `.adi/` 跨设备同步？（v0.1 假设 `adb pull`，v0.2 评估自动同步）

---

## 附录 A：真实代码引用

| 引用 | 路径 |
|------|------|
| EditorTraceContext | `lib/core/observability/trace_context.dart:15-48` |
| ObservabilityService | `lib/core/observability/observability_service.dart:29-80` |
| InvariantChecker 5 项 | `lib/core/observability/invariant_checker.dart` |
| ErrorSnapshot | `lib/core/observability/error_snapshot.dart` |
| ExportPipeline | `lib/core/observability/export_pipeline.dart` |
| CommandReplayer | `lib/presentation/observability/command_replayer.dart` |
| BlockRenderer switch | `lib/presentation/blocks/block_renderer.dart:49-68` |
| TaskListItemElement | `lib/data/models/document.dart:64-74` |
| FallbackBlockRenderer | `lib/presentation/blocks/fallback_block_renderer.dart:37` |
| analyze.py | `tools/ffx-analyze/analyze.py` |
| replay determinism test | `test/observability/replay_determinism_test.dart` |
| ADR-0023 | `docs/ADR/0023-editor-observability-system.md` |
| ADR-0022 | `docs/ADR/0022-renderer-failure-policy.md` |
| ADR-0024 | `docs/ADR/0024-agent-diagnostic-interface.md` |

---

## 附录 B：变更记录

### B.1 v1.0 → v1.1

同步 ADR-0024 v3 架构收敛：

| 变更 | v1.0 | v1.1 |
|------|------|------|
| 数据模型 | `AdiObservation` 单层 | 三层：`ErrorSnapshot` → `AdiRecord` → `AdiView` |
| Failure Identity | 无 | `AdiFailureRecord` 聚合（failure_id / occurrences / status） |
| Replay 重构 | Move 到 core | Extract 到 `core/replay/replay_engine.dart` + 依赖契约 |
| Storage | 无 schema version | `schema_version.json` + Migration Registry |
| Storage 安全 | 无 | crash-safe atomic rename + 清理配额 |
| CLI 输出 | human only | 双模式 `--json` + `next_actions` |
| CLI 命令 | 无 doctor | `adi doctor` 自检 |
| Agent Contract | §2.8 附属 | 提升为 §1.4 核心原则 |
| v0.3 | Change Impact Analysis 混入 | 拆为独立 ADR-0026 |
| 分阶段 | v0.1 单块 | v0.1 Core / v0.1.1 拆分 |
| 文档职责 | 与 ADR 重叠 | design doc=怎么实现，ADR=为什么 |

### B.2 v1.1 → v1.2

同步 ADR-0024 v4 Accepted 架构收敛（第三轮评审反馈全部落地）：

| 变更 | v1.1 | v1.2 |
|------|------|------|
| 假设模型 | `AdiCandidateCause`（无 verified） | `AdiHypothesis`（含 `verified` 字段，显式假设管理） |
| 证据完整度 | 无 | `AdiObservationQuality`（complete / partial / degraded） |
| Agent 评价 | 无 | `AgentDiagnosisRecord` + Agent Evaluation Loop（§5.5） |
| 权限控制 | 无 | Permission Model 三级权限（§5.6：readonly / diagnostic / repair） |
| 协议版本 | `schema_version` 单版本 | 双版本：`adi_protocol_version`（CLI 接口）+ `schema_version`（存储） |
| v0.1.1 范围 | 含 Migration / aggregation / index / LRU | 收敛为基础存储，Data Lifecycle 移 v0.2 |
| v0.2 范围 | validate + failures list + index | 补齐 LRU 配额 + Migration Registry + SQLite 评估 |
| ADR 状态 | Proposed | Accepted（Human Owner 签字 2026-08-10） |
