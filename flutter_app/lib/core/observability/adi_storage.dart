/// ADI Storage：.adi/ 目录读写（Layer 2 持久化）。
///
/// 取代 ExportPipeline 的 zip，让 Agent 可增量查询、无需解压。
/// 只读写 [AdiRecord]（Layer 2），不返回 [AdiView]（Layer 3）。
/// View 由 QueryAdapter 投影生成。
///
/// **架构守门**：.adi/ 写入仅此文件（TC-ARCH-2 allowlist）。
/// **Crash-safe**：atomic rename（temp → rename）。
///
/// 落地 ADR-0024 §2.6（ADI Storage）。
library;

import 'dart:convert';
import 'dart:io';

import 'adi_aggregation.dart';
import 'adi_record.dart';

/// ADI 存储抽象接口。
abstract class AdiStorage {
  void writeErrorRecord(AdiErrorRecord record);
  AdiErrorRecord? latestErrorRecord();
  AdiErrorRecord? findErrorByTraceId(String traceId);
  List<AdiErrorRecord> allErrorRecords();
  void writeFailureRecord(AdiFailureRecord record);
  AdiFailureRecord? loadFailure(String failureId);
  List<AdiFailureRecord> allFailureRecords();
  int readSchemaVersion();
  bool get isInitialized;
  void initialize();
  String get rootPath;

  /// v0.2: 从全部 error records 聚合生成 failure records。
  ///
  /// 按 failureId（SHA-256 of errorType + stackHash）分组，
  /// 合并 occurrences / traceIds / sessionIds，写入 .adi/failures/。
  void aggregateFailures();

  /// v0.2: 读取/写入 index.json 索引文件。
  Map<String, Object?> readIndex();
  void writeIndex(Map<String, Object?> index);

  /// v0.2: LRU 清理——保留最近 [maxSessions] 个 session，
  /// 总存储不超过 [maxStorageBytes]。
  ///
  /// 返回被清理的文件数。
  int retain({
    int maxSessions = 20,
    int maxStorageBytes = 500 * 1024 * 1024,
  });

  /// v0.2: Schema migration——将 .adi/ 升级到最新 schema_version。
  ///
  /// 返回迁移前后的 version 对。
  ({int from, int to}) migrateToLatest();
}

/// ADI 存储实现。
class AdiStorageImpl implements AdiStorage {
  final String _rootPath;

  AdiStorageImpl([String? rootPath])
      : _rootPath = rootPath ?? '${Directory.current.path}/.adi';

  @override
  String get rootPath => _rootPath;

  @override
  bool get isInitialized => Directory(_rootPath).existsSync();

  @override
  void initialize() {
    _ensureDir(_rootPath);
    _ensureDir('$_rootPath/observations');
    _ensureDir('$_rootPath/sessions');
    _ensureDir('$_rootPath/traces');
    _ensureDir('$_rootPath/failures');
    _writeSchemaVersion();
  }

  @override
  void writeErrorRecord(AdiErrorRecord record) {
    if (!isInitialized) initialize();
    _atomicWrite('$_rootPath/observations/${record.id}.json', record.toJson());
  }

