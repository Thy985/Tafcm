/// ObservabilityService：编辑器可观测系统统一 Facade。
///
/// 作为所有 Tracer 和 Trace Context 的持有者，通过可选参数注入到
/// CommandHandler / TransactionBuilder。不修改任何业务逻辑接口。
///
/// 落地 ADR-0021 §2.6（EditorTraceContext）+ §2.7（InvariantChecker）
/// + §3.7.2（ErrorSnapshotter）+ §3.7.3（InteractionTracer + ExportPipeline）。
library;

import 'package:flutter/foundation.dart';

import '../../presentation/commands/command_handler.dart';
import 'command_replayer.dart';
import 'command_tracer.dart';
import 'error_snapshot.dart';
import 'error_snapshotter.dart';
import 'export_pipeline.dart';
import 'interaction_tracer.dart';
import 'invariant_checker.dart';
import 'models.dart';
import 'trace_context.dart';
import 'transaction_tracer.dart';

/// 编辑器可观测系统统一 Facade。
///
/// 持有 [CommandTracer]、[TransactionTracer]、[InteractionTracer]、
/// [EditorTraceContext] 等。
/// 通过可选参数注入到 [CommandHandler] 和 [TransactionBuilder]。
class ObservabilityService {
  final ObservabilityConfig config;
  final CommandTracer commandTracer;
  final TransactionTracer transactionTracer;

  /// 用户交互轨迹记录器（Phase 3.7.3）。
  final InteractionTracer interactionTracer;

  final InvariantChecker Function() invariantCheckerFactory;

  /// 错误快照捕获器（LIGHT/FULL 模式自动创建，OFF 模式为 null）。
  ///
  /// P0 修复（2026-08-04）：原实现为 `final ErrorSnapshotter? errorSnapshotter`
  /// + 构造参数注入，但生产代码（editor_providers.dart）用 `ObservabilityService()`
  /// 无参构造 → errorSnapshotter 永远为 null → `captureError()` 空操作 →
  /// `snapshot.json` 永远缺失。改为构造体内自动创建，外部测试仍可注入 mock。
  late final ErrorSnapshotter? _errorSnapshotter;

  /// 诊断导出管道（Phase 3.7.3，懒初始化）。
  ExportPipeline? _exportPipeline;

  /// 当前 Trace Context（由 EditorCoordinator.handle() 设置）。
  EditorTraceContext? _currentContext;

  /// 会话 ID（App 启动时生成）。
  final String sessionId;

  ObservabilityService({
    this.config = ObservabilityConfig.light,
    CommandTracer? commandTracer,
    TransactionTracer? transactionTracer,
    InteractionTracer? interactionTracer,
    InvariantChecker Function()? invariantCheckerFactory,
    ErrorSnapshotter? errorSnapshotter,
  })  : commandTracer = commandTracer ?? CommandTracer(),
        transactionTracer = transactionTracer ?? TransactionTracer(),
        interactionTracer = interactionTracer ?? InteractionTracer(),
        invariantCheckerFactory =
            invariantCheckerFactory ?? (() => InvariantChecker()),
        sessionId = TraceIdGenerator.sessionId() {
    // P0 修复（2026-08-04）：LIGHT/FULL 模式自动创建 ErrorSnapshotter。
    // 外部传入 mock 时优先用 mock（测试场景）；否则在非 OFF 模式自动创建。
    _errorSnapshotter = errorSnapshotter ??
        (isEnabled ? ErrorSnapshotter(observability: this) : null);
  }

  /// 错误快照捕获器（只读 getter）。
  ErrorSnapshotter? get errorSnapshotter => _errorSnapshotter;

  /// 当前 Trace Context。
  EditorTraceContext? get currentContext => _currentContext;

  /// 设置当前 Trace Context（由 EditorCoordinator.handle() 调用）。
  void setTraceContext(EditorTraceContext context) {
    _currentContext = context;
  }

  /// 清空 Trace Context。
  void clearTraceContext() {
    _currentContext = null;
  }

  /// 是否处于 LIGHT 或 FULL 模式。
  bool get isEnabled => config.level != ObservabilityLevel.off;

  /// 是否处于 FULL 模式。
  bool get isFull => config.level == ObservabilityLevel.full;

  /// 获取 ExportPipeline 实例（懒初始化）。
  ExportPipeline get exportPipeline =>
      _exportPipeline ??= ExportPipeline(this);

  // ============ Command Trace ============

