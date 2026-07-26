/// EditorPage：Phase 3.0 production 路径的顶层编辑器页面（Route 入口）。
///
/// 落地 Phase 3.0 Task Contract §3.2 + §2.5（旧 UI 并存）。
///
/// **职责**：
/// - 创建 [EditorCoordinator]（注入 InMemoryDocumentEditor + EditorHistory）
/// - 通过 [EditorScope] 把 Coordinator 注入到 widget 树
/// - 挂载 [EditorShell]（布局壳）
/// - **Phase 3.4 Slice2（ADR-0013）**：持有并驱动 [AutosaveService]（显式 DI，
///   无全局单例）；save 回调与手动保存共用同一落盘路径
/// - **Phase 3.4 Slice 7 / §3.7**：响应 [EditorAppBar] 的导出 PopupMenu，调用
///   [MarkdownExporter.exportToXxx] 并通过 [exportProgressProvider] 透出进度，
///   完成后调起系统分享
/// - dispose 时释放 Coordinator + 停止 AutosaveService
///
/// **Feature Flag**（§2.5 旧 UI 并存）：
/// - Phase 3.0 期间 `kEnableNewEditor` 默认 false（旧 UI 为主入口）
/// - Phase 3.1 完成后改为 true
/// - Phase 3.17 完成后删除旧 UI 代码
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/editing/editor_history.dart';
import '../../domain/providers/export_progress_provider.dart';
import '../../domain/services/export_service.dart';
import '../../providers/current_path_provider.dart';
import '../../providers/file_repository_provider.dart';
import '../widgets/export_progress_overlay.dart';
import 'autosave_service.dart';
import 'editor_coordinator.dart';
import 'editor_scope.dart';
import 'editor_shell.dart';
import 'in_memory_document_editor.dart';
import 'seed_documents.dart';

/// Phase 3.0 顶层编辑器页面（Route 入口）。
///
/// 通过 [seedSelector] 选择种子文档（0/1/2 对应 demo1/demo2/demo3）。
class EditorPage extends ConsumerStatefulWidget {
  /// 选择种子文档（0 = demo1, 1 = demo2, 2 = demo3）。
  ///
  /// 默认 0。Phase 3.1+ 接入真实 .md 文件时，此参数替换为文件路径。
  final int seedSelector;

  const EditorPage({
    super.key,
    this.seedSelector = 0,
  });

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  late final EditorCoordinator _coordinator;
  AutosaveService? _autosave;

  @override
  void initState() {
    super.initState();
    final editor = _buildSeedEditor(widget.seedSelector);
    final history = EditorHistory(maxHistorySize: 200);
    _coordinator = EditorCoordinator(editor: editor, history: history);

    // ADR-0013：自动保存服务（显式 DI，无全局单例）。
    // source = Coordinator（实现 DirtyStateSource）；save = 落盘回调（仅当存在可写路径）。
    _autosave = AutosaveService(
      source: _coordinator,
      save: _saveDocument,
    );
    _autosave!.start();
  }

  /// 自动保存落盘回调（ADR-0013：与手动保存共用同一路径，幂等）。
  ///
  /// 返回 `true` = 已落盘；`false` = 跳过（无可写路径，避免为未保存 / 演示文档产生
  /// 无主 .md，对齐 [EditorScreen._scheduleAutosave] 行为）。
  ///
  /// 保存快照在 [AutosaveService] 调用本回调的**起始同步**读取（触发时刻快照），
  /// 避免把进行中的实时 live 写盘造成回退。
  ///
  /// 注：当前演示路径（[seedSelector]）不设置 [currentPathProvider]，故自动保存在该路径下
  /// 为 inert（不写盘、不误标已保存）。一旦 EditorPage 接入真实 .md 路径（ADR-0016 / Slice6
  /// 文件树），本回调即生效，E2E「关 App 重开内容一致」随之满足。
  Future<bool> _saveDocument() async {
    final path = ref.read(currentPathProvider);
    if (path == null) return false;
    // 触发时刻快照：在 save 回调**起始同步**读取（避免写盘进行中的实时 live 回退）。
    final snapshot = _coordinator.editor.allSources.join('\n');
    await ref.read(fileRepositoryProvider).writeDocument(
          path,
          title: _coordinator.title,
          content: snapshot,
        );
    // 写盘后：若 source 在此期间无新改动，标记已保存；否则保留 dirty，
    // 由 AutosaveService 重新调度下一次保存（ADR-0013 并发保护：禁止误清进行中的编辑）。
    if (_coordinator.editor.allSources.join('\n') == snapshot) {
      _coordinator.markSaved();
    }
    return true;
  }