  @override
  AdiErrorRecord? latestErrorRecord() {
    final dir = Directory('$_rootPath/observations');
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.path.compareTo(a.path));
    final json = _readJson(files.first.path);
    return json != null ? AdiErrorRecord.fromJson(json) : null;
  }

  @override
  AdiErrorRecord? findErrorByTraceId(String traceId) {
    for (final r in allErrorRecords()) {
      if (r.traceId == traceId) return r;
    }
    return null;
  }

  @override
  List<AdiErrorRecord> allErrorRecords() {
    final dir = Directory('$_rootPath/observations');
    if (!dir.existsSync()) return [];
    final result = <AdiErrorRecord>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final json = _readJson(entity.path);
      if (json != null) {
        try {
          result.add(AdiErrorRecord.fromJson(json));
        } catch (_) {}
      }
    }
    result.sort((a, b) => b.time.compareTo(a.time));
    return result;
  }

  @override
  void writeFailureRecord(AdiFailureRecord record) {
    if (!isInitialized) initialize();
    _atomicWrite('$_rootPath/failures/${record.failureId}.json', record.toJson());
  }

  @override
  AdiFailureRecord? loadFailure(String failureId) {
    final json = _readJson('$_rootPath/failures/$failureId.json');
    return json != null ? AdiFailureRecord.fromJson(json) : null;
  }

  @override
  List<AdiFailureRecord> allFailureRecords() {
    final dir = Directory('$_rootPath/failures');
    if (!dir.existsSync()) return [];
    final result = <AdiFailureRecord>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final json = _readJson(entity.path);
      if (json != null) {
        try {
          result.add(AdiFailureRecord.fromJson(json));
        } catch (_) {}
      }
    }
    result.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return result;
  }

  @override
  int readSchemaVersion() {
    final json = _readJson('$_rootPath/schema_version.json');
    return json?['schema_version'] as int? ?? 0;
  }

  // ============ v0.2: Failure Aggregation ============

  @override
  void aggregateFailures() {
    if (!isInitialized) initialize();
    final errors = allErrorRecords();
    if (errors.isEmpty) return;

    final existing = <String, AdiFailureRecord>{};
    for (final f in allFailureRecords()) {
      existing[f.failureId] = f;
    }

    final aggregated = aggregateErrors(errors, existing);
    for (final record in aggregated.values) {
      writeFailureRecord(record);
    }

    _rebuildIndex();
  }

  // ============ v0.2: Index ============

  @override
  Map<String, Object?> readIndex() {
    return _readJson('$_rootPath/index.json') ?? {};
  }

  @override
  void writeIndex(Map<String, Object?> index) {
    if (!isInitialized) initialize();
    _atomicWrite('$_rootPath/index.json', index);
  }

  void _rebuildIndex() {
    final errors = allErrorRecords();
    final failures = allFailureRecords();
    writeIndex(buildIndex(errors, failures));
  }

  // ============ v0.2: LRU Retention ============

  @override
  int retain({
    int maxSessions = 20,
    int maxStorageBytes = 500 * 1024 * 1024,
  }) {
    if (!isInitialized) return 0;
    var cleaned = 0;

    final allErrors = allErrorRecords();
    final sessionLatestTime = <String, DateTime>{};
    for (final e in allErrors) {
      final existing = sessionLatestTime[e.sessionId];
      if (existing == null || e.time.isAfter(existing)) {
        sessionLatestTime[e.sessionId] = e.time;
      }
    }
    if (sessionLatestTime.length > maxSessions) {
      final sorted = sessionLatestTime.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final toRemove = sorted
          .take(sessionLatestTime.length - maxSessions)
          .map((e) => e.key)
          .toSet();
      final obsDir = Directory('$_rootPath/observations');
      if (obsDir.existsSync()) {
        for (final entity in obsDir.listSync()) {
          if (entity is! File || !entity.path.endsWith('.json')) continue;
          final json = _readJson(entity.path);
          if (json == null) continue;
          final sid = json['sessionId'] as String?;
          if (sid != null && toRemove.contains(sid)) {
            entity.deleteSync();
            cleaned++;
          }
        }
      }
      final sessDir = Directory('$_rootPath/sessions');
      if (sessDir.existsSync()) {
        for (final sid in toRemove) {
          final dir = Directory('$_rootPath/sessions/$sid');
          if (dir.existsSync()) {
            for (final f in dir.listSync().whereType<File>()) {
              f.deleteSync();
              cleaned++;
            }
            dir.deleteSync();
          }
        }
      }
    }

    final totalSize = _calculateStorageSize();
    if (totalSize > maxStorageBytes) {
      final obsDir = Directory('$_rootPath/observations');
      if (obsDir.existsSync()) {
        final files = obsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList();
        final fileTimes = <File, DateTime>{};
        for (final f in files) {
          final json = _readJson(f.path);
          final timeStr = json?['time'] as String?;
          if (timeStr != null) {
            try {
              fileTimes[f] = DateTime.parse(timeStr);
            } catch (_) {
              fileTimes[f] = DateTime.fromMillisecondsSinceEpoch(0);
            }
          }
        }
        final sortedFiles = fileTimes.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        var currentSize = totalSize;
        for (final entry in sortedFiles) {
          if (currentSize <= maxStorageBytes) break;
          currentSize -= entry.key.lengthSync();
          entry.key.deleteSync();
          cleaned++;
        }
      }
    }

    if (cleaned > 0) _rebuildIndex();
    return cleaned;
  }

  int _calculateStorageSize() {
    var total = 0;
    final root = Directory(_rootPath);
    if (!root.existsSync()) return 0;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }

  // ============ v0.2: Schema Migration ============

  @override
  ({int from, int to}) migrateToLatest() {
    final current = readSchemaVersion();
    const target = 1;
    if (current >= target) return (from: current, to: target);

    for (var v = current; v < target; v++) {
      switch (v) {
        case 0:
          _migrateV0ToV1();
        default:
          break;
      }
    }

    final existing = _readJson('$_rootPath/schema_version.json');
    _atomicWrite('$_rootPath/schema_version.json', {
      'adi_version': '0.2',
      'adi_protocol_version': '1.0',
      'schema_version': target,
      'created_at': existing?['created_at'] ?? DateTime.now().toIso8601String(),
      'migrated_at': DateTime.now().toIso8601String(),
      'migrated_from': current,
    });

    _rebuildIndex();
    return (from: current, to: target);
  }

  void _migrateV0ToV1() {
    _ensureDir('$_rootPath/observations');
    _ensureDir('$_rootPath/sessions');
    _ensureDir('$_rootPath/traces');
    _ensureDir('$_rootPath/failures');
  }

  // ============ 内部辅助 ============

  void _ensureDir(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  void _writeSchemaVersion() {
    final path = '$_rootPath/schema_version.json';
    if (File(path).existsSync()) return;
    _atomicWrite(path, {
      'adi_version': '0.1',
      'adi_protocol_version': '1.0',
      'schema_version': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Crash-safe atomic write：temp → write → flush → rename。
  void _atomicWrite(String path, Map<String, Object?> data) {
    final tempPath = '$path.tmp';
    final file = File(tempPath);
    final raf = file.openSync(mode: FileMode.write);
    try {
      raf.writeStringSync(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    file.renameSync(path);
  }

  Map<String, Object?>? _readJson(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    } catch (e) {
      stderr.writeln('[ADI] _readJson failed for $path: $e');
      return null;
    }
  }
}