  /// 记录 Command 执行轨迹。
  ///
  /// **P1 信噪比修复（2026-08-06）**：
  /// - LIGHT 模式：仅失败（succeeded=false）的 Command 输出 debugPrint，
  ///   成功 Command 静默入 RingBuffer（用户主动导出诊断时才用到）。
  /// - FULL 模式：保留全量 debugPrint（开发者主动开启的 verbose 模式）。
  /// - 失败 Command 是"信号"，成功 Command 是"噪声"——LIGHT 模式只放信号过。
  void recordCommand(CommandTraceEntry entry) {
    if (!isEnabled) return;
    if (isFull || !entry.succeeded) {
      debugPrint('[OBS] Command: ${entry.commandName}'
          ' | txId=${entry.transactionId}'
          ' | traceId=${_prefix(entry.traceId, 8)}'
          ' | before=${_prefix(entry.beforeStateHash, 6)}'
          ' | after=${_prefix(entry.afterStateHash, 6)}'
          ' | ok=${entry.succeeded}'
          ' | params=${entry.params}');
    }
    commandTracer.record(entry);
  }

  // ============ Transaction Trace ============

  /// 记录 Transaction 状态变化。
  ///
  /// **P1 信噪比修复（2026-08-06）**：
  /// - LIGHT 模式：仅 rollback 输出 debugPrint（commit 是常态，rollback是信号）。
  /// - FULL 模式：保留全量 debugPrint。
  void recordTransaction(TransactionTraceEntry entry) {
    if (!isEnabled) return;
    if (isFull || entry.result != TransactionResult.commit) {
      debugPrint('[OBS] Transaction: ${entry.transactionId}'
          ' | result=${entry.result.name}'
          ' | ops=${entry.operations.map((o) => o.type).join(',')}'
          ' | before=${_prefix(entry.beforeHash, 6)}'
          ' | after=${_prefix(entry.afterHash, 6)}'
          ' | elapsed=${entry.elapsed.inMilliseconds}ms'
          ' | traceId=${_prefix(entry.traceId, 8)}');
    }
    transactionTracer.record(entry);
  }

  // ============ Interaction Trace（§3.7.3） ============

  /// 记录用户交互事件。
  ///
  /// **P1 信噪比修复（2026-08-06）**：
  /// - LIGHT 模式：UserInput / UserTap / UserFormatToggle 是高频常态事件，
  ///   静默入 RingBuffer；UserUndoRedo 频率低且语义重要，保留 debugPrint。
  /// - FULL 模式：保留全量 debugPrint。
  void recordInteraction(EditorInteractionEvent event) {
    if (!isEnabled) return;
    if (isFull || event is UserUndoRedo) {
      debugPrint('[OBS] Interaction: ${event.runtimeType}'
          ' | ${_describeInteraction(event)}');
    }
    _checkTapJitter(event);
    interactionTracer.record(event);
  }

  /// 检测触摸抖动：同一 target 300ms 内重复 UserTap 超过 2 次。
  void _checkTapJitter(EditorInteractionEvent event) {
    if (event is! UserTap) return;
    final now = event.timestamp;
    final recentTaps = interactionTracer.entries
        .whereType<UserTap>()
        .where((e) =>
            e.target == event.target &&
            now.difference(e.timestamp).inMilliseconds < 300)
        .length;
    if (recentTaps >= 2) {
      debugPrint('[OBS] TapJitterDetected: target=${event.target}'
          ' | count=${recentTaps + 1}'
          ' | window=300ms');
    }
  }

  /// 描述交互事件（用于调试日志）。
  ///
  /// **P1 信噪比修复（2026-08-06）**：UserInput 改为脱敏描述
  /// （length/hasNewline/isAscii），不再打印原始文本。
  String _describeInteraction(EditorInteractionEvent event) {
    return switch (event) {
      UserTap(:final target) => 'target=$target',
      UserInput(:final length, :final hasNewline, :final isAscii) =>
        'len=$length nl=$hasNewline ascii=$isAscii',
      UserDelete(:final count) => 'count=$count',
      UserFormatToggle(:final format) => 'format=$format',
      UserUndoRedo(:final isUndo) => 'action=${isUndo ? "Undo" : "Redo"}',
      UserLongPress(:final target) => 'target=$target',
    };
  }

  /// 安全截取字符串前缀（避免短字符串崩溃）。
  String _prefix(String? s, int len) {
    if (s == null) return 'null';
    return s.length <= len ? s : s.substring(0, len);
  }

  // ============ Invariant Checker ============

  /// 运行不变量检查，返回失败列表。
  List<InvariantFailure> checkInvariants(
      List<EditorInvariantContext> state) {
    if (!isEnabled) return [];
    final checker = invariantCheckerFactory();
    return checker.checkAll(state);
  }

  // ============ Error Snapshot（§3.7.2） ============

