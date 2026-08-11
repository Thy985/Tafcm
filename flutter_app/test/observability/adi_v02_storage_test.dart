/// ADI v0.2 Storage 扩展测试。
///
/// 验证 aggregateFailures / readIndex / writeIndex /
/// retain（LRU 清理）/ migrateToLatest（Schema Migration）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/adi_record.dart';
import 'package:formula_fix/core/observability/adi_storage.dart';

void main() {
  late String tempDir;
  late AdiStorage storage;

  setUp(() {
    tempDir = '${Directory.systemTemp.path}/adi_v02_test_${DateTime.now().microsecondsSinceEpoch}';
    storage = AdiStorageImpl(tempDir);
  });

  tearDown(() {
    final dir = Directory(tempDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('aggregateFailures', () {
    test('相同 errorType+stackHash 聚合为同一 failure', () {
      storage.initialize();
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_1',
        time: DateTime(2026, 8, 1),
        sessionId: 's1',
        traceId: 't1',
        source: 'test',
        errorType: 'CommandExecutionError',
        message: 'error 1',
        stackHash: 'sha_abc',
      ));
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_2',
        time: DateTime(2026, 8, 5),
        sessionId: 's2',
        traceId: 't2',
        source: 'test',
        errorType: 'CommandExecutionError',
        message: 'error 2',
        stackHash: 'sha_abc',
      ));
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_3',
        time: DateTime(2026, 8, 11),
        sessionId: 's1',
        traceId: 't3',
        source: 'test',
        errorType: 'GlobalError',
        message: 'different type',
        stackHash: 'sha_xyz',
      ));

      storage.aggregateFailures();
      final failures = storage.allFailureRecords();

      expect(failures.length, 2);
      final recurring = failures.firstWhere(
        (f) => f.errorType == 'CommandExecutionError',
      );
      expect(recurring.occurrences, 2);
      expect(recurring.sessionIds, containsAll(['s1', 's2']));
      expect(recurring.traceIds, containsAll(['t1', 't2']));
    });

    test('无 error records 时不产生 failures', () {
      storage.initialize();
      storage.aggregateFailures();

      expect(storage.allFailureRecords(), isEmpty);
    });

    test('聚合后 index.json 包含 failures 索引', () {
      storage.initialize();
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_1',
        time: DateTime(2026, 8, 11),
        sessionId: 's1',
        traceId: 't1',
        source: 'test',
        errorType: 'ErrorA',
        message: 'msg',
      ));
      storage.aggregateFailures();
      final index = storage.readIndex();

      expect(index.containsKey('updated_at'), isTrue);
      expect(index.containsKey('failures'), isTrue);
      expect(index.containsKey('observations'), isTrue);
      final failures = index['failures'] as List;
      expect(failures.length, 1);
    });

    test('re-aggregation 保留 occurrences 历史不覆盖', () {
      storage.initialize();
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_1',
        time: DateTime(2026, 8, 1),
        sessionId: 's1',
        traceId: 't1',
        source: 'test',
        errorType: 'ErrorA',
        message: 'msg',
        stackHash: 'sha_a',
      ));
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_2',
        time: DateTime(2026, 8, 2),
        sessionId: 's1',
        traceId: 't2',
        source: 'test',
        errorType: 'ErrorA',
        message: 'msg',
        stackHash: 'sha_a',
      ));
      storage.aggregateFailures();
      expect(
        storage.allFailureRecords().first.occurrences,
        2,
      );

      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_3',
        time: DateTime(2026, 8, 3),
        sessionId: 's1',
        traceId: 't3',
        source: 'test',
        errorType: 'ErrorA',
        message: 'msg',
        stackHash: 'sha_a',
      ));
      storage.aggregateFailures();
      expect(
        storage.allFailureRecords().first.occurrences,
        3,
      );
    });

    test('re-aggregation 保留 fixed 状态不回退为 open', () {
      storage.initialize();
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_1',
        time: DateTime(2026, 8, 1),
        sessionId: 's1',
        traceId: 't1',
        source: 'test',
        errorType: 'ErrorA',
        message: 'msg',
        stackHash: 'sha_a',
      ));
      storage.aggregateFailures();
      final fid = storage.allFailureRecords().first.failureId;
      storage.writeFailureRecord(AdiFailureRecord(
        failureId: fid,
        firstSeen: DateTime(2026, 8, 1),
        lastSeen: DateTime(2026, 8, 1),
        occurrences: 1,
        errorType: 'ErrorA',
        stackHash: 'sha_a',
        traceIds: ['t1'],
        sessionIds: ['s1'],
        status: AdiFailureStatus.fixed,
      ));

      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_2',
        time: DateTime(2026, 8, 5),
        sessionId: 's1',
        traceId: 't2',
        source: 'test',
        errorType: 'ErrorA',
        message: 'msg',
        stackHash: 'sha_a',
      ));
      storage.aggregateFailures();
      expect(
        storage.allFailureRecords().first.status,
        AdiFailureStatus.fixed,
      );
    });
  });

  group('readIndex / writeIndex', () {
    test('writeIndex → readIndex 往返', () {
      storage.initialize();
      storage.writeIndex({
        'test_key': 'test_value',
        'count': 42,
      });
      final index = storage.readIndex();

      expect(index['test_key'], 'test_value');
      expect(index['count'], 42);
    });

    test('未初始化时 readIndex 返回空 Map', () {
      expect(storage.readIndex(), isEmpty);
    });
  });

  group('retain (LRU)', () {
    test('不超限时清理 0 个文件', () {
      storage.initialize();
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_1',
        time: DateTime(2026, 8, 11),
        sessionId: 's1',
        traceId: 't1',
        source: 'test',
        errorType: 'A',
        message: 'm',
      ));

      final cleaned = storage.retain(maxSessions: 20);
      expect(cleaned, 0);
    });

    test('超 maxSessions 时清理旧 session', () {
      storage.initialize();
      for (var i = 0; i < 25; i++) {
        storage.writeErrorRecord(AdiErrorRecord(
          id: 'obs_$i',
          time: DateTime(2026, 8, 1 + i),
          sessionId: 'sess_$i',
          traceId: 't_$i',
          source: 'test',
          errorType: 'E$i',
          message: 'm$i',
        ));
      }

      final cleaned = storage.retain(maxSessions: 10);
      expect(cleaned, greaterThan(0));
    });

    test('retain 按时间序而非字典序清理', () {
      storage.initialize();
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_a',
        time: DateTime(2026, 8, 10),
        sessionId: 'sess_z',
        traceId: 't_a',
        source: 'test',
        errorType: 'A',
        message: 'm',
      ));
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_b',
        time: DateTime(2026, 8, 1),
        sessionId: 'sess_a',
        traceId: 't_b',
        source: 'test',
        errorType: 'B',
        message: 'm',
      ));

      storage.retain(maxSessions: 1);
      final remaining = storage.allErrorRecords();
      expect(remaining.length, 1);
      expect(remaining.first.sessionId, 'sess_z');
    });
  });

  group('migrateToLatest', () {
    test('已是最新 version 时无迁移', () {
      storage.initialize();
      final result = storage.migrateToLatest();

      expect(result.from, 1);
      expect(result.to, 1);
    });

    test('从 version 0 迁移到 version 1', () {
      final root = Directory(tempDir);
      root.createSync(recursive: true);
      final result = storage.migrateToLatest();

      expect(result.from, 0);
      expect(result.to, 1);
      expect(storage.readSchemaVersion(), 1);
      expect(Directory('$tempDir/observations').existsSync(), isTrue);
      expect(Directory('$tempDir/failures').existsSync(), isTrue);
    });

    test('migrate 幂等：多次迁移结果一致', () {
      final root = Directory(tempDir);
      root.createSync(recursive: true);
      storage.migrateToLatest();
      final schemaAfter1 = _readSchemaJson(tempDir);

      storage.migrateToLatest();
      final schemaAfter2 = _readSchemaJson(tempDir);

      expect(schemaAfter2['schema_version'], 1);
      expect(
        schemaAfter2['created_at'],
        schemaAfter1['created_at'],
      );
    });
  });

  group('allFailureRecords', () {
    test('返回按 lastSeen 倒序排列', () {
      storage.initialize();
      storage.writeFailureRecord(AdiFailureRecord(
        failureId: 'f_old',
        firstSeen: DateTime(2026, 8, 1),
        lastSeen: DateTime(2026, 8, 5),
        occurrences: 1,
        errorType: 'A',
        traceIds: [],
        sessionIds: [],
        status: AdiFailureStatus.open,
      ));
      storage.writeFailureRecord(AdiFailureRecord(
        failureId: 'f_new',
        firstSeen: DateTime(2026, 8, 10),
        lastSeen: DateTime(2026, 8, 11),
        occurrences: 1,
        errorType: 'B',
        traceIds: [],
        sessionIds: [],
        status: AdiFailureStatus.open,
      ));

      final all = storage.allFailureRecords();
      expect(all.length, 2);
      expect(all.first.failureId, 'f_new');
      expect(all.last.failureId, 'f_old');
    });
  });
}

Map<String, Object?> _readSchemaJson(String tempDir) {
  final file = File('$tempDir/schema_version.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}