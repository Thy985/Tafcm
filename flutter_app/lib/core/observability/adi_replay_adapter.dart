/// ADI Replay Adapter：replay_engine → Replay 协议。
///
/// 把 ReplayEngine 的重放能力包装为 Agent 可调用的 Replay 协议。
/// 从 ObservabilityService 导出 Command 事件流，驱动 ReplayEngine 重放。
///
/// 落地 ADR-0024 §2.3（Replay Adapter）。
library;

import '../replay/replay_engine.dart';
import 'adi_view.dart';

import 'observability_service.dart';

/// 重放适配器抽象接口。
abstract class AdiReplayAdapter {
  AdiReplayResultView replay(String sessionId);
}

/// 重放适配器实现。
///
/// 需要 Agent 提供 [ReplayCommandExecutor]（presentation 层注入），
/// 因为 Command 反序列化依赖 EditorCommand（presentation 层类型）。
///
/// `executorFactory` 是工厂函数而非直接实例：每次 replay 创建新 executor，
/// 避免上一次 replay 的残余状态污染本次重放（state isolation）。
class AdiReplayAdapterImpl implements AdiReplayAdapter {
  final ObservabilityService _service;
  final ReplayCommandExecutor Function() executorFactory;

  AdiReplayAdapterImpl(this._service, this.executorFactory);

  @override
  AdiReplayResultView replay(String sessionId) {
    final events = _service.exportCommandStream();
    if (events.isEmpty) {
      return AdiReplayResultView(
        status: AdiReplayStatus.inconclusive,
        commandsExecuted: 0,
        resultTraceId: 'replay_${DateTime.now().millisecondsSinceEpoch}',
        steps: const [],
      );
    }

    final executor = executorFactory();
    final engine = ReplayEngine(executor: executor, events: events);
    final results = engine.replay();

    final steps = results
        .map((r) => AdiReplayStepView(
              index: r.index,
              commandName: r.commandName,
              success: r.success,
              hashMatch: r.hashMatch,
              error: r.error,
            ))
        .toList();

    final hasFailure = results.any((r) => !r.success || !r.hashMatch);
    final failedAt = results
        .where((r) => !r.success || !r.hashMatch)
        .firstOrNull;

    return AdiReplayResultView(
      status: hasFailure ? AdiReplayStatus.reproduced : AdiReplayStatus.notReproduced,
      failedAt: failedAt != null
          ? 'step ${failedAt.index}: ${failedAt.commandName}'
          : null,
      commandsExecuted: results.length,
      resultTraceId: 'replay_${DateTime.now().millisecondsSinceEpoch}',
      steps: steps,
    );
  }
}