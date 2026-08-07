/// Observability System 数据模型。
///
/// 定义所有 Trace 事件/条目的数据类型，包括：
/// - [CommandTraceEntry]：Command 执行轨迹
/// - [TransactionTraceEntry]：Transaction 状态变化
/// - [EditorInteractionEvent] 及其子类：用户交互事件
/// - [InvariantFailure]：不变量检查失败记录
/// - [ObservabilityLevel]：可观测性级别
///
/// 落地 ADR-0021 §2.1-2.7。
library;

/// 可观测性级别。
///
/// 决定哪些事件被记录、是否写盘、是否包含正文。
/// 落地 ADR-0021 §3.3（三级模式）。
enum ObservabilityLevel {
  /// 关闭 — tree-shaking 移除全部代码。
  off,

  /// 轻量 — 仅保留环形缓冲区，不写盘，不包含正文。
  light,

  /// 完整 — 全部记录，含 Interaction Trace + AST snapshot + document content。
  full,
}

/// Command 来源枚举。
///
/// 与 [CommandOrigin] 对应，用于 Trace 记录。
enum CommandOrigin {
  keyboard,
  ime,
  ai,
  voice,
  menu,
  gesture,
}

/// Transaction 来源枚举。
///
/// 与 [TransactionOrigin] 对应，用于 Trace 记录。
enum TransactionOrigin {
  keyboard,
  ime,
  paste,
  programmatic,
  undo,
  redo,
}

/// Transaction 执行结果。
enum TransactionResult {
  commit,
  rollback,
}

/// Command 执行轨迹条目。
///
/// 记录每个 [EditorCommand] 的执行参数、结果、状态变化。
/// 落地 ADR-0021 §2.2。
class CommandTraceEntry {
  final String commandName; // "InsertTextCommand"
  final Map<String, Object?> params; // {blockId: "abc", offset: 0, text: "hello"}
  final CommandOrigin origin;
  final DateTime timestamp;
  final String? transactionId; // 关联的 Transaction ID
  final bool succeeded;
  final String? errorMessage;

  // === State Checkpoint（Replay 确定性关键） ===
  final String? beforeStateHash; // Command 执行前的 Document fingerprint
  final String? afterStateHash; // Command 执行后的 Document fingerprint
  final String? preconditionHash; // 执行前提的 fingerprint

  // === Trace Context ===
  final String? traceId;
  final String? spanId;

  const CommandTraceEntry({
    required this.commandName,
    required this.params,
    required this.origin,
    required this.timestamp,
    this.transactionId,
    required this.succeeded,
    this.errorMessage,
    this.beforeStateHash,
    this.afterStateHash,
    this.preconditionHash,
    this.traceId,
    this.spanId,
  });
}

/// 操作摘要（用于 Transaction Trace 的 operations 列表）。
class OperationSummary {
  final String type; // "InsertText", "Delete", "UpdateSource", etc.
  final String blockId;
  final String? detail;

  const OperationSummary({
    required this.type,
    required this.blockId,
    this.detail,
  });
}

/// Transaction 状态变化条目。
///
/// 记录每个 Transaction 的 before/after 状态。
/// 落地 ADR-0021 §2.3。
class TransactionTraceEntry {
  final String transactionId;
  final TransactionOrigin origin;
  final String beforeSnapshot; // 事务前的 blocks source 摘要
  final String beforeHash; // 事务前 Document fingerprint
  final List<OperationSummary> operations; // 操作列表
  final String afterSnapshot; // 事务后的 blocks source 摘要
  final String afterHash; // 事务后 Document fingerprint
  final TransactionResult result;
  final String? rollbackReason;
  final Duration elapsed; // 执行耗时

  // === Trace Context ===
  final String? traceId;
  final String? spanId;

  const TransactionTraceEntry({
    required this.transactionId,
    required this.origin,
    required this.beforeSnapshot,
    required this.beforeHash,
    required this.operations,
    required this.afterSnapshot,
    required this.afterHash,
    required this.result,
    this.rollbackReason,
    required this.elapsed,
    this.traceId,
    this.spanId,
  });
}

