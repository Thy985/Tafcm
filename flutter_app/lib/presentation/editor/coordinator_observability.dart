/// CoordinatorObservability（#246 行数拆分辅助）。
///
/// **为什么抽出来**：`EditorCoordinator` 有 TC-ARCH-UI-4 硬约束 ——
/// 文件 ≤ 260 行（见 `test/architecture/ui_god_object_test.dart`）。
/// #246 加上字段级 notifier 后本文件会突破上限，故把「非协调职责」拆出：
/// - 本文件：可观测性上报（trace / interaction / 诊断导出）
/// - `coordinator_change_notifier.dart`：变更广播
///
/// **刻意不写成 `mixin ... on EditorCoordinator`**：那会让本文件 import
/// `editor_coordinator.dart`，而后者也要 import 本文件，形成循环依赖 ——
/// Dart 解析 `on` 子句时因循环拿不到成员，编译报
/// "The method '_recordInteraction' isn't defined"。改为「普通类 + 显式参数」。
///
/// 本类是纯「往 observability 服务写日志」的转发层，不含领域判断，
/// 与 `EditorCoordinator` 的命令协调 / 焦点 / undo 职责正交。
library;

import '../../core/observability/models.dart' as obs;
import '../../core/observability/observability_service.dart';
import '../../core/observability/trace_context.dart';
import '../commands/editor_command.dart';

/// ADR-0021 / Phase 3.7.3：可观测性上报入口。
class CoordinatorObservability {
  CoordinatorObservability(this._service);

  /// 可为 null（未接入可观测的 LIGHT 模式）。
  final ObservabilityService? _service;

  /// ADR-0021 §2.6：开始新的用户交互，生成新 traceId。
  ///
  /// 在 dispatch / setFocus / undo / redo 等用户交互入口调用，
  /// 不在 handle() 内调用（一次交互可能派发多个 command，共享同一 traceId）。
  void beginUserInteraction() {
    final svc = _service;
    if (svc?.isEnabled == true) {
      svc!.setTraceContext(EditorTraceContext(
        sessionId: svc.sessionId,
        traceId: TraceIdGenerator.traceId(),
        spanId: TraceIdGenerator.commandSpanId(),
      ));
    }
  }

  /// 记录用户交互事件（Phase 3.7.3）。
  void recordInteraction(obs.EditorInteractionEvent event) {
    _service?.recordInteraction(event);
  }

  /// 导出诊断数据 zip（Phase 3.7.3）。
  ///
  /// 委托给 [ObservabilityService.exportDiagnosticZip]。
  /// 返回 zip 文件路径，失败或未启用时返回 null。
  Future<String?> exportDiagnosticZip({String? outputDir}) {
    final svc = _service;
    if (svc == null) return Future.value(null);
    return svc.exportDiagnosticZip(outputDir: outputDir);
  }

  /// 根据 Command 类型记录交互事件。
  ///
  /// **P1 信噪比修复（2026-08-06）**：UserInput 改用 [UserInput.fromText]
  /// 工厂，仅记录 length/hasNewline/isAscii 三项脱敏元信息，
  /// 不再传入原始 [InsertTextCommand.text]。
  void recordInteractionForCommand(EditorCommand command) {
    final now = DateTime.now();
    switch (command) {
      case InsertTextCommand c:
        recordInteraction(obs.UserInput.fromText(c.text, now));
      case WrapSelectionCommand c:
        recordInteraction(obs.UserFormatToggle(
          format: '${c.prefix}${c.suffix}',
          timestamp: now,
        ));
      default:
        break;
    }
  }
}