/// ADI Record 单元测试。
///
/// 验证 AdiErrorRecord / AdiFailureRecord 的 toJson/fromJson 往返、
/// computeFailureId 跨 VM 稳定性（SHA-256）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/adi_record.dart';
import 'package:formula_fix/core/observability/error_snapshot.dart';

void main() {
  group('AdiErrorRecord', () {
    test('toJson → fromJson 往返保持全部字段', () {
      final record = AdiErrorRecord(
        id: 'obs_20260811_120000',
        time: DateTime(2026, 8, 11, 12, 0, 0),
        sessionId: 'sess_abc',
        traceId: 'trace_xyz',
        source: 'command_handler',
        errorType: 'CommandExecutionError',
        message: 'Block not found',
        stackHash: 'sha_deadbeef',
        commandName: 'InsertTextCommand',
      );
      final json = record.toJson();
      final restored = AdiErrorRecord.fromJson(json);

      expect(restored.id, record.id);
      expect(restored.time, record.time);
      expect(restored.sessionId, record.sessionId);
      expect(restored.traceId, record.traceId);
      expect(restored.source, record.source);
      expect(restored.errorType, record.errorType);
      expect(restored.message, record.message);
      expect(restored.stackHash, record.stackHash);
      expect(restored.commandName, record.commandName);
    });

    test('fromSnapshot 投影保留核心字段', () {
      final snapshot = ErrorSnapshot(
        id: 'err_20260811_100000',
        timestamp: DateTime(2026, 8, 11, 10, 0, 0),
        type: 'CommandExecutionError',
        message: 'Null cursor',
        commandName: 'DeleteCommand',
        traceId: 'trace_t1',
        sessionId: 'sess_s1',
      );
      final record = AdiErrorRecord.fromSnapshot(snapshot, source: 'test');

      expect(record.id, snapshot.id);
      expect(record.time, snapshot.timestamp);
      expect(record.sessionId, snapshot.sessionId);
      expect(record.traceId, snapshot.traceId);
      expect(record.errorType, snapshot.type);
      expect(record.message, snapshot.message);
      expect(record.commandName, snapshot.commandName);
      expect(record.source, 'test');
    });

    test('fromSnapshot 处理 null traceId/sessionId', () {
      final snapshot = ErrorSnapshot(
        id: 'err_001',
        timestamp: DateTime(2026, 8, 11),
        type: 'GlobalError',
        message: 'crash',
      );
      final record = AdiErrorRecord.fromSnapshot(snapshot);

      expect(record.sessionId, 'unknown');
      expect(record.traceId, 'unknown');
    });
  });

  group('AdiFailureRecord', () {
    test('toJson → fromJson 往返保持全部字段', () {
      final record = AdiFailureRecord(
        failureId: 'f_abc123',
        firstSeen: DateTime(2026, 8, 1),
        lastSeen: DateTime(2026, 8, 11),
        occurrences: 3,
        errorType: 'InvariantFailure',
        stackHash: 'sha_001',
        traceIds: ['trace_1', 'trace_2', 'trace_3'],
        sessionIds: ['sess_1', 'sess_2'],
        status: AdiFailureStatus.recurring,
      );
      final json = record.toJson();
      final restored = AdiFailureRecord.fromJson(json);

      expect(restored.failureId, record.failureId);
      expect(restored.firstSeen, record.firstSeen);
      expect(restored.lastSeen, record.lastSeen);
      expect(restored.occurrences, record.occurrences);
      expect(restored.errorType, record.errorType);
      expect(restored.stackHash, record.stackHash);
      expect(restored.traceIds, record.traceIds);
      expect(restored.sessionIds, record.sessionIds);
      expect(restored.status, record.status);
    });

    test('copyWith 更新部分字段', () {
      final record = AdiFailureRecord(
        failureId: 'f_1',
        firstSeen: DateTime(2026, 8, 1),
        lastSeen: DateTime(2026, 8, 1),
        occurrences: 1,
        errorType: 'ErrorA',
        traceIds: ['t1'],
        sessionIds: ['s1'],
        status: AdiFailureStatus.open,
      );
      final updated = record.copyWith(
        lastSeen: DateTime(2026, 8, 11),
        occurrences: 2,
        status: AdiFailureStatus.recurring,
      );

      expect(updated.occurrences, 2);
      expect(updated.lastSeen, DateTime(2026, 8, 11));
      expect(updated.status, AdiFailureStatus.recurring);
      expect(updated.failureId, record.failureId);
      expect(updated.firstSeen, record.firstSeen);
    });

    test('computeFailureId 对相同输入返回相同结果（确定性）', () {
      final id1 = AdiFailureRecord.computeFailureId('ErrorA', 'stack_123');
      final id2 = AdiFailureRecord.computeFailureId('ErrorA', 'stack_123');

      expect(id1, id2);
      expect(id1.startsWith('f_'), isTrue);
    });

    test('computeFailureId 对不同输入返回不同结果', () {
      final id1 = AdiFailureRecord.computeFailureId('ErrorA', 'stack_123');
      final id2 = AdiFailureRecord.computeFailureId('ErrorB', 'stack_123');
      final id3 = AdiFailureRecord.computeFailureId('ErrorA', 'stack_456');

      expect(id1, isNot(id2));
      expect(id1, isNot(id3));
    });

    test('computeFailureId 处理 null stackHash', () {
      final id1 = AdiFailureRecord.computeFailureId('ErrorA', null);
      final id2 = AdiFailureRecord.computeFailureId('ErrorA', null);

      expect(id1, id2);
      expect(id1.startsWith('f_'), isTrue);
    });
  });

  group('AdiInvariantRecord', () {
    test('toJson → fromJson 往返', () {
      final record = AdiInvariantRecord(
        id: 'inv_001',
        time: DateTime(2026, 8, 11),
        sessionId: 'sess_1',
        traceId: 'trace_1',
        violated: ['CursorExists'],
        checked: ['CursorExists', 'SelectionValid', 'BlockTreeAcyclic'],
      );
      final restored = AdiInvariantRecord.fromJson(record.toJson());

      expect(restored.id, record.id);
      expect(restored.violated, record.violated);
      expect(restored.checked, record.checked);
    });
  });
}