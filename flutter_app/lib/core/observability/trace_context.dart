/// EditorTraceContext：跨层 Trace ID 设计。
///
/// 类似 OpenTelemetry 的 trace_id / span_id / parent_id 模型，
/// 用于建立 Interaction → Command → Transaction 的跨层因果链。
///
/// 落地 ADR-0021 §2.6。
library;

import 'dart:math';

/// 跨层 Trace ID 上下文。
///
/// 每次用户交互（EditorCoordinator.handle()）生成一个新的 traceId，
/// 该交互产生的所有 Command / Transaction 共享同一 traceId。
class EditorTraceContext {
  /// 会话级唯一 ID（App 启动时生成，持续到 App 退出）。
  final String sessionId;

  /// 操作链路 ID（一次用户交互产生的完整链路共享同一 traceId）。
  final String traceId;

  /// 当前层 ID（interaction / command / transaction 各自独立）。
  final String spanId;

  /// 父层 ID（用于构建跨层树状关系：interaction → command → transaction）。
  final String? parentSpanId;

  const EditorTraceContext({
    required this.sessionId,
    required this.traceId,
    required this.spanId,
    this.parentSpanId,
  });

  /// 创建子 Span（继承 sessionId + traceId，生成新 spanId）。
  EditorTraceContext childSpan(String spanId) {
    return EditorTraceContext(
      sessionId: sessionId,
      traceId: traceId,
      spanId: spanId,
      parentSpanId: this.spanId,
    );
  }

  @override
  String toString() =>
      'Trace(session=$sessionId, trace=$traceId, span=$spanId, parent=$parentSpanId)';
}

/// Trace ID 生成器。
///
/// 生成短格式 ID（便于阅读和日志搜索），格式为 `{prefix}_{counter:04d}`。
class TraceIdGenerator {
  static final Random _random = Random();
  static int _interactionCounter = 0;
  static int _commandCounter = 0;
  static int _transactionCounter = 0;

  /// 生成会话 ID（App 启动时调用一次）。
  static String sessionId() {
    final rand = _random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'sess_$rand';
  }

  /// 生成 trace ID（一次用户交互调用一次）。
  static String traceId() {
    _interactionCounter++;
    return 'trc_${_interactionCounter.toString().padLeft(4, '0')}';
  }

  /// 生成 command span ID。
  static String commandSpanId() {
    _commandCounter++;
    return 'cmd_${_commandCounter.toString().padLeft(4, '0')}';
  }

  /// 生成 transaction span ID。
  static String transactionSpanId() {
    _transactionCounter++;
    return 'tx_${_transactionCounter.toString().padLeft(4, '0')}';
  }

  /// 重置所有计数器（用于测试）。
  static void reset() {
    _interactionCounter = 0;
    _commandCounter = 0;
    _transactionCounter = 0;
  }
}