  /// 根据 [selector] 构造种子 [InMemoryDocumentEditor]。
  InMemoryDocumentEditor _buildSeedEditor(int selector) {
    switch (selector) {
      case 0:
        return SeedDocuments.createDemo1();
      case 1:
        return SeedDocuments.createDemo2();
      case 2:
        return SeedDocuments.createDemo3();
      default:
        return SeedDocuments.createDemo1();
    }
  }

  /// 导出动作回调（Phase 3.4 Slice 7 / §3.7）。
  ///
  /// 由 [EditorAppBar] 的导出 PopupMenu 选中目标格式时调用。
  ///
  /// 流程：
  ///   1. 验证文档非空 → [exportProgressProvider] 进入 InProgress
  ///   2. 拼装 markdown + title，调用对应 [MarkdownExporter] 方法，
  ///      `onProgress` 把每个阶段的进度推到 provider（per-formula + per-block）
  ///   3. 成功 → `complete(format, bytes)`，由 [ExportProgressOverlay] 显示成功 SnackBar
  ///   4. 成功后调起系统分享（写临时文件 → `Share.shareXFiles`）
  ///   5. 任意阶段异常 → [classifyError] → `fail(format, kind)`；用户消息由
  ///      ExportProgressOverlay 渲染（friendly message，不暴露 stack，
  ///      AGENTS.md §4.4 守门）。
  ///
  /// **唯一持有 ref 的层**（AGENTS.md §6.5 依赖图单向）：
  /// - chrome/blocks 不直接读写 exportProgressProvider；
  /// - 由 EditorPage（ref 持有者）负责 state 推进；
  /// - [ExportProgressOverlay] 仅以 ConsumerWidget 身份 ref.listen 消费。
  Future<void> _handleExport(ExportFormat format) async {
    final notifier = ref.read(exportProgressProvider.notifier);

    // 1. 空文档检查（避免无意义的 export 启动）。
    if (_coordinator.editor.allSources.isEmpty) {
      notifier.fail(format, ExportFailure.emptyDocument);
      return;
    }

    notifier.start(format);

    final markdown = _coordinator.editor.allSources.join('\n');
    final title = _coordinator.title;

    try {
      // 2. 调用 exporter，`onProgress` 桥接到 notifier.report。
      final bytes = switch (format) {
        ExportFormat.pdf => await MarkdownExporter.exportToPdf(
            markdown,
            title: title,
            onProgress: notifier.report,
          ),
        ExportFormat.docx => await MarkdownExporter.exportToWord(
            markdown,
            title: title,
            onProgress: notifier.report,
          ),
        ExportFormat.txt => await MarkdownExporter.exportToTxt(
            markdown,
            onProgress: notifier.report,
          ),
      };

      // 3. 成功：进入 ExportCompletedState。Overlay 显示"已导出 PDF"等。
      notifier.complete(format, bytes);

      // 4. 分享：写临时文件（domain 层 ExportService.writeBytesToTempFile，
      // 符合 TC-ARCH-1/2；本方法在 domain/services 路径，受 allowlist）+ 系统 share sheet。
      final path = await ExportService.writeBytesToTempFile(
        bytes,
        format,
        fileName: title,
      );
      await Share.shareXFiles(
        [XFile(path, mimeType: _mimeFor(format))],
        subject: path.split('/').last,
      );
    } catch (e) {
      // 5. 失败：分类 → ExportFailedState。Overlay 显示分类友好文案。
      final info = classifyError(e);
      notifier.fail(format, info.kind);
    }
  }

  /// MimeType helper（与 file 扩展名配对）。
  static String _mimeFor(ExportFormat format) => switch (format) {
        ExportFormat.pdf => 'application/pdf',
        ExportFormat.docx =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ExportFormat.txt => 'text/plain',
      };

  @override
  void dispose() {
    _autosave?.stop();
    // ADR-0013：释放 DirtyStateTracker 的 StreamController（Level 3 评审 R1）。
    _coordinator.dispose();
    // Phase 3.0：InMemoryDocumentEditor / EditorHistory 持有的是纯内存数据，
    // 无需显式释放。Phase 3.1+ 接入真实 .md 文件时需补充资源清理。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 用 AnimatedBuilder 监听 ChangeNotifier（_coordinator）变化，
    // 当 coordinator.handle / setFocus / clearFocus / undo / redo 调用
    // notifyListeners() 时，触发 EditorShell 重建。
    //
    // 顶层 ExportProgressOverlay（Phase 3.4 Slice 7 / §3.7）监听
    // exportProgressProvider，渲染 SnackBar；保持 chrome/widgets/blocks
    // 各层 Riverpod-free（AGENTS.md §6.5 依赖图单向）。
    return ExportProgressOverlay(
      child: EditorScope(
        coordinator: _coordinator,
        child: AnimatedBuilder(
          animation: _coordinator,
          builder: (context, _) => EditorShell(
            coordinator: _coordinator,
            onExportTo: _handleExport,
          ),
        ),
      ),
    );
  }
}
