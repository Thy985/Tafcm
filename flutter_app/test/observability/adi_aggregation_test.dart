/// ADI Aggregation 纯函数单元测试。
///
/// 验证 aggregateErrors / buildIndex 的数据变换逻辑。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/observability/adi_aggregation.dart';
import 'package:tafcm/core/observability/adi_record.dart';

void main() {
  group('aggregateErrors', () {
    test('空 errors 返回空 Map', () {
      expect(aggregateErrors([], {}), isEmpty);
    });

    test('相同 errorType+stackHash 聚合为同一 failure', () {
      final errors = [
        AdiErrorRecord(
          id: 'obs_1',
          time: DateTime(2026, 8, 1),
          sessionId: 's1',
          traceId: 't1',
          source: 'test',
          errorType: 'ErrorA',
          message: 'msg',
          stackHash: 'sha_a',
        ),
        AdiErrorRecord(
          id: 'obs_2',
          time: DateTime(2026, 8, 5),
          sessionId: 's2',
          traceId: 't2',
          source: 'test',
          errorType: 'ErrorA',
          message: 'msg',
          stackHash: 'sha_a',
        ),
      ];

      final result = aggregateErrors(errors, {});
      expect(result.length, 1);
      final failure = result.values.first;
      expect(failure.occurrences, 2);
      expect(failure.sessionIds, containsAll(['s1', 's2']));
      expect(failure.traceIds, containsAll(['t1', 't2']));
      expect(failure.firstSeen, DateTime(2026, 8, 1));
      expect(failure.lastSeen, DateTime(2026, 8, 5));
    });

    test('与 existing 合并时取 max occurrences', () {
      final errors = [
        AdiErrorRecord(
          id: 'obs_1',
          time: DateTime(2026, 8, 1),
          sessionId: 's1',
          traceId: 't1',
          source: 'test',
          errorType: 'ErrorA',
          message: 'msg',
          stackHash: 'sha_a',
        ),
      ];
      final fid = AdiFailureRecord.computeFailureId('ErrorA', 'sha_a');
      final existing = {
        fid: AdiFailureRecord(
          failureId: fid,
          firstSeen: DateTime(2026, 8, 1),
          lastSeen: DateTime(2026, 8, 1),
          occurrences: 5,
          errorType: 'ErrorA',
          stackHash: 'sha_a',
          traceIds: ['t0'],
          sessionIds: ['s0'],
          status: AdiFailureStatus.fixed,
        ),
      };

      final result = aggregateErrors(errors, existing);
      expect(result[fid]!.occurrences, 5);
      expect(result[fid]!.status, AdiFailureStatus.fixed);
    });

    test('与 existing 合并时保留 fixed 状态', () {
      final errors = [
        AdiErrorRecord(
          id: 'obs_1',
          time: DateTime(2026, 8, 1),
          sessionId: 's1',
          traceId: 't1',
          source: 'test',
          errorType: 'ErrorA',
          message: 'msg',
          stackHash: 'sha_a',
        ),
      ];
      final fid = AdiFailureRecord.computeFailureId('ErrorA', 'sha_a');
      final existing = {
        fid: AdiFailureRecord(
          failureId: fid,
          firstSeen: DateTime(2026, 8, 1),
          lastSeen: DateTime(2026, 8, 1),
          occurrences: 1,
          errorType: 'ErrorA',
          stackHash: 'sha_a',
          traceIds: ['t0'],
          sessionIds: ['s0'],
          status: AdiFailureStatus.fixed,
        ),
      };

      final result = aggregateErrors(errors, existing);
      expect(result[fid]!.status, AdiFailureStatus.fixed);
    });

    test('新 failure 默认 status 为 open', () {
      final errors = [
        AdiErrorRecord(
          id: 'obs_1',
          time: DateTime(2026, 8, 1),
          sessionId: 's1',
          traceId: 't1',
          source: 'test',
          errorType: 'ErrorA',
          message: 'msg',
          stackHash: 'sha_a',
        ),
      ];

      final result = aggregateErrors(errors, {});
      expect(result.values.first.status, AdiFailureStatus.open);
    });
  });

  group('buildIndex', () {
    test('包含 observations 和 failures 两个列表', () {
      final errors = [
        AdiErrorRecord(
          id: 'obs_1',
          time: DateTime(2026, 8, 11),
          sessionId: 's1',
          traceId: 't1',
          source: 'test',
          errorType: 'ErrorA',
          message: 'msg',
        ),
      ];
      final failures = [
        AdiFailureRecord(
          failureId: 'f_1',
          firstSeen: DateTime(2026, 8, 1),
          lastSeen: DateTime(2026, 8, 11),
          occurrences: 3,
          errorType: 'ErrorA',
          traceIds: ['t1'],
          sessionIds: ['s1'],
          status: AdiFailureStatus.open,
        ),
      ];

      final index = buildIndex(errors, failures);
      expect(index.containsKey('updated_at'), isTrue);
      expect(index.containsKey('observations'), isTrue);
      expect(index.containsKey('failures'), isTrue);
      expect((index['observations'] as List).length, 1);
      expect((index['failures'] as List).length, 1);
    });

    test('空输入返回空列表', () {
      final index = buildIndex([], []);
      expect((index['observations'] as List), isEmpty);
      expect((index['failures'] as List), isEmpty);
    });
  });
}