/// 用户交互事件（sealed class）。
///
/// 仅记录语义层事件，不记录底层 Flutter Event。
/// 落地 ADR-0021 §2.1。
sealed class EditorInteractionEvent {
  DateTime get timestamp;

  const EditorInteractionEvent();
}

class UserTap extends EditorInteractionEvent {
  final String target;
  @override
  final DateTime timestamp;

  const UserTap({required this.target, required this.timestamp});
}

/// 用户输入事件。
///
/// **P1 信噪比修复（2026-08-06）**：脱敏 — 不再记录原始 [text]，
/// 改为 [length] + [hasNewline] + [isAscii] 三项元信息。理由：
/// 1. 与 [MermaidService] / [FormulaSvgService] 的"不传敏感原文"原则对齐
///    （见 mermaid_service.dart:407 / formula_svg_service.dart:311）
/// 2. 用户笔记可能含敏感内容（密码、私人信息），trace 导出 zip 时
///    不应一并泄露
/// 3. 调试场景下"输入了几字符 + 是否含换行 + 是否 ASCII"已足够定位
///    IME / 退格 / 复制粘贴类问题
class UserInput extends EditorInteractionEvent {
  /// 原始文本长度（脱敏：仅长度，不含内容）。
  final int length;

  /// 是否含换行符（用于调试 Enter 拆块 / IME 组合态场景）。
  final bool hasNewline;

  /// 是否纯 ASCII（用于调试中文 IME 与英文输入的差异）。
  final bool isAscii;

  @override
  final DateTime timestamp;

  const UserInput({
    required this.length,
    required this.hasNewline,
    required this.isAscii,
    required this.timestamp,
  });

  /// 便利工厂：从原始 text 提取脱敏元信息。
  factory UserInput.fromText(String text, DateTime timestamp) {
    return UserInput(
      length: text.length,
      hasNewline: text.contains('\n'),
      isAscii: text.codeUnits.every((c) => c < 128),
      timestamp: timestamp,
    );
  }
}

class UserDelete extends EditorInteractionEvent {
  final int count;
  @override
  final DateTime timestamp;

  const UserDelete({required this.count, required this.timestamp});
}

class UserFormatToggle extends EditorInteractionEvent {
  final String format;
  @override
  final DateTime timestamp;

  const UserFormatToggle({required this.format, required this.timestamp});
}

class UserUndoRedo extends EditorInteractionEvent {
  final bool isUndo;
  @override
  final DateTime timestamp;

  const UserUndoRedo({required this.isUndo, required this.timestamp});
}

/// 用户长按事件（移动端核心交互，触发 BlockToolbar）。
class UserLongPress extends EditorInteractionEvent {
  final String target;
  @override
  final DateTime timestamp;

  const UserLongPress({required this.target, required this.timestamp});
}

/// 不变量检查失败记录。
///
/// 落地 ADR-0021 §2.7（Layer 0 Invariant Checker）。
class InvariantFailure {
  final String invariantName;
  final String message;
  final DateTime timestamp;
  final String? stateHash;

  const InvariantFailure({
    required this.invariantName,
    required this.message,
    required this.timestamp,
    this.stateHash,
  });
}

/// 可观测性模式的配置。
///
/// 控制记录级别、环形缓冲区大小、隐私保护等。
class ObservabilityConfig {
  final ObservabilityLevel level;
  final int commandBufferSize;
  final int transactionBufferSize;
  final int interactionBufferSize;

  const ObservabilityConfig({
    this.level = ObservabilityLevel.light,
    this.commandBufferSize = 500,
    this.transactionBufferSize = 50,
    this.interactionBufferSize = 1000,
  });

  /// LIGHT 模式默认配置。
  static const light = ObservabilityConfig(
    level: ObservabilityLevel.light,
    commandBufferSize: 500,
    transactionBufferSize: 50,
    interactionBufferSize: 1000,
  );

  /// FULL 模式默认配置。
  static const full = ObservabilityConfig(
    level: ObservabilityLevel.full,
    commandBufferSize: 500,
    transactionBufferSize: 50,
    interactionBufferSize: 1000,
  );

  /// OFF 模式（tree-shaking 移除）。
  static const off = ObservabilityConfig(
    level: ObservabilityLevel.off,
  );
}