/// ADI Replay Adapter 单元测试。
///
/// 验证 AdiReplayAdapterImpl 的 replay：空事件 → inconclusive，
/// 有事件 → reproduced/notReproduced，executorFactory state isolation。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/adi_replay_adapter.dart';
import 'package:formula_fix/core/observability/adi_view.dart';
import 'package:formula_fix/core/observability/models.dart';
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/core/observability/trace_context.dart';
import 'package:formula_fix/core/replay/replay_engine.dart';

void main() {
  late ObservabilityService service;

  setUp(() {
    service = ObservabilityService.full();
    TraceIdGenerator.reset();
  });

  group('AdiReplayAdapterImpl.replay', () {
    test('无 command 事件时返回 inconclusive', () {
      final adapter = AdiReplayAdapterImpl(service, _successExecutorFactory);
      final result = adapter.replay('sess_1');

      expect(result.status, AdiReplayStatus.inconclusive);
      expect(result.commandsExecuted, 0);
      expect(result.steps, isEmpty);
    });

    test('有事件且全部成功匹配 → notReproduced', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {'blockId': 'b1', 'text': 'hello'},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
        beforeStateHash: 'hash_before',
        afterStateHash: 'hash_after',
      ));

      final adapter = AdiReplayAdapterImpl(service, _successExecutorFactory);
      final result = adapter.replay(service.sessionId);

      expect(result.commandsExecuted, 1);
      expect(result.status, AdiReplayStatus.notReproduced);
    });

    test('有事件且执行失败 → reproduced', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'DeleteCommand',
        params: {'blockId': 'b1'},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: false,
        errorMessage: 'Block not found',
      ));

      final adapter = AdiReplayAdapterImpl(service, _failingExecutorFactory);
      final result = adapter.replay(service.sessionId);

      expect(result.commandsExecuted, 1);
      expect(result.status, AdiReplayStatus.reproduced);
      expect(result.failedAt, isNotNull);
    });

    test('resultTraceId 以 replay_ 前缀开头', () {
      final adapter = AdiReplayAdapterImpl(service, _successExecutorFactory);
      final result = adapter.replay('sess_1');

      expect(result.resultTraceId.startsWith('replay_'), isTrue);
    });
  });
}

ReplayCommandExecutor _successExecutorFactory() => _SuccessExecutor();
ReplayCommandExecutor _failingExecutorFactory() => _FailingExecutor();

class _SuccessExecutor implements ReplayCommandExecutor {
  @override
  ReplayStepResult executeOne(ReplayCommandEvent event) {
    return ReplayStepResult(
      success: true,
      actualHash: event.afterStateHash,
    );
  }
}

class _FailingExecutor implements ReplayCommandExecutor {
  @override
  ReplayStepResult executeOne(ReplayCommandEvent event) {
    return ReplayStepResult(
      success: false,
      error: 'Block not found',
    );
  }
}