  /// 捕获错误快照。
  ///
  /// 委托给 [errorSnapshotter] 生成 [ErrorSnapshot]。
  /// 若无 errorSnapshotter（OFF 模式），返回 null。
  ErrorSnapshot? captureError({
    required String type,
    required String message,
    String? commandName,
    Map<String, Object?>? commandParams,
    String? cursorBlockId,
    int? cursorOffset,
  }) {
    if (!isEnabled) return null;
    return errorSnapshotter?.capture(
      type: type,
      message: message,
      commandName: commandName,
      commandParams: commandParams,
      cursorBlockId: cursorBlockId,
      cursorOffset: cursorOffset,
    );
  }

  /// 获取最近一次错误快照。
  ErrorSnapshot? get lastErrorSnapshot => errorSnapshotter?.lastSnapshot;

  // ============ Export（§3.7.3） ============

  /// 导出诊断 zip 文件。
  ///
  /// 委托给 [ExportPipeline] 生成 zip 包。
  Future<String?> exportDiagnosticZip({String? outputDir}) {
    if (!isEnabled) return Future.value(null);
    return exportPipeline.export(outputDir: outputDir);
  }

  /// 导出当前 Trace 数据（用于诊断）。
  ///
  /// 返回一个 JSON 兼容的 Map，包含所有 Trace 记录。
  Map<String, Object?> exportSnapshot() {
    if (!isEnabled) return {'level': 'off'};
    return {
      'sessionId': sessionId,
      'level': config.level.name,
      'commandCount': commandTracer.count,
      'transactionCount': transactionTracer.count,
      'interactionCount': interactionTracer.count,
      'commands': commandTracer.entries.map((e) => {
        'commandName': e.commandName,
        'params': e.params,
        'origin': e.origin.name,
        'timestamp': e.timestamp.toIso8601String(),
        'succeeded': e.succeeded,
        if (e.errorMessage != null) 'errorMessage': e.errorMessage,
        if (e.beforeStateHash != null) 'beforeStateHash': e.beforeStateHash,
        if (e.afterStateHash != null) 'afterStateHash': e.afterStateHash,
        if (e.traceId != null) 'traceId': e.traceId,
      }).toList(),
      'transactions': transactionTracer.entries.map((e) => {
        'transactionId': e.transactionId,
        'origin': e.origin.name,
        'result': e.result.name,
        'beforeHash': e.beforeHash,
        'afterHash': e.afterHash,
        if (e.rollbackReason != null) 'rollbackReason': e.rollbackReason,
        if (e.traceId != null) 'traceId': e.traceId,
      }).toList(),
      'interactions': interactionTracer.entries.map((e) {
        return switch (e) {
          UserTap(:final target, :final timestamp) => <String, Object?>{
            'type': 'UserTap',
            'target': target,
            'timestamp': timestamp.toIso8601String(),
          },
          UserInput(
            :final length,
            :final hasNewline,
            :final isAscii,
            :final timestamp
          ) =>
            <String, Object?>{
              'type': 'UserInput',
              'length': length,
              'hasNewline': hasNewline,
              'isAscii': isAscii,
              'timestamp': timestamp.toIso8601String(),
            },
          UserDelete(:final count, :final timestamp) => <String, Object?>{
            'type': 'UserDelete',
            'count': count,
            'timestamp': timestamp.toIso8601String(),
          },
          UserFormatToggle(:final format, :final timestamp) => <String, Object?>{
            'type': 'UserFormatToggle',
            'format': format,
            'timestamp': timestamp.toIso8601String(),
          },
          UserUndoRedo(:final isUndo, :final timestamp) => <String, Object?>{
            'type': 'UserUndoRedo',
            'isUndo': isUndo,
            'timestamp': timestamp.toIso8601String(),
          },
          UserLongPress(:final target, :final timestamp) => <String, Object?>{
            'type': 'UserLongPress',
            'target': target,
            'timestamp': timestamp.toIso8601String(),
          },
        };
      }).toList(),
    };
  }

  // ============ Command Replay（§3.7.4） ============

  /// 导出 Command 事件流（用于 Replay）。
  ///
  /// 返回 [ReplayCommandEvent] 列表，可序列化为 JSON 供
  /// [CommandReplayer] 加载重放。
  List<ReplayCommandEvent> exportCommandStream() {
    if (!isEnabled) return [];
    return commandTracer.entries
        .map(CommandReplayer.fromTraceEntry)
        .toList();
  }

  /// 从已记录的 Command 事件流创建 [CommandReplayer]。
  ///
  /// [handler]：必须从固定 seed document 初始化的 [CommandHandler]。
  CommandReplayer createReplayer(CommandHandler handler) {
    return CommandReplayer(
      handler: handler,
      events: exportCommandStream(),
    );
  }

  /// 清空所有记录。
  void clear() {
    commandTracer.clear();
    transactionTracer.clear();
    interactionTracer.clear();
    clearTraceContext();
  }
}