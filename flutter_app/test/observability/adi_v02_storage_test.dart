/// ADI v0.2 Storage 扩展测试。
///
/// 验证 aggregateFailures / readIndex / writeIndex /
/// retain（LRU 清理）/ migrateToLatest（Schema Migration）。
library;

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