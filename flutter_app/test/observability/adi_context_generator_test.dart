/// ADI Context Generator 单元测试。
///
/// 验证 AdiContextGeneratorImpl.generateAgentContext 输出 Markdown 格式、
/// 含 Observation / Reproduction / Evidence / Hypotheses / Invariant / Next Actions。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/observability/adi_context_generator.dart';
import 'package:tafcm/core/observability/adi_query_adapter.dart';
import 'package:tafcm/core/observability/adi_record.dart';
import 'package:tafcm/core/observability/adi_storage.dart';
import 'package:tafcm/core/observability/adi_view.dart';
import 'package:tafcm/core/observability/models.dart';
import 'package:tafcm/core/observability/observability_service.dart';
import 'package:tafcm/core/observability/trace_context.dart';

void main() {
  late String tempDir;
  late AdiStorage storage;
  late ObservabilityService service;

  setUp(() {
    tempDir = '${Directory.systemTemp.path}/adi_ctx_test_${DateTime.now().microsecondsSinceEpoch}';
    storage = AdiStorageImpl(tempDir);
    storage.initialize();
    service = ObservabilityService.full(adiStorage: storage);
    TraceIdGenerator.reset();
  });

  tearDown(() {
    final dir = Directory(tempDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('AdiContextGeneratorImpl.generateAgentContext', () {
    test('无错误时输出 "No errors recorded"', () {
      final adapter = AdiQueryAdapterImpl(service, storage);
      final gen = AdiContextGeneratorImpl(adapter, service);
      final output = gen.generateAgentContext();

      expect(output, contains('# Current Software State'));
      expect(output, contains('No errors recorded.'));
      expect(output, contains('No action needed'));
    });

    test('有错误时输出 errorType + message', () {
      final traceId = TraceIdGenerator.traceId();
      service.setTraceContext(EditorTraceContext(
        sessionId: service.sessionId,
        traceId: traceId,
        spanId: 'span_1',
      ));
      service.captureError(
        type: 'CommandExecutionError',
        message: 'Block not found',
        commandName: 'InsertTextCommand',
      );

      final adapter = AdiQueryAdapterImpl(service, storage);
      final gen = AdiContextGeneratorImpl(adapter, service);
      final output = gen.generateAgentContext();

      expect(output, contains('CommandExecutionError'));
      expect(output, contains('Block not found'));
      expect(output, contains('InsertTextCommand'));
    });

    test('有 replay data 时输出 replay 命令建议', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
      ));
      service.captureError(
        type: 'ErrorA',
        message: 'test',
      );

      final adapter = AdiQueryAdapterImpl(service, storage);
      final gen = AdiContextGeneratorImpl(adapter, service);
      final output = gen.generateAgentContext();

      expect(output, contains('Replay data available'));
      expect(output, contains('adi replay'));
    });

    test('包含全部 6 个 section', () {
      final adapter = AdiQueryAdapterImpl(service, storage);
      final gen = AdiContextGeneratorImpl(adapter, service);
      final output = gen.generateAgentContext();

      expect(output, contains('## Last failure'));
      expect(output, contains('## Reproduction'));
      expect(output, contains('## Evidence'));
      expect(output, contains('## Suspected location'));
      expect(output, contains('## Invariant status'));
      expect(output, contains('## Suggested next action'));
    });

    test('有 hypotheses 时输出 file:line', () {
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_h',
        time: DateTime(2026, 8, 11),
        sessionId: 'old_session',
        traceId: 'old_trace',
        source: 'test',
        errorType: 'ErrorA',
        message: 'test',
      ));

      final adapter = _AdapterWithHypothesis(service, storage);
      final gen = AdiContextGeneratorImpl(adapter, service);
      final output = gen.generateAgentContext();

      expect(output, contains('lib/core/editing/block_editor.dart:42'));
      expect(output, contains('confidence: hypothesis'));
    });
  });
}

class _AdapterWithHypothesis extends AdiQueryAdapterImpl {
  _AdapterWithHypothesis(super.service, super.storage);

  @override
  AdiErrorView? latestError() {
    final base = super.latestError();
    if (base == null) return null;
    return AdiErrorView(
      id: base.id,
      traceId: base.traceId,
      errorType: base.errorType,
      message: base.message,
      replayAvailable: base.replayAvailable,
      snapshotPath: base.snapshotPath,
      quality: base.quality,
      sessionId: base.sessionId,
      commandName: base.commandName,
      hypotheses: [
        AdiHypothesis(
          file: 'lib/core/editing/block_editor.dart',
          line: 42,
          reason: 'Null block reference',
        ),
      ],
    );
  }
}