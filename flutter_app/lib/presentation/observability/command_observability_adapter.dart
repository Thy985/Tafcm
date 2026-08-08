/// CommandObservabilityAdapter：从 CommandHandler 抽取的可观测性适配器。
///
/// 将 Command Trace 记录、Error Snapshot 捕获、Invariant Check 等
/// 可观测性逻辑从 CommandHandler 中分离，降低 command_handler.dart 行数
/// 并提升可测试性。
///
/// 落地 ADR-0021 §2.2-2.7。
library;

import '../../core/editing/document_editor.dart';
import '../../core/editing/edit_operation.dart';
import '../../core/editing/editor_history.dart';
import '../../core/editing/transaction.dart';
import '../../core/observability/invariant_checker.dart';
import '../../core/observability/models.dart' as obs;
import '../../core/observability/observability_service.dart';
import '../commands/commands.dart';
import 'command_replayer.dart';

/// 可观测性适配器：封装 CommandHandler 中所有 observability 相关逻辑。
class CommandObservabilityAdapter {
  final ObservabilityService? observability;
  final DocumentEditor editor;
  final EditorHistory history;

  CommandObservabilityAdapter({
    required this.observability,
    required this.editor,
    required this.history,
  });

  /// Transaction commit 后运行不变量检查（ADR-0021 §2.7）。
  ///
  /// 检查失败不阻塞编辑器运行，但自动触发 Error Snapshot。
  void runInvariantCheck() {
    final svc = observability;
    if (svc?.isEnabled != true) return;

    final historyBlockIds = <String>{};
    Transaction? lastTx = history.lastOrNull;
    if (lastTx != null) {
      for (final op in lastTx.ops) {
        if (op is TextOperation) {
          historyBlockIds.add(op.blockId.value);
        }
      }
    }

    final state = editor.allIds
        .map((id) {
          final element = editor.getBlock(id);
          return element != null
              ? EditorInvariantContext(
                  blockId: id.value,
                  element: element,
                  historyBlockIds: historyBlockIds,
                )
              : null;
        })
        .whereType<EditorInvariantContext>()
        .toList();

    final failures = svc!.checkInvariants(state);
    if (failures.isNotEmpty) {
      svc.captureError(
        type: 'InvariantViolation',
        message: 'Invariant check failed: ${failures.map((f) => f.invariantName).join(", ")}',
        commandName: 'InvariantChecker',
      );
    }
  }

  /// 捕获 Command 执行异常并生成 Error Snapshot。
  void captureCommandError(EditorCommand command, Object error) {
    final svc = observability;
    if (svc?.isEnabled != true) return;

    svc!.captureError(
      type: 'CommandExecutionError',
      message: error.toString(),
      commandName: command.runtimeType.toString(),
      commandParams: {'displayName': command.displayName},
    );
  }

  /// 记录 Command 执行轨迹到 ObservabilityService。
  void recordCommandTrace(
    EditorCommand command,
    bool success,
    String? beforeHash,
    String? afterHash,
    TransactionId transactionId,
  ) {
    final svc = observability;
    if (svc?.isEnabled != true) return;
    final ctx = svc!.currentContext;

    final replayEvent = CommandReplayer.serialize(command);
    final params = replayEvent.params;

    svc.recordCommand(obs.CommandTraceEntry(
      commandName: command.runtimeType.toString(),
      params: params,
      origin: _mapOrigin(command.origin),
      timestamp: DateTime.now(),
      transactionId: transactionId.toString(),
      succeeded: success,
      beforeStateHash: beforeHash,
      afterStateHash: afterHash,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
    ));
  }

  obs.CommandOrigin _mapOrigin(CommandOrigin origin) {
    return switch (origin) {
      CommandOrigin.keyboard => obs.CommandOrigin.keyboard,
      CommandOrigin.ime => obs.CommandOrigin.ime,
      CommandOrigin.ai => obs.CommandOrigin.ai,
      CommandOrigin.voice => obs.CommandOrigin.voice,
      CommandOrigin.menu => obs.CommandOrigin.menu,
      CommandOrigin.gesture => obs.CommandOrigin.gesture,
    };
  }
}