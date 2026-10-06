/// 导出协作式取消令牌（issue #323：导出中 BACK 不确认、管线既不取消也不完成）。
///
/// 协作式取消模型：
///   - 调用方（[ExportProgressNotifier] / EditorExportActions）在一次导出开始时
///     创建令牌，导出进行中持有；
///   - 导出管线（PdfExporter / WordExporter / TextExporter）接收可选令牌，
///     在阶段边界（入口 / 公式预渲染批次 / 逐块 / 逐片拼装 / 写盘前）调用
///     [ExportCancelToken.throwIfCancelled] 检查；
///   - 用户确认退出时 [ExportCancelToken.cancel] 置位，管线在下一个检查点抛出
///     [ExportCancelledException]，由 runWithGuard 归 Idle（非 Failed）。
///
/// 选择「协作式边界检查」而非强杀：导出管线是纯 async Future，Dart 无法中断
/// 在途 await；但所有阶段边界都是检查点，观察延迟 ≤ 单块/单公式渲染耗时
/// （有 5-30s 超时兜底），且不会留下半写的临时文件。
library;

/// 协作式取消令牌。
///
/// 单次导出一个实例；[cancel] 幂等，可从任意调用方（确认对话框、浮层
/// dispose 兜底）触发。
class ExportCancelToken {
  bool _cancelled = false;

  /// 是否已请求取消。
  bool get isCancelled => _cancelled;

  /// 请求取消（幂等）。仅置位标志，不中断正在执行的同步代码——
  /// 管线在下一个检查点抛出 [ExportCancelledException]。
  void cancel() => _cancelled = true;

  /// 管线检查点：已取消则抛出 [ExportCancelledException]。
  void throwIfCancelled() {
    if (_cancelled) throw const ExportCancelledException();
  }
}

/// 用户取消导出时由管线检查点抛出。
///
/// [ExportProgressNotifier.runWithGuard] 捕获后**不**归类为 Failed——
/// 取消是用户意图，不是错误；状态经 finally 归 Idle，异常继续上抛由
/// 调用方（EditorExportActions）吞掉，避免 zone 未捕获异常噪音。
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => 'ExportCancelledException';
}
