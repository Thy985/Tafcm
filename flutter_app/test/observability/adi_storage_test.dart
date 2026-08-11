/// ADI Storage 单元测试。
///
/// 验证 AdiStorageImpl 的 initialize / writeErrorRecord / latestErrorRecord /
/// writeFailureRecord / loadFailure / atomic write（crash-safe）/ schema version。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/adi_record.dart';
import 'package:formula_fix/core/observability/adi_storage.dart';

void main() {
  late String tempDir;
  late AdiStorage storage;

  setUp(() {
    tempDir = '${Directory.systemTemp.path}/adi_test_${DateTime.now().microsecondsSinceEpoch}';
    storage = AdiStorageImpl(tempDir);
  });

  tearDown(() {
    final dir = Directory(tempDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('AdiStorageImpl.initialize', () {
    test('创建 .adi/ 目录结构', () {
      storage.initialize();

      expect(Directory('$tempDir/observations').existsSync(), isTrue);
      expect(Directory('$tempDir/sessions').existsSync(), isTrue);
      expect(Directory('$tempDir/traces').existsSync(), isTrue);
      expect(Directory('$tempDir/failures').existsSync(), isTrue);
      expect(storage.isInitialized, isTrue);
    });

    test('写入 schema_version.json', () {
      storage.initialize();

      expect(storage.readSchemaVersion(), 1);
    });

    test('重复 initialize 不覆盖 schema_version', () {
      storage.initialize();
      storage.initialize();

      expect(storage.readSchemaVersion(), 1);
    });
  });

  group('AdiStorageImpl.writeErrorRecord', () {
    test('写入后可读取', () {
      storage.initialize();
      final record = AdiErrorRecord(
        id: 'obs_001',
        time: DateTime(2026, 8, 11, 12, 0, 0),
        sessionId: 'sess_1',
        traceId: 'trace_1',
        source: 'test',
        errorType: 'CommandExecutionError',
        message: 'test error',
      );
      storage.writeErrorRecord(record);

      final loaded = storage.latestErrorRecord();
      expect(loaded, isNotNull);
      expect(loaded!.id, 'obs_001');
      expect(loaded.errorType, 'CommandExecutionError');
    });

    test('findErrorByTraceId 按 traceId 查找', () {
      storage.initialize();
      final record = AdiErrorRecord(
        id: 'obs_002',
        time: DateTime(2026, 8, 11),
        sessionId: 'sess_1',
        traceId: 'trace_target',
        source: 'test',
        errorType: 'GlobalError',
        message: 'crash',
      );
      storage.writeErrorRecord(record);

      final found = storage.findErrorByTraceId('trace_target');
      expect(found, isNotNull);
      expect(found!.id, 'obs_002');

      final notFound = storage.findErrorByTraceId('nonexistent');
      expect(notFound, isNull);
    });

    test('allErrorRecords 返回按时间倒序排列', () {
      storage.initialize();
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_old',
        time: DateTime(2026, 8, 1),
        sessionId: 's',
        traceId: 't1',
        source: 'test',
        errorType: 'A',
        message: 'old',
      ));
      storage.writeErrorRecord(AdiErrorRecord(
        id: 'obs_new',
        time: DateTime(2026, 8, 11),
        sessionId: 's',
        traceId: 't2',
        source: 'test',
        errorType: 'B',
        message: 'new',
      ));

      final all = storage.allErrorRecords();
      expect(all.length, 2);
      expect(all.first.id, 'obs_new');
      expect(all.last.id, 'obs_old');
    });
  });

  group('AdiStorageImpl.writeFailureRecord', () {
    test('写入后可按 failureId 读取', () {
      storage.initialize();
      final record = AdiFailureRecord(
        failureId: 'f_abc123',
        firstSeen: DateTime(2026, 8, 1),
        lastSeen: DateTime(2026, 8, 11),
        occurrences: 2,
        errorType: 'InvariantFailure',
        traceIds: ['t1', 't2'],
        sessionIds: ['s1'],
        status: AdiFailureStatus.open,
      );
      storage.writeFailureRecord(record);

      final loaded = storage.loadFailure('f_abc123');
      expect(loaded, isNotNull);
      expect(loaded!.occurrences, 2);
      expect(loaded.status, AdiFailureStatus.open);
    });

    test('loadFailure 对不存在的 ID 返回 null', () {
      storage.initialize();

      expect(storage.loadFailure('nonexistent'), isNull);
    });
  });

  group('AdiStorageImpl atomic write', () {
    test('写入后 .tmp 文件不存在（已 rename）', () {
      storage.initialize();
      final record = AdiErrorRecord(
        id: 'obs_003',
        time: DateTime(2026, 8, 11),
        sessionId: 's',
        traceId: 't',
        source: 'test',
        errorType: 'A',
        message: 'm',
      );
      storage.writeErrorRecord(record);

      expect(File('$tempDir/observations/obs_003.json').existsSync(), isTrue);
      expect(File('$tempDir/observations/obs_003.json.tmp').existsSync(), isFalse);
    });
  });

  group('AdiStorageImpl edge cases', () {
    test('未 initialize 时 latestErrorRecord 返回 null', () {
      expect(storage.latestErrorRecord(), isNull);
    });

    test('未 initialize 时 allErrorRecords 返回空列表', () {
      expect(storage.allErrorRecords(), isEmpty);
    });

    test('writeErrorRecord 自动 initialize', () {
      final record = AdiErrorRecord(
        id: 'obs_auto',
        time: DateTime(2026, 8, 11),
        sessionId: 's',
        traceId: 't',
        source: 'test',
        errorType: 'A',
        message: 'm',
      );
      storage.writeErrorRecord(record);

      expect(storage.isInitialized, isTrue);
      expect(storage.latestErrorRecord(), isNotNull);
    });
  });
}