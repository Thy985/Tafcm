/// EditorPage 导出动作处理器（Phase 3.4 Slice 7 + 3.7.3）。
///
/// 从 editor_page.dart 抽取，保持单一职责（AGENTS.md §1.2）。
/// 包含文档导出（PDF/DOCX/TXT）与诊断数据导出两个入口。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/providers/export_progress_provider.dart';
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
                subject: 'FormulaFix 诊断数据',
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

  /// 导出动作入口（Phase 3.4 Slice 7 / 3.4.4）。
  ///
  /// 流程：start → 调 MarkdownExporter.exportToXxx 桥接 onProgress → complete
  /// → 写临时文件 + Share.shareXFiles（v7 API）；失败用 classifyError 分类。
  ///
  /// bytes 留在调用方直接写盘 / 分享，不经过 [exportProgressProvider] 状态机传输
  /// （避免 Provider state 序列化 Uint8List 导致内存/所有权混淆）。
  Future<void> handleExport(BuildContext context, ExportFormat format) async {
    final notifier = ref.read(exportProgressProvider.notifier);
    final markdown = coordinator.editor.allSources.join('\n');
    final title = coordinator.title;
    final isDark = ref.read(themeModeProvider) == AppThemeMode.dark;

    notifier.start(format);
    try {
      final Uint8List bytes = switch (format) {
        ExportFormat.pdf => await MarkdownExporter.exportToPdf(
            markdown,
            title: title,
            isDark: isDark,
            onProgress: (p) => notifier.report(p),
            observability: ref.read(observabilityProvider),
          ),
        ExportFormat.docx => await MarkdownExporter.exportToWord(
            markdown,
            title: title,
            isDark: isDark,
            onProgress: (p) => notifier.report(p),
          ),
        ExportFormat.txt => await MarkdownExporter.exportToTxt(
            markdown,
            onProgress: (p) => notifier.report(p),
          ),
      };

      notifier.complete(format);

      final path = await ExportService.writeBytesToTempFile(
        bytes,
        format,
        fileName: title,
      );
      await Share.shareXFiles(
        [XFile(path, mimeType: mimeFor(format))],
        subject: title,
      );
    } catch (e, st) {
      // P2 修复（2026-08-04）：导出失败也送入 observability（captureError）。
      debugPrint('[EditorExportActions] export failed: $e\n$st');
      ref.read(observabilityProvider).captureError(
            type: 'ExportError',
            message: '$e',
            commandName: 'handleExport',
            commandParams: {'format': format.name},
          );
      final info = classifyError(e);
      notifier.fail(format, info.kind);
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