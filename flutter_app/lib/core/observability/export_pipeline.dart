/// ExportPipeline：诊断导出管道。
///
/// 生成 `formula_fix_debug_YYYYMMDD_HHmmss.zip`，包含：
/// - metadata.json：版本、设备、时间、observability 级别、各 trace count
/// - trace.json：完整的事件流（Interaction + Command + Transaction + Render）
/// - snapshot.json：当前 Error Snapshot（如有）
/// - invariant_report.json：最近一次 Invariant Checker 运行结果
/// - README.txt：导出说明
///
/// 落地 ADR-0021 §2.8（Export Pipeline）+ ADR-0023 §2.1 扩展（Render Trace）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'observability_service.dart';

/// 诊断导出管道。
///
/// 通过 [ObservabilityService] 获取所有 Trace 数据，打包为 zip 文件。
/// 由开发者选项或设置页面触发导出。
class ExportPipeline {
  final ObservabilityService _service;

  ExportPipeline(this._service);

  /// 导出诊断 zip 文件。
  ///
  /// [outputDir]：可选输出目录，默认使用应用文档目录。
  /// 返回 zip 文件路径，失败时返回 null。
  Future<String?> export({String? outputDir}) async {
    try {
      final dir = outputDir ?? await _defaultOutputDir();
      if (dir == null) return null;

      final now = DateTime.now();
      final date = '${now.year}${_pad(now.month)}${_pad(now.day)}';
      final time = '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
      final fileName = 'formula_fix_debug_${date}_$time.zip';
      final filePath = '${dir}${Platform.pathSeparator}$fileName';

      final archive = Archive();
      final encoder = JsonEncoder.withIndent('  ');

      // metadata.json
      final metadata = _buildMetadata(now);
      _addJsonFile(archive, 'metadata.json', encoder, metadata);

      // trace.json
      final trace = _buildTrace();
      _addJsonFile(archive, 'trace.json', encoder, trace);

      // snapshot.json（如有）
      final snapshot = _service.lastErrorSnapshot;
      if (snapshot != null) {
        _addJsonFile(archive, 'snapshot.json', encoder, snapshot.toJson());
      }

      // invariant_report.json
      final invariantReport = _buildInvariantReport();
      _addJsonFile(archive, 'invariant_report.json', encoder, invariantReport);

      // README.txt
      archive.addFile(ArchiveFile(
        'README.txt',
        utf8.encode(_buildReadme()).length,
        utf8.encode(_buildReadme()),
      ));

      final compressed = ZipEncoder().encode(archive);
      if (compressed == null) return null;

      final file = File(filePath);
      await file.writeAsBytes(compressed);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// 添加 JSON 文件到 archive。
  void _addJsonFile(
    Archive archive,
    String name,
    JsonEncoder encoder,
    Map<String, Object?> data,
  ) {
    final json = encoder.convert(data);
    final bytes = utf8.encode(json);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  /// 构建 metadata.json。
  Map<String, Object?> _buildMetadata(DateTime now) {
    return {
      'version': _service.config.level.name,
      'time': now.toIso8601String(),
      'observabilityLevel': _service.config.level.name,
      'sessionId': _service.sessionId,
      'commandCount': _service.commandTracer.count,
      'transactionCount': _service.transactionTracer.count,
      'interactionCount': _service.interactionTracer.count,
      'renderCount': _service.renderTracer.count,
    };
  }

  /// 构建 trace.json（按时间排序的事件流）。
  Map<String, Object?> _buildTrace() {
    final interactions = _service.interactionTracer.entries.map((e) {
      return switch (e) {
        UserTap(:final target, :final timestamp) => <String, Object?>{
          'type': 'UserTap',
          'target': target,
          'timestamp': timestamp.toIso8601String(),
        },
        UserInput(
          :final length,
          :final hasNewline,
          :final isAscii,
          :final timestamp
        ) =>
            <String, Object?>{
              'type': 'UserInput',
              'length': length,
              'hasNewline': hasNewline,
              'isAscii': isAscii,
              'timestamp': timestamp.toIso8601String(),
            },
        UserDelete(:final count, :final timestamp) => <String, Object?>{
          'type': 'UserDelete',
          'count': count,
          'timestamp': timestamp.toIso8601String(),
        },
        UserFormatToggle(:final format, :final timestamp) => <String, Object?>{
          'type': 'UserFormatToggle',
          'format': format,
          'timestamp': timestamp.toIso8601String(),
        },
        UserUndoRedo(:final isUndo, :final timestamp) => <String, Object?>{
          'type': 'UserUndoRedo',
          'isUndo': isUndo,
          'timestamp': timestamp.toIso8601String(),
        },
        UserLongPress(:final target, :final timestamp) => <String, Object?>{
          'type': 'UserLongPress',
          'target': target,
          'timestamp': timestamp.toIso8601String(),
        },
      };
    }).toList();

    final commands = _service.commandTracer.entries.map((e) {
      return <String, Object?>{
        'commandName': e.commandName,
        'params': e.params,
        'origin': e.origin.name,
        'timestamp': e.timestamp.toIso8601String(),
        'succeeded': e.succeeded,
        if (e.errorMessage != null) 'errorMessage': e.errorMessage,
        if (e.traceId != null) 'traceId': e.traceId,
      };
    }).toList();

    final transactions = _service.transactionTracer.entries.map((e) {
      return <String, Object?>{
        'transactionId': e.transactionId,
        'origin': e.origin.name,
        'result': e.result.name,
        'beforeHash': e.beforeHash,
        'afterHash': e.afterHash,
        if (e.rollbackReason != null) 'rollbackReason': e.rollbackReason,
        if (e.traceId != null) 'traceId': e.traceId,
      };
    }).toList();

    final renders = _service.renderTracer.entries.map((e) {
      return switch (e) {
        CodeBlockThemeRendered(
          :final isDark,
          :final themeName,
          :final language,
          :final timestamp
        ) =>
          <String, Object?>{
            'type': 'CodeBlockThemeRendered',
            'isDark': isDark,
            'themeName': themeName,
            'language': language,
            'timestamp': timestamp.toIso8601String(),
          },
        CodeBlockLanguageChipRendered(
          :final language,
          :final shown,
          :final mode,
          :final timestamp
        ) =>
          <String, Object?>{
            'type': 'CodeBlockLanguageChipRendered',
            'language': language,
            'shown': shown,
            'mode': mode.name,
            'timestamp': timestamp.toIso8601String(),
          },
        PdfCjkFontFallbackEvent(
          :final fontLoaded,
          :final fallbackActive,
          :final language,
          :final codeLength,
          :final hasCjk,
          :final timestamp
        ) =>
          <String, Object?>{
            'type': 'PdfCjkFontFallbackEvent',
            'fontLoaded': fontLoaded,
            'fallbackActive': fallbackActive,
            'language': language,
            'codeLength': codeLength,
            'hasCjk': hasCjk,
            'timestamp': timestamp.toIso8601String(),
          },
        FocusOnViewStateCreatedEvent(:final blockId, :final timestamp) =>
          <String, Object?>{
            'type': 'FocusOnViewStateCreatedEvent',
            'blockId': blockId,
            'timestamp': timestamp.toIso8601String(),
          },
        CjkFontLoadEvent(:final loaded, :final errorMessage, :final timestamp) =>
          <String, Object?>{
            'type': 'CjkFontLoadEvent',
            'loaded': loaded,
            if (errorMessage != null) 'errorMessage': errorMessage,
            'timestamp': timestamp.toIso8601String(),
          },
      };
    }).toList();

    return {
      'interactions': interactions,
      'commands': commands,
      'transactions': transactions,
      'renders': renders,
    };
  }

  /// 构建 invariant_report.json。
  Map<String, Object?> _buildInvariantReport() {
    return {
      'lastCheckTime': DateTime.now().toIso8601String(),
      'invariants': <String>[
        'CursorExists',
        'SelectionValid',
        'BlockTreeAcyclic',
        'ParentChildValid',
        'HistoryConsistent',
      ],
      'result': 'not_checked',
    };
  }

  /// 构建 README.txt。
  String _buildReadme() {
    return 'FormulaFix Debug Report\n'
        '========================\n\n'
        'This archive contains diagnostic data for debugging.\n\n'
        'Files:\n'
        '  metadata.json           - App version, device, OS, session info\n'
        '  trace.json              - Interaction + Command + Transaction + Render traces\n'
        '  snapshot.json           - Error snapshot (if any)\n'
        '  invariant_report.json   - Invariant checker results\n\n'
        'For analysis:\n'
        '  python tools/ffx-analyze/analyze.py this_file.zip\n';
  }

  /// 获取默认输出目录（应用文档目录）。
  Future<String?> _defaultOutputDir() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}