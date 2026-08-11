/// ADI Aggregation：故障聚合纯函数（无 I/O 副作用）。
///
/// 从 [AdiStorage] 提取聚合逻辑为纯函数，便于单元测试与复用。
/// Storage 层负责 I/O（读写 .adi/ 文件），本模块只做数据变换。
///
/// 落地 ADR-0024 §2.6（Failure Aggregation）。
library;

import 'adi_record.dart';

/// 聚合 error records 为 failure records。
///
/// 按 failureId（SHA-256 of errorType + stackHash）分组，合并：
/// - firstSeen / lastSeen（时间范围）
/// - occurrences（取 max(records.length, existing.occurrences)，不覆盖历史）
/// - traceIds / sessionIds（去重并集）
/// - status（保留 existing.status，新 failure 默认 open）
///
/// [existingFailures]：已存在的 failure records（key = failureId）。
/// 返回所有 failureId → 聚合后 AdiFailureRecord 的 Map。
Map<String, AdiFailureRecord> aggregateErrors(
  List<AdiErrorRecord> errors,
  Map<String, AdiFailureRecord> existingFailures,
) {
  if (errors.isEmpty) return {};

  final byFailureId = <String, List<AdiErrorRecord>>{};
  for (final error in errors) {
    final fid = AdiFailureRecord.computeFailureId(
      error.errorType,
      error.stackHash,
    );
    byFailureId.putIfAbsent(fid, () => []).add(error);
  }

  final result = <String, AdiFailureRecord>{};
  for (final entry in byFailureId.entries) {
    final fid = entry.key;
    final records = entry.value;
    records.sort((a, b) => a.time.compareTo(b.time));

    final existing = existingFailures[fid];
    final firstSeen = records.first.time;
    final lastSeen = records.last.time;
    final traceIds = records.map((r) => r.traceId).toSet().toList();
    final sessionIds = records.map((r) => r.sessionId).toSet().toList();

    result[fid] = AdiFailureRecord(
      failureId: fid,
      firstSeen: existing != null
          ? (existing.firstSeen.isBefore(firstSeen)
              ? existing.firstSeen
              : firstSeen)
          : firstSeen,
      lastSeen: existing != null
          ? (existing.lastSeen.isAfter(lastSeen)
              ? existing.lastSeen
              : lastSeen)
          : lastSeen,
      occurrences: existing != null
          ? (records.length > existing.occurrences
              ? records.length
              : existing.occurrences)
          : records.length,
      errorType: records.first.errorType,
      stackHash: records.first.stackHash,
      traceIds: traceIds,
      sessionIds: sessionIds,
      status: existing?.status ?? AdiFailureStatus.open,
    );
  }

  return result;
}

/// 构建 index.json 索引内容。
///
/// 包含 observations 和 failures 两个列表，供 CLI 快速查询。
Map<String, Object?> buildIndex(
  List<AdiErrorRecord> errors,
  List<AdiFailureRecord> failures,
) {
  return {
    'updated_at': DateTime.now().toIso8601String(),
    'observations': errors
        .map((e) => {
              'id': e.id,
              'errorType': e.errorType,
              'time': e.time.toIso8601String(),
              'sessionId': e.sessionId,
              'traceId': e.traceId,
            })
        .toList(),
    'failures': failures
        .map((f) => {
              'failureId': f.failureId,
              'errorType': f.errorType,
              'occurrences': f.occurrences,
              'status': f.status.name,
              'lastSeen': f.lastSeen.toIso8601String(),
            })
        .toList(),
  };
}