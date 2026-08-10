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

import 'adi_record.dart';

/// ADI 存储抽象接口。
abstract class AdiStorage {
  void writeErrorRecord(AdiErrorRecord record);
  AdiErrorRecord? latestErrorRecord();
  AdiErrorRecord? findErrorByTraceId(String traceId);
  List<AdiErrorRecord> allErrorRecords();
  void writeFailureRecord(AdiFailureRecord record);
  AdiFailureRecord? loadFailure(String failureId);
  int readSchemaVersion();
  bool get isInitialized;
  void initialize();
  String get rootPath;
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
  int readSchemaVersion() {
    final json = _readJson('$_rootPath/schema_version.json');
    return json?['schema_version'] as int? ?? 0;
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

  /// Crash-safe atomic write：temp → write → rename。
  void _atomicWrite(String path, Map<String, Object?> data) {
    final tempPath = '$path.tmp';
    File(tempPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    File(tempPath).renameSync(path);
  }

  Map<String, Object?>? _readJson(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }
}
