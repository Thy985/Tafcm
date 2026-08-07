/// ErrorSnapshotter：自动错误快照捕获器。
///
/// 在以下时机自动触发 Error Snapshot：
/// 1. CommandHandler.handle() 异常（try/catch）
/// 2. TransactionBuilder.rollback() 非预期回滚
/// 3. 全局异常（FlutterError.onError / PlatformDispatcher.onError）
/// 4. Invariant Checker 失败
///
/// LIGHT 模式：仅保存 metadata + logs + AST hash，不含文档正文。
/// FULL 模式：可额外保存文档正文，需显式开启 includeDocumentContent。
///
/// 隐私保护：includeDocumentContent 标志每次 App 启动重置为 false。
///
/// 落地 ADR-0021 §2.4（Layer 4：Error Snapshot）+ §3.7.2。
library;

import 'dart:convert';

import 'error_snapshot.dart';
import 'observability_service.dart';

/// 错误快照捕获器。
///
/// 持有 [ObservabilityService] 引用，在异常触发时从 CommandTracer /
/// TransactionTracer 提取最近记录，组装为 [ErrorSnapshot]。
class ErrorSnapshotter {
  /// 关联的可观测服务。
  final ObservabilityService observability;

  /// 最近一次 Error Snapshot（内存保留最近 1 次）。
  ErrorSnapshot? _lastSnapshot;

  /// 是否包含文档正文（FULL 模式，每次 App 启动重置为 false）。
  bool _includeDocumentContent = false;

  /// App 版本号（由外部注入，如 package_info_plus）。
  String _appVersion = '';

  /// 设备型号（由外部注入，如 device_info_plus）。
  String _device = '';

  /// 操作系统版本。
  String _os = '';

  ErrorSnapshotter({required this.observability});

  /// 获取最近一次 Error Snapshot。
  ErrorSnapshot? get lastSnapshot => _lastSnapshot;

  /// 当前是否包含文档正文。
  bool get includeDocumentContent => _includeDocumentContent;

  /// 设置是否包含文档正文（仅 FULL 模式）。
  ///
  /// 每次 App 启动时自动重置为 false，防止用户意外泄露私人笔记。
  void setIncludeDocumentContent(bool value) {
    _includeDocumentContent = value;
  }

  /// 设置 App 环境信息（由外部注入）。
  void setAppInfo({String version = '', String device = '', String os = ''}) {
    _appVersion = version;
    _device = device;
    _os = os;
  }

  /// 捕获错误快照。
  ///
  /// [type]：错误类型（CommandExecutionError / TransactionRollback /
  ///   GlobalError / InvariantFailure）
  /// [message]：错误消息
  /// [commandName]：出错的 Command 名称（可选）
  /// [commandParams]：出错的 Command 参数（可选）
  /// [cursorBlockId]：光标所在 Block ID（可选）
  /// [cursorOffset]：光标偏移量（可选）
  ///
  /// 返回生成的 [ErrorSnapshot]。
  ErrorSnapshot capture({
    required String type,
    required String message,
    String? commandName,
    Map<String, Object?>? commandParams,
    String? cursorBlockId,
    int? cursorOffset,
  }) {
    final now = DateTime.now();
    final id = _generateId(now);

    // 从 CommandTracer 提取最近操作摘要
    final recentOps = _buildRecentOperations();

    final ctx = observability.currentContext;

    final snapshot = ErrorSnapshot(
      id: id,
      timestamp: now,
      type: type,
      message: message,
      commandName: commandName,
      commandParams: commandParams,
      cursorBlockId: cursorBlockId,
      cursorOffset: cursorOffset,
      recentOperations: recentOps,
      appVersion: _appVersion,
      device: _device,
      os: _os,
      traceId: ctx?.traceId,
      sessionId: observability.sessionId,
      captureMode: _includeDocumentContent ? CaptureMode.full : CaptureMode.light,
      includeDocumentContent: _includeDocumentContent,
    );

    _lastSnapshot = snapshot;
    return snapshot;
  }

  /// 生成快照 ID。
  String _generateId(DateTime now) {
    final date = '${now.year}${_pad(now.month)}${_pad(now.day)}';
    final time = '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    return 'err_$date$time';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 从 CommandTracer + TransactionTracer 提取最近操作摘要。
  List<Map<String, Object?>> _buildRecentOperations() {
    final ops = <Map<String, Object?>>[];

    // 提取最近 Command 记录（最多 10 条）
    for (final entry in observability.commandTracer.entries.reversed.take(10)) {
      ops.add({
        'time': entry.timestamp.toIso8601String(),
        'action': entry.commandName,
        'value': entry.params.toString(),
        'succeeded': entry.succeeded,
        if (entry.errorMessage != null) 'error': entry.errorMessage,
      });
    }

    // 提取最近 Transaction 记录（最多 5 条）
    for (final entry in observability.transactionTracer.entries.reversed.take(5)) {
      ops.add({
        'time': 'tx_${entry.transactionId}',
        'action': 'Transaction.${entry.result.name}',
        'value': 'origin=${entry.origin.name}',
        if (entry.rollbackReason != null) 'error': entry.rollbackReason,
      });
    }

    return ops;
  }

  /// 将 ErrorSnapshot 导出为 JSON 兼容 Map（用于 zip 导出）。
  Map<String, Object?> toJson(ErrorSnapshot snapshot) {
    return snapshot.toJson();
  }

  /// 序列化为 JSON 字符串。
  String toJsonString(ErrorSnapshot snapshot) {
    return const JsonEncoder.withIndent('  ').convert(toJson(snapshot));
  }
}