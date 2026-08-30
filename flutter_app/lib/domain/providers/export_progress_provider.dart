/// 导出进度状态层（3.4.4 Slice 7）。
///
/// 单一 Notifier 把 [ExportProgress] 报告的回调序列整合为可被 UI 监听/消费的
/// 状态机。状态本身在 ExportService.exportToXxx 进行中驱动，UI 通过
/// [exportProgressProvider] watch。
///
/// 设计原则：
///   - **状态可穷尽**：`sealed` 联合 + pattern matching；UI 用 `switch` 确保
///     每个分支被覆盖（Phase 3.4 Dart 现代特性使用，AGENTS.md §2.2）。
///   - **不持有业务对象**：`ExportInProgressState.format` 只存 `ExportFormat`
///     enum（轻量），不持有未导出的字节流；导出字节流留在调用方（EditorPage）
///     自行写到临时文件并触发 share，与项目沿用的「ExportService.exportAndShare」
///     行为对齐（不重复实现分享路径）。
///   - **不在 chrome/blocks 暴露 Riverpod**：UI 通过 [ExportProgressOverlay]
///     ConsumerWidget 集中消费，chrome/editor_app_bar 保持 Riverpod-free。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/export_service.dart';

/// 导出状态 sealed 联合（3.4.4 Slice 7）。
sealed class ExportState {
  const ExportState();
}

/// 空闲（初始 / 上次导出后已重置）。
class ExportIdleState extends ExportState {
  const ExportIdleState();
}

/// 导出进行中。
class ExportInProgressState extends ExportState {
  const ExportInProgressState({
    required this.format,
    required this.progress,
  });

  /// 当前导出格式（用于 SnackBar 标题/图标）。
  final ExportFormat format;

  /// 当前阶段的进度快照。
  final ExportProgress progress;
}

/// 导出完成（仅表达语义，bytes 由调用方直接消费，不经过 Provider 状态机传输）。
class ExportCompletedState extends ExportState {
  const ExportCompletedState({required this.format});

  final ExportFormat format;
}

/// 导出失败。
class ExportFailedState extends ExportState {
  const ExportFailedState({
    required this.format,
    required this.failure,
  });

  final ExportFormat format;
  final ExportFailure failure;
}

/// ExportProgressNotifier（3.4.4 Slice 7）。
///
/// 调用方式（典型流程）：
/// ```dart
/// final notifier = ref.read(exportProgressProvider.notifier);
/// notifier.start(ExportFormat.pdf);
/// try {
///   final bytes = await MarkdownExporter.exportToPdf(
///     markdown,
///     onProgress: notifier.report,
///   );
///   notifier.complete(ExportFormat.pdf, bytes);
/// } catch (e) {
///   notifier.fail(ExportFormat.pdf, classifyError(e).kind);
/// }
/// ```
class ExportProgressNotifier extends StateNotifier<ExportState> {
  ExportProgressNotifier() : super(const ExportIdleState());

  /// 启动一次导出（进入 [ExportInProgressState]）。
  ///
  /// 防止并发：已在导出中时直接返回（不覆盖前一次进度，也不抛异常中断调用方）。
  void start(ExportFormat format) {
    if (state is ExportInProgressState) return;
    state = ExportInProgressState(
      format: format,
      progress: const ExportProgress(
        stage: ExportStage.collectingFormulas,
        completed: 0,
        total: 1,
      ),
    );
  }

  /// 由 [MarkdownExporter.exportToXxx] 的 [ExportProgressCallback] 直接调用。
  ///
  /// 仅在 [ExportInProgressState] 时更新 state；不会从 [ExportIdleState]
  /// 跳变（防御：保证 start 与 report 配对）。
  void report(ExportProgress progress) {
    final current = state;
    if (current is ExportInProgressState) {
      state = ExportInProgressState(format: current.format, progress: progress);
    }
  }

  /// 导出成功（仅表达语义，bytes 留在调用方）。
  void complete(ExportFormat format) {
    state = ExportCompletedState(format: format);
  }

  /// 导出失败。
  void fail(ExportFormat format, ExportFailure failure) {
    state = ExportFailedState(format: format, failure: failure);
  }

  /// 重置为空闲（例如 SnackBar 关闭后、用户再次选择导出前）。
  void reset() {
    state = const ExportIdleState();
  }

  /// Terminal-state guarantee 包装器（PR-4 状态机硬化）。
  ///
  /// 不变量（实测bug.md §PR-4）：
  /// > 无论 success / timeout / exception / cancel / partial failure，
  /// > 都必须最终 `reset()` —— 不让 UI 依赖某个 happy path 调用 `complete()`。
  ///
  /// 行为：
  /// 1. `start(format)`（与直接调 [start] 同样的并发保护：guard 进行中不重入）
  /// 2. await [body] —— 调用方写导出 + 写盘 + share 等完整流程
  /// 3. 成功：state = Completed
  /// 4. 失败：[body] 抛异常 → 用 [classifyError] 映射为 [ExportFailure]
  ///    → state = Failed；异常继续向上抛（调用方可继续做 observability 记录）
  /// 5. **finally：state = Idle**（无论 1-4 哪条路径）
  ///
  /// **设计要点**：fail 分类由本方法内部完成（不依赖调用方记得调 [fail]）。
  /// 这是闭环 Bug4 的关键 —— 旧实现让 UI 自己 try/catch/finally 散落
  /// `start/complete/fail/reset`，只要"导出主流程成功但写盘/分享阶段失败"就
  /// 漏调 fail → SnackBar 永久显示。runWithGuard 把这 4 个调用合并为一个
  /// 不变量。
  ///
  /// [onError]（可选）：在 [body] 抛异常后、调 [fail] 之前调用，参数为
  /// `(error, stack)`。用于把异常写入 observability / 日志。
  ///
  /// [errorClassifier]（可选）：自定义异常 → [ExportFailure] 映射；默认走
  /// `export_service.classifyError`。测试可注入 stub。
  Future<T> runWithGuard<T>(
    ExportFormat format,
    Future<T> Function() body, {
    void Function(Object error, StackTrace stack)? onError,
    ExportFailure Function(Object error)? errorClassifier,
  }) async {
    start(format);
    final classify = errorClassifier ?? _defaultClassifyError;
    try {
      final result = await body();
      complete(format);
      return result;
    } catch (e, st) {
      onError?.call(e, st);
      fail(format, classify(e));
      rethrow;
    } finally {
      // 无论 success / fail / throw，最终都回 Idle —— 防止"导出完成
      // 但状态栏永久存在"（Bug4）。
      reset();
    }
  }

  /// 默认异常分类：委托给 `export_service.classifyError`。
  ExportFailure _defaultClassifyError(Object e) => classifyError(e).kind;
}

/// 导出进度全局 Provider（3.4.4 Slice 7）。
///
/// 由持有 ref 的层（EditorPage）写入，由 [ExportProgressOverlay] 监听消费。
/// chrome/widgets/blocks 各层严禁直接读写（AGENTS.md §6.1 + §6.5 守门）。
final exportProgressProvider =
    StateNotifierProvider<ExportProgressNotifier, ExportState>(
  (ref) => ExportProgressNotifier(),
);
