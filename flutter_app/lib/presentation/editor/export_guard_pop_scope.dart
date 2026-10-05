/// 导出进行中的返回拦截（issue #323）。
///
/// 修复行为（QA 实测：导出中按 BACK → 编辑器直接退出、导出既不取消也不报错、
/// 进度浮层冻结残留在首页）：
///   - 导出**未**进行中：BACK 行为与原实现一致 —— 兜底 `context.go('/home')`。
///   - 导出进行中：拦截 BACK，弹确认对话框「导出进行中」；
///     - 用户选「继续导出」→ 留在编辑器，导出继续；
///     - 用户选「取消导出并退出」→ 协作式取消导出（令牌置位，管线在下一个
///       阶段检查点抛 ExportCancelledException）→ 返回首页，浮层随编辑器
///       路由销毁，无孤儿残留。
///
/// **挂载层级**：本 widget 必须包住 [ExportProgressOverlay]（编辑器路由内），
/// 保证「浮层绝不存活于编辑器路由之外」——任何离开编辑器路由的路径都会
/// 先经过本拦截或触发浮层 dispose 的兜底取消。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/providers/export_progress_provider.dart';

/// 导出进行中 BACK → 确认对话框。
///
/// 返回 `true` = 用户确认「取消导出并退出」；`false` = 留在编辑器继续导出
/// （含对话框被系统返回键关闭的情况）。
@visibleForTesting
Future<bool> confirmExitDuringExport(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    // 语义上必须二选一：点空白处不关闭，防止误触后处于「对话框关闭但
    // 导出/退出状态不明」的中间态。
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('导出进行中'),
      content: const Text('导出尚未完成，退出将取消本次导出。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('继续导出'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('取消导出并退出'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 包住编辑器子树的 PopScope：导出进行中拦截 BACK 并确认。
class ExportGuardPopScope extends ConsumerWidget {
  const ExportGuardPopScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // select 布尔：只在「空闲 ⇄ 进行中」切换时重建（PR #246 整树重建教训——
    // 直接 watch 整个 provider 会让每次进度上报都重建 EditorShell 子树）。
    final isExporting = ref.watch(
      exportProgressProvider.select((state) => state is ExportInProgressState),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (isExporting) {
          final confirmed = await confirmExitDuringExport(context);
          if (!confirmed) return; // 留在编辑器，导出继续
          // 协作式取消：令牌置位 + 状态回 Idle（浮层立即关闭）。
          ref.read(exportProgressProvider.notifier).cancel();
        }
        if (context.mounted) {
          context.go('/home');
        }
      },
      child: child,
    );
  }
}
