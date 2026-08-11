/// ADI Query Adapter 单元测试。
///
/// 验证 AdiQueryAdapterImpl 的 latestError / traceView / recentFailures /
/// _hasReplayData（按 sessionId 过滤）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/adi_query_adapter.dart';
import 'package:formula_fix/core/observability/adi_record.dart';
import 'package:formula_fix/core/observability/adi_storage.dart';

import 'package:formula_fix/core/observability/models.dart';
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/core/observability/trace_context.dart';

void main() {
  late String tempDir;
  late AdiStorage storage;
  late ObservabilityService service;

  setUp(() {
    tempDir = '${Directory.systemTemp.path}/adi_qa_test_${DateTime.now().microsecondsSinceEpoch}';
    storage = AdiStorageImpl(tempDir);
    storage.initialize();
    service = ObservabilityService.full(adiStorage: storage);
    TraceIdGenerator.reset();
  });

  tearDown(() {
    final dir = Directory(tempDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('AdiQueryAdapterImpl.latestError', () {
    test('无错误时返回 null', () {
      final adapter = AdiQueryAdapterImpl(service, storage);

      expect(adapter.latestError(), isNull);
    });

    test('captureError 后返回 AdiErrorView', () {
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
      final error = adapter.latestError();

      expect(error, isNotNull);
      expect(error!.errorType, 'CommandExecutionError');
      expect(error.message, 'Block not found');
      expect(error.commandName, 'InsertTextCommand');
    });

    test('从磁盘加载跨 session 错误', () {
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_disk',
        time: DateTime(2026, 8, 10),
        sessionId: 'old_session',
        traceId: 'old_trace',
        source: 'test',
        errorType: 'GlobalError',
        message: 'past crash',
      ));

      final adapter = AdiQueryAdapterImpl(service, storage);
      final error = adapter.latestError();

      expect(error, isNotNull);
      expect(error!.errorType, 'GlobalError');
    });
  });

  group('AdiQueryAdapterImpl.traceView', () {
    test('当前 context 匹配时返回 trace view', () {
      final traceId = 'trace_current';
      service.setTraceContext(EditorTraceContext(
        sessionId: service.sessionId,
        traceId: traceId,
        spanId: 'span_1',
      ));

      final adapter = AdiQueryAdapterImpl(service, storage);
      final view = adapter.traceView(traceId);

      expect(view, isNotNull);
      expect(view!.traceId, traceId);
      expect(view.spans, hasLength(1));
      expect(view.spans.first.layer, 'current');
    });

    test('不匹配的 traceId 返回 null', () {
      final adapter = AdiQueryAdapterImpl(service, storage);

      expect(adapter.traceView('nonexistent'), isNull);
    });

    test('从 commandTracer entries 构建 trace view', () {
      final traceId = 'trace_cmd';
      service.recordCommand(CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {'blockId': 'b1', 'text': 'hello'},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
        traceId: traceId,
        spanId: 'span_cmd',
      ));

      final adapter = AdiQueryAdapterImpl(service, storage);
      final view = adapter.traceView(traceId);

      expect(view, isNotNull);
      expect(view!.spans, hasLength(1));
      expect(view.spans.first.description, 'InsertTextCommand');
      expect(view.spans.first.layer, 'command');
    });
  });

  group('AdiQueryAdapterImpl.recentFailures', () {
    test('返回磁盘上的错误记录', () {
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_f1',
        time: DateTime(2026, 8, 10),
        sessionId: 's1',
        traceId: 't1',
        source: 'test',
        errorType: 'ErrorA',
        message: 'msg1',
      ));
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_f2',
        time: DateTime(2026, 8, 11),
        sessionId: 's2',
        traceId: 't2',
        source: 'test',
        errorType: 'ErrorB',
        message: 'msg2',
      ));

      final adapter = AdiQueryAdapterImpl(service, storage);
      final failures = adapter.recentFailures(limit: 10);

      expect(failures.length, 2);
      expect(failures.first.errorType, 'ErrorB');
    });

    test('limit 参数限制返回数量', () {
      for (var i = 0; i < 5; i++) {
        storage.writeErrorRecord(AdiErrorRecord(
          id: 'obs_$i',
          time: DateTime(2026, 8, 1 + i),
          sessionId: 's',
          traceId: 't$i',
          source: 'test',
          errorType: 'E$i',
          message: 'm$i',
        ));
      }

      final adapter = AdiQueryAdapterImpl(service, storage);
      final failures = adapter.recentFailures(limit: 3);

      expect(failures.length, 3);
    });
  });

  group('AdiQueryAdapterImpl._hasReplayData', () {
    test('sessionId 不匹配当前 session 时 replayAvailable 为 false', () {
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_other',
        time: DateTime(2026, 8, 10),
        sessionId: 'different_session',
        traceId: 't_other',
        source: 'test',
        errorType: 'ErrorA',
        message: 'msg',
      ));
      service.recordCommand(CommandTraceEntry(
        commandName: 'Cmd',
        params: {},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
      ));

      final adapter = AdiQueryAdapterImpl(service, storage);
      final failures = adapter.recentFailures();

      expect(failures, hasLength(1));
      expect(failures.first.replayAvailable, isFalse);
    });

    test('sessionId 匹配且有 command entries 时 replayAvailable 为 true', () {
      service.recordCommand(CommandTraceEntry(
        commandName: 'Cmd',
        params: {},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 11),
        succeeded: true,
      ));
      service.captureError(
        type: 'ErrorA',
        message: 'msg',
      );

      final adapter = AdiQueryAdapterImpl(service, storage);
      final error = adapter.latestError();

      expect(error, isNotNull);
      expect(error!.replayAvailable, isTrue);
    });
  });
}