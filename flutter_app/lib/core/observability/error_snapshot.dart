/// ErrorSnapshot：错误快照数据模型。
///
/// 定义错误现场的结构化数据，包含 metadata、Command 信息、光标信息、
/// 最近操作列表和 App 环境信息。
///
/// 落地 ADR-0021 §2.4（Layer 4：Error Snapshot）。
library;

/// 错误快照捕获模式。
///
/// 落地 ADR-0021 §2.4（隐私保护）。
enum CaptureMode {
  /// 轻量模式：不含文档正文，仅 metadata + logs + AST hash。
  /// 默认模式，每次 App 启动生效。
  light,

  /// 完整模式：可包含文档正文 + 截图，需显式开启。
  /// `includeDocumentContent` 标志必须在开发者选项中显式开启，
  /// 且每次 App 启动重置为 false。
  full,
}

/// 错误快照（结构化数据）。
///
/// 在异常发生时自动保存的完整现场信息，类似 Chrome crash dump。
/// 默认（LIGHT 模式）不含文档正文，仅含元数据 + 日志 + AST hash。
class ErrorSnapshot {
  /// 快照唯一 ID，格式 `err_yyyyMMdd_HHmmss`。
  final String id;

  /// 错误发生时间。
  final DateTime timestamp;

  /// 错误类型。
  ///
  /// 可选值：
  /// - `CommandExecutionError`：Command 执行异常
  /// - `TransactionRollback`：非预期事务回滚
  /// - `GlobalError`：App 全局异常
  /// - `InvariantFailure`：不变量检查失败
  final String type;

  /// 错误消息。
  final String message;

  // === Command 信息 ===

  /// 出错的 Command 名称（如 "InsertTextCommand"）。
  final String? commandName;

  /// 出错的 Command 参数。
  final Map<String, Object?>? commandParams;

  // === 光标信息 ===

  /// 错误发生时光标所在的 Block ID。
  final String? cursorBlockId;

  /// 错误发生时光标偏移量。
  final int? cursorOffset;

  // === 最近操作 ===

  /// 最近 N 条操作摘要（按时间排序，最新在前）。
  final List<Map<String, Object?>> recentOperations;

  // === App 信息 ===

  /// App 版本号。
  final String appVersion;

  /// 设备型号。
  final String device;

  /// 操作系统版本。
  final String os;

  // === 关联 Trace ===

  /// 关联的 Trace ID。
  final String? traceId;

  /// 关联的 Session ID。
  final String? sessionId;

  /// 捕获模式。
  final CaptureMode captureMode;

  /// 是否包含文档正文（仅 FULL 模式）。
  final bool includeDocumentContent;

  const ErrorSnapshot({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.message,
    this.commandName,
    this.commandParams,
    this.cursorBlockId,
    this.cursorOffset,
    this.recentOperations = const [],
    this.appVersion = '',
    this.device = '',
    this.os = '',
    this.traceId,
    this.sessionId,
    this.captureMode = CaptureMode.light,
    this.includeDocumentContent = false,
  });

  /// 序列化为 JSON 兼容 Map。
  Map<String, Object?> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'type': type,
    'message': message,
    if (commandName != null) 'command': {
      'name': commandName,
      if (commandParams != null) 'params': commandParams,
    },
    if (cursorBlockId != null) 'cursor': {
      'blockId': cursorBlockId,
      'offset': cursorOffset,
    },
    if (recentOperations.isNotEmpty) 'recentOperations': recentOperations,
    'app': {
      'version': appVersion,
      'device': device,
      'os': os,
    },
    if (traceId != null) 'traceId': traceId,
    if (sessionId != null) 'sessionId': sessionId,
    'captureMode': captureMode.name,
    'includeDocumentContent': includeDocumentContent,
  };
}