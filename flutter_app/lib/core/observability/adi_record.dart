/// ADI Record：.adi/ 持久化 schema（Layer 2）。
///
/// 三层模型中的持久化层，字段集稳定，变更需 schema_version 升级。
/// 由 [ErrorSnapshot]（Layer 1 runtime event）通过 toRecord() 投影生成。
/// 由 [AdiView]（Layer 3 Agent 视图）通过 toView() 消费。
///
/// 落地 ADR-0024 §2.1（三层模型分离）。
library;

import 'package:crypto/crypto.dart';

import 'error_snapshot.dart';

/// ADI 持久化记录基类。
///
/// 字段集稳定，变更需 schema_version 升级（见 AdiStorage）。
sealed class AdiRecord {
  String get id;
  DateTime get time;
  String get sessionId;
  String get traceId;
  Map<String, Object?> toJson();
}

/// 错误记录（对应 .adi/observations/obs_NNN.json）。
class AdiErrorRecord extends AdiRecord {
  @override
  final String id;
  @override
  final DateTime time;
  @override
  final String sessionId;
  @override
  final String traceId;
  final String source;
  final String errorType;
  final String message;
  final String? stackHash;
  final String? commandName;

  AdiErrorRecord({
    required this.id,
    required this.time,
    required this.sessionId,
    required this.traceId,
    required this.source,
    required this.errorType,
    required this.message,
    this.stackHash,
    this.commandName,
  });

  /// 从 [ErrorSnapshot] 投影生成。
  factory AdiErrorRecord.fromSnapshot(
    ErrorSnapshot snapshot, {
    String source = 'unknown',
  }) {
    return AdiErrorRecord(
      id: snapshot.id,
      time: snapshot.timestamp,
      sessionId: snapshot.sessionId ?? 'unknown',
      traceId: snapshot.traceId ?? 'unknown',
      source: source,
      errorType: snapshot.type,
      message: snapshot.message,
      commandName: snapshot.commandName,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'sessionId': sessionId,
        'traceId': traceId,
        'source': source,
        'errorType': errorType,
        'message': message,
        if (stackHash != null) 'stackHash': stackHash,
        if (commandName != null) 'commandName': commandName,
      };

  factory AdiErrorRecord.fromJson(Map<String, Object?> json) {
    return AdiErrorRecord(
      id: json['id'] as String,
      time: DateTime.parse(json['time'] as String),
      sessionId: json['sessionId'] as String,
      traceId: json['traceId'] as String,
      source: json['source'] as String? ?? 'unknown',
      errorType: json['errorType'] as String,
      message: json['message'] as String,
      stackHash: json['stackHash'] as String?,
      commandName: json['commandName'] as String?,
    );
  }
}

/// 不变量检查记录（对应 .adi/observations/ 下 invariant 记录）。
class AdiInvariantRecord extends AdiRecord {
  @override
  final String id;
  @override
  final DateTime time;
  @override
  final String sessionId;
  @override
  final String traceId;
  final List<String> violated;
  final List<String> checked;

  AdiInvariantRecord({
    required this.id,
    required this.time,
    required this.sessionId,
    required this.traceId,
    required this.violated,
    required this.checked,
  });

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'sessionId': sessionId,
        'traceId': traceId,
        'violated': violated,
        'checked': checked,
      };

  factory AdiInvariantRecord.fromJson(Map<String, Object?> json) {
    return AdiInvariantRecord(
      id: json['id'] as String,
      time: DateTime.parse(json['time'] as String),
      sessionId: json['sessionId'] as String,
      traceId: json['traceId'] as String,
      violated: (json['violated'] as List?)?.cast<String>() ?? [],
      checked: (json['checked'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// 故障聚合状态。
enum AdiFailureStatus { open, fixed, recurring }

/// 故障聚合记录（对应 .adi/failures/f_NNN.json）。
///
/// 同一 bug 的多次 occurrence 归为同一 failureId。
/// 去重键：hash(errorType + stackHash)。
class AdiFailureRecord {
  final String failureId;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int occurrences;
  final String errorType;
  final String? stackHash;
  final List<String> traceIds;
  final List<String> sessionIds;
  final AdiFailureStatus status;

  const AdiFailureRecord({
    required this.failureId,
    required this.firstSeen,
    required this.lastSeen,
    required this.occurrences,
    required this.errorType,
    this.stackHash,
    required this.traceIds,
    required this.sessionIds,
    required this.status,
  });

  AdiFailureRecord copyWith({
    DateTime? lastSeen,
    int? occurrences,
    List<String>? traceIds,
    List<String>? sessionIds,
    AdiFailureStatus? status,
  }) {
    return AdiFailureRecord(
      failureId: failureId,
      firstSeen: firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      occurrences: occurrences ?? this.occurrences,
      errorType: errorType,
      stackHash: stackHash,
      traceIds: traceIds ?? this.traceIds,
      sessionIds: sessionIds ?? this.sessionIds,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
        'failureId': failureId,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'occurrences': occurrences,
        'errorType': errorType,
        if (stackHash != null) 'stackHash': stackHash,
        'traceIds': traceIds,
        'sessionIds': sessionIds,
        'status': status.name,
      };

  factory AdiFailureRecord.fromJson(Map<String, Object?> json) {
    return AdiFailureRecord(
      failureId: json['failureId'] as String,
      firstSeen: DateTime.parse(json['firstSeen'] as String),
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      occurrences: json['occurrences'] as int? ?? 1,
      errorType: json['errorType'] as String,
      stackHash: json['stackHash'] as String?,
      traceIds: (json['traceIds'] as List?)?.cast<String>() ?? [],
      sessionIds: (json['sessionIds'] as List?)?.cast<String>() ?? [],
      status: AdiFailureStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String? ?? 'open'),
        orElse: () => AdiFailureStatus.open,
      ),
    );
  }

  /// 计算 failureId 去重键。
  ///
  /// 使用 SHA-256 而非 [String.hashCode]，因为 hashCode 在不同 VM 运行间
  /// 不稳定（Dart 哈希随机化），会导致同一 bug 跨 session 生成不同 failureId。
  static String computeFailureId(String errorType, String? stackHash) {
    final input = '$errorType|${stackHash ?? ''}';
    final digest = sha256.convert(input.codeUnits);
    return 'f_${digest.toString().substring(0, 16)}';
  }
}