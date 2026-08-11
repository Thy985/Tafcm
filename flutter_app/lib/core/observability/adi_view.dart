/// ADI View：Agent 消费视图（Layer 3）。
///
/// 可自由演进，不持久化，由 [AdiRecord]（Layer 2）投影生成。
/// 增加字段不影响 .adi/ 存储 schema。
///
/// 落地 ADR-0024 §2.1（三层模型分离）。
library;

import 'adi_record.dart';

/// Agent 消费视图基类。
sealed class AdiView {
  String get id;
  String get traceId;
}

/// 证据完整度。Agent 需知道"我看到的信息是否足够"。
enum AdiObservationQuality {
  /// FULL 模式：全部数据。
  complete,

  /// LIGHT 模式：缺 render data / document content。
  partial,

  /// 数据损坏或截断。
  degraded,
}

/// 显式假设管理。Agent 不应把 hypothesis 当 fact。
class AdiHypothesis {
  final String file;
  final int line;
  final String reason;
  final String confidence;
  final bool verified;

  const AdiHypothesis({
    required this.file,
    required this.line,
    required this.reason,
    this.confidence = 'hypothesis',
    this.verified = false,
  });

  Map<String, Object?> toJson() => {
        'file': file,
        'line': line,
        'reason': reason,
        'confidence': confidence,
        'verified': verified,
      };
}

/// 错误视图（Agent 消费）。
class AdiErrorView extends AdiView {
  @override
  final String id;
  @override
  final String traceId;
  final String errorType;
  final String message;
  final bool replayAvailable;
  final String? snapshotPath;
  final AdiObservationQuality quality;
  final List<AdiHypothesis> hypotheses;
  final String? sessionId;
  final String? commandName;

  AdiErrorView({
    required this.id,
    required this.traceId,
    required this.errorType,
    required this.message,
    required this.replayAvailable,
    this.snapshotPath,
    this.quality = AdiObservationQuality.partial,
    this.hypotheses = const [],
    this.sessionId,
    this.commandName,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'traceId': traceId,
        'errorType': errorType,
        'message': message,
        'replayAvailable': replayAvailable,
        if (snapshotPath != null) 'snapshotPath': snapshotPath,
        'quality': quality.name,
        'hypotheses': hypotheses.map((h) => h.toJson()).toList(),
        if (sessionId != null) 'sessionId': sessionId,
        if (commandName != null) 'commandName': commandName,
      };
}

/// Trace span 节点（跨层因果链中的一步）。
class AdiSpanNode {
  final String spanId;
  final String? parentSpanId;
  final String layer;
  final String description;
  final DateTime timestamp;

  const AdiSpanNode({
    required this.spanId,
    this.parentSpanId,
    required this.layer,
    required this.description,
    required this.timestamp,
  });

  Map<String, Object?> toJson() => {
        'spanId': spanId,
        if (parentSpanId != null) 'parentSpanId': parentSpanId,
        'layer': layer,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Trace 视图（跨层因果链）。
class AdiTraceView extends AdiView {
  @override
  final String id;
  @override
  final String traceId;
  final String sessionId;
  final List<AdiSpanNode> spans;

  AdiTraceView({
    required this.id,
    required this.traceId,
    required this.sessionId,
    required this.spans,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'traceId': traceId,
        'sessionId': sessionId,
        'spans': spans.map((s) => s.toJson()).toList(),
      };
}

/// 不变量视图。
class AdiInvariantView {
  final List<String> violated;
  final List<String> checked;

  const AdiInvariantView({
    required this.violated,
    required this.checked,
  });

  bool get allPassed => violated.isEmpty;

  Map<String, Object?> toJson() => {
        'violated': violated,
        'checked': checked,
      };
}

/// Replay 状态。
enum AdiReplayStatus {
  /// 成功复现了错误。
  reproduced,

  /// 未复现错误。
  notReproduced,

  /// 结果不确定（如数据不足）。
  inconclusive,
}

/// Replay 单步结果视图。
class AdiReplayStepView {
  final int index;
  final String commandName;
  final bool success;
  final bool hashMatch;
  final String? error;

  const AdiReplayStepView({
    required this.index,
    required this.commandName,
    required this.success,
    required this.hashMatch,
    this.error,
  });
}

/// Replay 结果视图。
class AdiReplayResultView {
  final AdiReplayStatus status;
  final String? failedAt;
  final int commandsExecuted;
  final String resultTraceId;
  final List<AdiReplayStepView> steps;

  const AdiReplayResultView({
    required this.status,
    this.failedAt,
    required this.commandsExecuted,
    required this.resultTraceId,
    required this.steps,
  });

  Map<String, Object?> toJson() => {
        'status': status.name,
        if (failedAt != null) 'failedAt': failedAt,
        'commandsExecuted': commandsExecuted,
        'resultTraceId': resultTraceId,
        'steps': steps
            .map((s) => {
                  'index': s.index,
                  'commandName': s.commandName,
                  'success': s.success,
                  'hashMatch': s.hashMatch,
                  if (s.error != null) 'error': s.error,
                })
            .toList(),
      };
}

/// 验证前状态分类（Agent 修复前的问题类型）。
enum AdiValidationBefore {
  /// 崩溃 / 异常。
  crash,

  /// 渲染降级 / fallback。
  fallback,

  /// 不变量违反（状态损坏）。
  invariantViolation,

  /// 未知 / 未分类。
  unknown,
}

/// 验证后状态分类（Agent 修复后是否通过）。
enum AdiValidationAfter {
  /// 验证通过（replay 不再复现 + invariant 全通过）。
  pass,

  /// 仍然失败（replay 复现或 invariant 仍违反）。
  stillFailing,

  /// 结果不确定（数据不足）。
  inconclusive,
}

/// 验证结果视图（对应 CLI: adi validate --after-fix）。
class AdiValidationResultView {
  final AdiValidationBefore before;
  final AdiValidationAfter after;
  final AdiReplayResultView replayResult;
  final AdiInvariantView invariants;

  /// true 表示 invariant report 可能来自不同 session（非 session-scoped）。
  ///
  /// 此时 [after] 为 [AdiValidationAfter.inconclusive]，
  /// Agent 应重新在目标 session 中触发 invariant check。
  final bool crossSessionDataWarning;

  const AdiValidationResultView({
    required this.before,
    required this.after,
    required this.replayResult,
    required this.invariants,
    this.crossSessionDataWarning = false,
  });

  Map<String, Object?> toJson() => {
        'before': before.name,
        'after': after.name,
        'replayResult': replayResult.toJson(),
        'invariants': invariants.toJson(),
        'crossSessionDataWarning': crossSessionDataWarning,
      };
}