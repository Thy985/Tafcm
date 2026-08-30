/// 导出进度浮层（Phase 3.4 Slice 7 / §3.7 3.4.4）。
///
/// 单一 ConsumerWidget 监听 [exportProgressProvider]，把每次 state 切换翻译为
/// ScaffoldMessenger 上的 SnackBar：
///   - [ExportInProgressState]：SnackBar 含 LinearProgressIndicator + 阶段
///     文案 + 完成百分比，常驻（duration = 1 天）让用户看到完整进度。
///   - [ExportCompletedState]：自动消失提示文案"导出完成"。
///   - [ExportFailedState]：长提示 [ExportFailure.userMessage]（ErrorMessage
///     friendly 规范 — 不暴露 stack，AGENTS.md §4.4）。
///   - [ExportIdleState]：清掉任何残留 SnackBar。
///
/// **依赖方向**：本 widget 在 EditorShell 顶层包住子树，需在 Scaffold 之内；
/// 不在 chrome/blocks 内直接使用（AGENTS.md §6.5 依赖图单向）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/providers/export_progress_provider.dart';
import '../../domain/services/export_service.dart';

/// 监听 [exportProgressProvider] 渲染 SnackBar 进度提示。
///
/// 用法：
/// ```dart
/// ExportProgressOverlay(
///   child: EditorShell(...),
/// )
/// ```
class ExportProgressOverlay extends ConsumerStatefulWidget {
  const ExportProgressOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ExportProgressOverlay> createState() =>
      _ExportProgressOverlayState();
}

class _ExportProgressOverlayState extends ConsumerState<ExportProgressOverlay> {
  /// PR-4：Completed / Failed SnackBar 计时器。dispose 时取消以避免
  /// "Timer is still pending" 报错（实测bug.md §Bug4 修复的副作用）。
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    _resetTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ExportState>(exportProgressProvider, (prev, next) {
      final messenger = ScaffoldMessenger.of(context);
      // 切换到新状态前先清掉旧 SnackBar，避免叠加。
      messenger.hideCurrentSnackBar();
      switch (next) {
        case ExportIdleState():
          // reset：已经 hideCurrent，再做一次幂等保护；同时取消任何
          // 进行中的 reset 计时器（已无意义）。
          messenger.hideCurrentSnackBar();
          _resetTimer?.cancel();
          _resetTimer = null;
        case ExportInProgressState():
          messenger.showSnackBar(_progressSnackBar(next));
          // InProgress 期间先 cancel 任何未触发的 reset（防误触发）。
          _resetTimer?.cancel();
          _resetTimer = null;
        case ExportCompletedState():
          // PR-4：Completed SnackBar 显示完成后，主动 reset() 把 provider
          // 拉回 Idle，避免 exportProgressProvider 永远停在 Completed
          // 状态（实测bug.md §Bug4）。
          messenger.showSnackBar(
            SnackBar(
              content: Text('已导出 ${_formatLabel(next.format)}'),
              duration: const Duration(seconds: 2),
            ),
          );
          _scheduleReset(const Duration(seconds: 2));
        case ExportFailedState():
          // PR-4：Failed SnackBar 显示完成后，主动 reset()。
          messenger.showSnackBar(
            SnackBar(
              content: Text('导出失败：${_failureMessage(next.failure)}'),
              duration: const Duration(seconds: 4),
            ),
          );
          _scheduleReset(const Duration(seconds: 4));
      }
    });
    return widget.child;
  }

  /// PR-4：Completed / Failed SnackBar 显示 [delay] 后调 [reset]，让
  /// [exportProgressProvider] 回到 Idle。避免"导出成功但 provider state
  /// 永久停在 Completed"——下次重新进 EditorScreen 仍能看到 Completed
  /// 状态（虽然 SnackBar 已自动消失，但 state 残留违反 state machine
  /// 不变量）。
  ///
  /// 用 [Timer] 而非 `Future.delayed`：Timer 可在 [dispose] 中显式 cancel，
  /// 避免 `Future.delayed` 留下的"pending timer"在 widget 测试 teardown 时
  /// 触发 `'!timersPending'` 断言失败。
  void _scheduleReset(Duration delay) {
    _resetTimer?.cancel();
    _resetTimer = Timer(delay, () {
      if (!mounted) return;
      try {
        ref.read(exportProgressProvider.notifier).reset();
      } catch (_) {
        // provider 已 dispose（页面销毁时）—— 静默吞掉，避免在测试
        // teardown 时抛 unhandled future error。
      }
      _resetTimer = null;
    });
  }

  /// 进行中状态的 SnackBar：阶段文案 + 百分比 + LinearProgressIndicator。
  SnackBar _progressSnackBar(ExportInProgressState state) {
    final pct = (state.progress.fraction * 100).toInt();
    final label = _stageLabel(state.progress.stage);
    final detail = state.progress.total > 0
        ? '$label · ${state.progress.completed}/${state.progress.total} ($pct%)'
        : '$label · 准备中…';
    return SnackBar(
      // 极长 duration：导出可能持续数十秒（PDF 公式 + Mermaid 渲染耗时），
      // 由下一次 state 切换显式 dismiss，不依赖自动超时。
      duration: const Duration(days: 1),
      content: SizedBox(
        height: 44,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('正在导出 ${_formatLabel(state.format)} · $detail'),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: state.progress.fraction.clamp(0.0, 1.0)),
          ],
        ),
      ),
    );
  }

  static String _stageLabel(ExportStage stage) => switch (stage) {
        ExportStage.collectingFormulas => '解析文档',
        ExportStage.preRenderingFormulaSvg => '渲染公式',
        ExportStage.renderingBlocks => '渲染块',
        ExportStage.assembling => '组装文件',
      };

  static String _formatLabel(ExportFormat fmt) => switch (fmt) {
        ExportFormat.pdf => 'PDF',
        ExportFormat.docx => 'Word',
        ExportFormat.txt => 'TXT',
      };

  /// ExportFailure → 用户友好短文案（与 export_service.dart::classifyError
  /// 给出的 userMessage 保持同口径，避免 UI 重复写策略）。
  static String _failureMessage(ExportFailure kind) => switch (kind) {
        ExportFailure.emptyDocument => '文档为空',
        ExportFailure.offline => '网络不可达',
        ExportFailure.parseError => '文档格式错误',
        ExportFailure.renderError => '渲染失败，可能含有不支持的语法',
        ExportFailure.writeError => '写入失败',
        ExportFailure.timeout => '导出超时，请重试',
        ExportFailure.unknown => '导出失败',
      };
}
