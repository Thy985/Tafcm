/// ADI Query Adapter：AdiRecord → AdiView 投影 + 查询。
///
/// 把 ObservabilityService 的内部能力包装为 Agent 可查询的协议接口。
/// 双源查询：内存实时（ObservabilityService）+ 磁盘跨 session（AdiStorage）。
///
/// 落地 ADR-0024 §2.2（Query Adapter）。
library;

import 'adi_record.dart';
import 'adi_storage.dart';
import 'adi_view.dart';
import 'error_snapshot.dart';
import 'observability_service.dart';

/// 查询适配器抽象接口。
abstract class AdiQueryAdapter {
  AdiErrorView? latestError();
  AdiTraceView? traceView(String traceId);
  List<AdiErrorView> recentFailures({int limit = 20});
}

/// 查询适配器实现。
class AdiQueryAdapterImpl implements AdiQueryAdapter {
  final ObservabilityService _service;
  final AdiStorage _storage;

  AdiQueryAdapterImpl(this._service, this._storage);

  @override
  AdiErrorView? latestError() {
    final snapshot = _service.lastErrorSnapshot;
    if (snapshot != null) {
      return _projectSnapshot(snapshot);
    }
    final record = _storage.latestErrorRecord();
    return record != null ? _projectRecord(record) : null;
  }

  @override
  AdiTraceView? traceView(String traceId) {
    final ctx = _service.currentContext;
    if (ctx != null && ctx.traceId == traceId) {
      return AdiTraceView(
        id: traceId,
        traceId: traceId,
        sessionId: ctx.sessionId,
        spans: [
          AdiSpanNode(
            spanId: ctx.spanId,
            parentSpanId: ctx.parentSpanId,
            layer: 'current',
            description: 'Active trace context',
            timestamp: DateTime.now(),
          ),
        ],
      );
    }
    final entries = _service.commandTracer.entries
        .where((e) => e.traceId == traceId)
        .toList();
    if (entries.isNotEmpty) {
      return AdiTraceView(
        id: traceId,
        traceId: traceId,
        sessionId: _service.sessionId,
        spans: entries
            .map((e) => AdiSpanNode(
                  spanId: e.spanId ?? traceId,
                  parentSpanId: null,
                  layer: 'command',
                  description: e.commandName,
                  timestamp: e.timestamp,
                ))
            .toList(),
      );
    }
    return null;
  }

  @override
  List<AdiErrorView> recentFailures({int limit = 20}) {
    final records = _storage.allErrorRecords().take(limit).toList();
    return records.map(_projectRecord).toList();
  }

  // ============ 投影 ============

  AdiErrorView _projectSnapshot(ErrorSnapshot snapshot) {
    return AdiErrorView(
      id: snapshot.id,
      traceId: snapshot.traceId ?? 'unknown',
      errorType: snapshot.type,
      message: snapshot.message,
      replayAvailable: _hasReplayData(snapshot.sessionId),
      snapshotPath: '.adi/observations/${snapshot.id}.json',
      quality: _service.isFull
          ? AdiObservationQuality.complete
          : AdiObservationQuality.partial,
      sessionId: snapshot.sessionId,
      commandName: snapshot.commandName,
    );
  }

  AdiErrorView _projectRecord(AdiErrorRecord record) {
    return AdiErrorView(
      id: record.id,
      traceId: record.traceId,
      errorType: record.errorType,
      message: record.message,
      replayAvailable: _hasReplayData(record.sessionId),
      snapshotPath: '.adi/observations/${record.id}.json',
      quality: _service.isFull
          ? AdiObservationQuality.complete
          : AdiObservationQuality.partial,
      sessionId: record.sessionId,
      commandName: record.commandName,
    );
  }

  bool _hasReplayData(String? sessionId) {
    if (sessionId == null) return false;
    return sessionId == _service.sessionId &&
        _service.commandTracer.entries.isNotEmpty;
  }
}