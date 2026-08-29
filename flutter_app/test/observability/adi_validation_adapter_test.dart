/// ADI Validation Adapter 单元测试。
///
/// 验证 AdiValidationAdapterImpl.validate：
/// - replay notReproduced + invariant allPassed → after: pass
/// - replay reproduced → after: stillFailing
/// - replay inconclusive → after: inconclusive
/// - invariant violated → after: stillFailing
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/observability/adi_replay_adapter.dart';
import 'package:tafcm/core/observability/adi_validation_adapter.dart';
import 'package:tafcm/core/observability/adi_view.dart';
import 'package:tafcm/core/observability/models.dart';
import 'package:tafcm/core/observability/observability_service.dart';
import 'package:tafcm/core/observability/trace_context.dart';
import 'package:tafcm/core/replay/replay_engine.dart';

void main() {
  late ObservabilityService service;

  setUp(() {
    service = ObservabilityService.full();
    TraceIdGenerator.reset();
  });

  group('AdiValidationAdapterImpl.validate', () {
    test('replay notReproduced + invariant allPassed → pass', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
        afterStateHash: 'hash_ok',
      ));
      service.updateInvariantReport(InvariantReportSnapshot(
        checkedAt: DateTime(2026, 8, 11),
        result: InvariantCheckResult.passed,
        failedNames: [],
        allNames: ['CursorExists', 'SelectionValid', 'BlockTreeAcyclic'],
      ));

      final replayAdapter = AdiReplayAdapterImpl(
        service,
        _successExecutorFactory,
      );
      final adapter = AdiValidationAdapterImpl(replayAdapter, service);
      final result = adapter.validate(sessionId: service.sessionId);

      expect(result.after, AdiValidationAfter.pass);
      expect(result.replayResult.status, AdiReplayStatus.notReproduced);
      expect(result.invariants.allPassed, isTrue);
    });

    test('replay reproduced → stillFailing', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'DeleteCommand',
        params: {},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: false,
        errorMessage: 'Block not found',
      ));

      final replayAdapter = AdiReplayAdapterImpl(
        service,
        _failingExecutorFactory,
      );
      final adapter = AdiValidationAdapterImpl(replayAdapter, service);
      final result = adapter.validate(sessionId: service.sessionId);

      expect(result.after, AdiValidationAfter.stillFailing);
      expect(result.replayResult.status, AdiReplayStatus.reproduced);
    });

    test('replay inconclusive → inconclusive', () {
      final replayAdapter = AdiReplayAdapterImpl(
        service,
        _successExecutorFactory,
      );
      final adapter = AdiValidationAdapterImpl(replayAdapter, service);
      final result = adapter.validate(sessionId: 'empty_session');

      expect(result.after, AdiValidationAfter.inconclusive);
      expect(result.replayResult.status, AdiReplayStatus.inconclusive);
    });

    test('invariant violated → stillFailing', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
        afterStateHash: 'hash_ok',
      ));
      service.updateInvariantReport(InvariantReportSnapshot(
        checkedAt: DateTime(2026, 8, 11),
        result: InvariantCheckResult.failed,
        failedNames: ['CursorExists'],
        allNames: ['CursorExists', 'SelectionValid'],
      ));

      final replayAdapter = AdiReplayAdapterImpl(
        service,
        _successExecutorFactory,
      );
      final adapter = AdiValidationAdapterImpl(replayAdapter, service);
      final result = adapter.validate(sessionId: service.sessionId);

      expect(result.after, AdiValidationAfter.stillFailing);
      expect(result.invariants.violated, ['CursorExists']);
    });

    test('toJson 包含 before/after/replayResult/invariants', () {
      final replayAdapter = AdiReplayAdapterImpl(
        service,
        _successExecutorFactory,
      );
      final adapter = AdiValidationAdapterImpl(replayAdapter, service);
      final result = adapter.validate(
        sessionId: 'test',
        before: AdiValidationBefore.crash,
      );
      final json = result.toJson();

      expect(json['before'], 'crash');
      expect(json['after'], isA<String>());
      expect(json.containsKey('replayResult'), isTrue);
      expect(json.containsKey('invariants'), isTrue);
    });

    test('cross-session invariant 隔离：不同 sessionId → inconclusive', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
        afterStateHash: 'hash_ok',
      ));
      service.updateInvariantReport(InvariantReportSnapshot(
        checkedAt: DateTime(2026, 8, 11),
        result: InvariantCheckResult.passed,
        failedNames: [],
        allNames: ['CursorExists'],
      ));

      final replayAdapter = AdiReplayAdapterImpl(
        service,
        _successExecutorFactory,
      );
      final adapter = AdiValidationAdapterImpl(replayAdapter, service);
      final result = adapter.validate(sessionId: 'different_session');

      expect(result.after, AdiValidationAfter.inconclusive);
      expect(result.crossSessionDataWarning, isTrue);
    });

    test('同 session invariant 不触发 crossSessionDataWarning', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
        afterStateHash: 'hash_ok',
      ));
      service.updateInvariantReport(InvariantReportSnapshot(
        checkedAt: DateTime(2026, 8, 11),
        result: InvariantCheckResult.passed,
        failedNames: [],
        allNames: ['CursorExists'],
      ));

      final replayAdapter = AdiReplayAdapterImpl(
        service,
        _successExecutorFactory,
      );
      final adapter = AdiValidationAdapterImpl(replayAdapter, service);
      final result = adapter.validate(sessionId: service.sessionId);

      expect(result.crossSessionDataWarning, isFalse);
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