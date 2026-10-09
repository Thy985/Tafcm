/// EditorPage 导出动作处理器（Phase 3.4 Slice 7 + 3.7.3）。
///
/// 从 editor_page.dart 抽取，保持单一职责（AGENTS.md §1.2）。
/// 包含文档导出（PDF/DOCX/TXT）与诊断数据导出两个入口。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/providers/export_progress_provider.dart';
import '../../domain/services/export_cancel_token.dart';
import '../../domain/services/export_service.dart';
import '../../providers/editor_providers.dart';
import '../theme/app_theme.dart';
import 'editor_coordinator.dart';

/// 导出动作处理：导出文档 + 导出诊断数据。
///
/// 从 [EditorPage] 抽取的导出逻辑，通过显式 DI（[ref] + [coordinator]）
/// 避免全局单例。调用方在 build / callback 中创建实例并调用。
class EditorExportActions {
  EditorExportActions({
    required this.ref,
    required this.coordinator,
  });

  final WidgetRef ref;
  final EditorCoordinator coordinator;

  /// 导出诊断数据 zip（Phase 3.7.3）。
  ///
  /// 通过 [EditorCoordinator.exportDiagnosticZip] 委托到 [ObservabilityService]，
  /// 结果（zip 路径）通过 SnackBar 展示。
  Future<void> handleExportDiagnostics(BuildContext context) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在导出诊断数据...')),
    );
    final path = await coordinator.exportDiagnosticZip();
    if (!context.mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('诊断数据已导出：$path'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '分享',
            onPressed: () async {
              await Share.shareXFiles(
                [XFile(path)],
                subject: 'Tafcm 诊断数据',
              );
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出诊断数据失败（可观测性未启用）')),
      );
    }
  }

  /// 导出动作入口（Phase 3.4 Slice 7 / 3.4.4 + PR-4 状态机硬化）。
  ///
  /// 流程：[ExportProgressNotifier.runWithGuard] 提供 terminal-state
  /// guarantee —— 无论导出主流程 / 写盘 / 分享任一阶段失败，最终都回到
  /// `ExportIdleState`，避免 SnackBar 永久残留（Bug4）。
  ///
  /// issue #323：协作式取消 —— 用户在确认对话框选择「取消导出并退出」
  /// 后，[ExportProgressNotifier.cancel] 置位令牌；本方法把令牌透传给
  /// 导出管线（阶段边界检查点），并在写临时文件前做最后检查，保证取消
  /// 不产出任何中间文件。[ExportCancelledException] 在此吞掉（取消是
  /// 用户意图，不是失败，也不进 observability）。
  ///
  /// bytes 留在调用方直接写盘 / 分享，不经过 [exportProgressProvider] 状态机传输
  /// （避免 Provider state 序列化 Uint8List 导致内存/所有权混淆）。
  Future<void> handleExport(BuildContext context, ExportFormat format) async {
    final notifier = ref.read(exportProgressProvider.notifier);
    final markdown = coordinator.editor.allSources.join('\n');
    // issue #327：导出文件名（及 PDF 元数据 title / 分享 subject）跟随用户
    // 当前可见的标题块内容，而非加载时从存储层文档名取的 coordinator.title
    // 快照——标题块改为 `qa: export/doc` 后旧值仍是「未命名文档」。
    // 无 H1 标题块时 fallback 到存储层文档名（新文档为「未命名文档」）。
    final title =
        coordinator.editor.titleFromContent ?? coordinator.title;
    final isDark = ref.read(themeModeProvider) == AppThemeMode.dark;

    try {
      // runWithGuard 保证：success → Completed；任意阶段 throw → Failed
      // （自动 classifyError 分类）；取消 → Idle（rethrow，本方法吞掉）；
      // finally 强制 → Idle。
      // observability 由 onError 钩子在 fail 之前记录。
      await notifier.runWithGuard<void>(
        format,
        () async {
          // runWithGuard 已 start（创建令牌），此处读取并透传给管线。
          final ExportCancelToken? cancelToken = notifier.activeCancelToken;
          final Uint8List bytes = switch (format) {
            ExportFormat.pdf => await MarkdownExporter.exportToPdf(
                markdown,
                title: title,
                isDark: isDark,
                onProgress: notifier.report,
                observability: ref.read(observabilityProvider),
                cancelToken: cancelToken,
              ),
            ExportFormat.docx => await MarkdownExporter.exportToWord(
                markdown,
                title: title,
                isDark: isDark,
                onProgress: notifier.report,
                cancelToken: cancelToken,
              ),
            ExportFormat.txt => await MarkdownExporter.exportToTxt(
                markdown,
                onProgress: notifier.report,
                cancelToken: cancelToken,
              ),
          };
          // issue #323：写盘前最后取消检查点——保证取消不产出临时文件。
          cancelToken?.throwIfCancelled();

          final path = await ExportService.writeBytesToTempFile(
            bytes,
            format,
            fileName: title,
          );
          // Bug（真机实测）：shareXFiles 的 Future 在 Android 上可能不 resolve
          // （用户关闭分享面板后 Future 挂起）。若在此 await，runWithGuard 的
          // body 永不返回 → complete() 永不执行 → state 永停 InProgress → 导出
          // 完成但「正在导出 32%」SnackBar 永久残留（duration 1 天）。
          // 写盘成功即视为导出完成，分享是用户交互，不阻塞导出状态机。
          unawaited(
            Share.shareXFiles(
              [XFile(path, mimeType: mimeFor(format))],
              subject: title,
            ).then<void>(
              (_) {},
              onError: (Object e) {
                // 分享失败不影响导出结果，仅记录（onError 兜底在 runWithGuard 层）。
                debugPrint('[EditorExportActions] share failed: $e');
              },
            ),
          );
        },
        onError: (e, st) {
          // 写盘 / share 失败的兜底记录（导出主流程失败也走这里）。
          debugPrint('[EditorExportActions] export failed: $e\n$st');
          ref.read(observabilityProvider).captureError(
                type: 'ExportError',
                message: '$e',
                commandName: 'handleExport',
                commandParams: {'format': format.name},
              );
        },
      );
    } on ExportCancelledException {
      // 用户确认「取消导出并退出」（issue #323）：状态机已由 runWithGuard
      // 归 Idle、浮层随编辑器路由销毁。取消不是错误——不上报 observability，
      // 也不向调用方（fire-and-forget 的 onExportTo 回调）抛未捕获异常。
      debugPrint('[EditorExportActions] export cancelled by user');
    }
  }

  /// [ExportFormat] → MIME，用于 `Share.shareXFiles` 的 XFile 标注。
  static String mimeFor(ExportFormat format) => switch (format) {
        ExportFormat.pdf => 'application/pdf',
        ExportFormat.docx =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ExportFormat.txt => 'text/plain',
      };
}