/// ReplayEngine：从 CommandReplayer Extract 的核心重放引擎。
///
/// 负责：逐条驱动 [ReplayCommandEvent] 事件流，收集 [ReplayResult]，
/// 验证 afterStateHash 一致性。不依赖 presentation 层——具体的
/// "反序列化 + 执行 + fingerprint 计算" 由 [ReplayCommandExecutor] 实现。
///
/// 落地 ADR-0024 §2.3（Replay Adapter Extract 而非 Move）。
/// 依赖契约：✅ core/editing / ✅ core/observability / ❌ presentation / ❌ domain
library;

import '../observability/models.dart';

/// 单条 Command 执行结果（executor 返回给 engine）。
class ReplayStepResult {
  /// CommandHandler.handle() 是否返回 true。
  final bool success;

  /// 实际 Document fingerprint（用于与 event.afterStateHash 对比）。
  final String? actualHash;

  /// 错误信息（反序列化失败 / 执行异常）。
  final String? error;

  const ReplayStepResult({
    required this.success,
    this.actualHash,
    this.error,
  });
}

/// Command 执行器抽象接口。
///
/// presentation 层（[CommandReplayer]）实现此接口，
/// 负责 "反序列化 ReplayCommandEvent → EditorCommand + 执行 + 计算 fingerprint"。
/// core 层（[ReplayEngine]）仅依赖此接口，不依赖 presentation 具体实现。
abstract class ReplayCommandExecutor {
  /// 执行单条 replay 事件。
  ///
  /// 返回 [ReplayStepResult]，含 success / actualHash / error。
  ReplayStepResult executeOne(ReplayCommandEvent event);
}

/// 核心重放引擎。
///
/// 从 [ReplayCommandEvent] 列表逐条驱动 [ReplayCommandExecutor]，
/// 每步验证 AST 状态是否符合预期（通过 fingerprint 对比）。
/// 某条失败不中断，继续执行后续事件，以便收集完整回放报告。
///
/// **确定性保证**：
/// 1. executor 必须从固定 seed document 初始化（相同 BlockId 分配）
/// 2. 非确定性操作（DateTime.now()、随机数等）在 replay 中不启用
/// 3. BlockId 由 seed document 中的固定 ID 决定
class ReplayEngine {
  final ReplayCommandExecutor executor;
  final List<ReplayCommandEvent> events;
  int _index = 0;
  final List<ReplayResult> _results = [];

  ReplayEngine({
    required this.executor,
    required this.events,
  });

  /// 当前回放位置。
  int get index => _index;

  /// 已完成的回放结果列表。
  List<ReplayResult> get results => List.unmodifiable(_results);

  /// 是否所有已回放命令均成功且 hash 匹配。
  bool get allSucceeded =>
      _results.isNotEmpty && _results.every((r) => r.success && r.hashMatch);

  /// 失败的条数。
  int get failureCount =>
      _results.where((r) => !r.success || !r.hashMatch).length;

  /// 逐条重放所有 Command。
  ///
  /// 返回 [ReplayResult] 列表，每条对应一个事件。
  /// 若某条失败，继续执行后续事件（不中断），以便收集完整回放报告。
  List<ReplayResult> replay() {
    _results.clear();
    _index = 0;

    for (final event in events) {
      final result = _replayOne(event, _index);
      _results.add(result);
      _index++;
    }

    return List.unmodifiable(_results);
  }

  /// 从指定位置开始重放。
  ///
  /// [startIndex]：起始事件序号（0-based）。
  /// 用于断点续放：从失败位置的上一步重新开始。
  List<ReplayResult> replayFrom(int startIndex) {
    _results.clear();
    _index = startIndex;

    for (int i = startIndex; i < events.length; i++) {
      final result = _replayOne(events[i], i);
      _results.add(result);
      _index = i + 1;
    }

    return List.unmodifiable(_results);
  }

  /// 重放单条 Command。
  ReplayResult _replayOne(ReplayCommandEvent event, int index) {
    final stepResult = executor.executeOne(event);

    if (stepResult.error != null) {
      return ReplayResult(
        index: index,
        commandName: event.commandName,
        success: stepResult.success,
        hashMatch: false,
        actualHash: stepResult.actualHash,
        expectedHash: event.afterStateHash,
        error: stepResult.error,
      );
    }

    final hashMatch = event.afterStateHash == null ||
        stepResult.actualHash == event.afterStateHash;

    return ReplayResult(
      index: index,
      commandName: event.commandName,
      success: stepResult.success,
      hashMatch: hashMatch,
      actualHash: stepResult.actualHash,
      expectedHash: event.afterStateHash,
    );
  }
}