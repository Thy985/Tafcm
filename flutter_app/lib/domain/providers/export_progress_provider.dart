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

import 'dart:typed_data';

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

/// 导出完成（bytes 由调用方消费）。
class ExportCompletedState extends ExportState {
  const ExportCompletedState({required this.format, required this.bytes});

  final ExportFormat format;
  final Uint8List bytes;
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
  void start(ExportFormat format) {
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

  /// 导出成功。
  void complete(ExportFormat format, Uint8List bytes) {
    state = ExportCompletedState(format: format, bytes: bytes);
  }

  /// 导出失败。
  void fail(ExportFormat format, ExportFailure failure) {
    state = ExportFailedState(format: format, failure: failure);
  }

  /// 重置为空闲（例如 SnackBar 关闭后、用户再次选择导出前）。
  void reset() {
    state = const ExportIdleState();
  }
}

/// 导出进度全局 Provider（3.4.4 Slice 7）。
///
/// 由持有 ref 的层（EditorPage）写入，由 [ExportProgressOverlay] 监听消费。
/// chrome/widgets/blocks 各层严禁直接读写（AGENTS.md §6.1 + §6.5 守门）。
final exportProgressProvider =
    StateNotifierProvider<ExportProgressNotifier, ExportState>(
  (ref) => ExportProgressNotifier(),
);
