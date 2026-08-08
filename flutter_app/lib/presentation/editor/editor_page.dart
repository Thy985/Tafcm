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
/// - dispose 时释放 Coordinator + 停止 AutosaveService
///
/// **Feature Flag**（§2.5 旧 UI 并存）：
/// - Phase 3.0 期间 `kEnableNewEditor` 默认 false（旧 UI 为主入口）
/// - Phase 3.1 完成后改为 true
/// - Phase 3.17 完成后删除旧 UI 代码
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/editing/editor_history.dart';
import '../../core/parser/markdown_parser.dart';
import '../../data/models/document.dart';

import '../../providers/asset_provider.dart';
import '../../providers/current_path_provider.dart';
import '../../providers/editor_providers.dart';
import '../../providers/external_file_service_provider.dart';
import '../../providers/file_repository_provider.dart';
import '../../providers/last_opened_path_provider.dart';
import '../widgets/export_progress_overlay.dart';
import 'autosave_service.dart';
import 'editor_coordinator.dart';
import 'editor_export_actions.dart';
import 'editor_load_helpers.dart';
import 'editor_scope.dart';
import 'editor_shell.dart';
import 'in_memory_document_editor.dart';
import 'seed_documents.dart';

/// Phase 3.0 顶层编辑器页面（Route 入口）。
///
/// - [externalUri]：外部应用（微信/QQ/浏览器等）通过 ACTION_VIEW 传来的 URI
///   （content:// 或 file://）。优先级最高，非空时通过 [ExternalFileService]
///   读取字节流加载。**不设置 [currentPathProvider]**——外部 URI 不可写，
///   自动保存回退为 inert（不写盘）。
/// - [filePath]：打开的真实 .md 文件路径（Phase 3.4.2 文件树）。非空时加载该文件；
///   为空时回退 [seedSelector] 演示文档。
/// - [seedSelector]：种子文档（0 = demo1, 1 = demo2, 2 = demo3），仅当 [filePath]
///   为 null 且 [externalUri] 为 null 时生效。
class EditorPage extends ConsumerStatefulWidget {
  /// 外部应用通过 ACTION_VIEW 传来的 URI（content:// 或 file://）。null = 非外部入口。
  final String? externalUri;

  /// 打开的真实 .md 文件路径（文件树 / 重启恢复传入）。null = 演示文档。
  final String? filePath;

  /// 选择种子文档（0 = demo1, 1 = demo2, 2 = demo3）。
  final int seedSelector;

  const EditorPage({
    super.key,
    this.externalUri,
    this.filePath,
    this.seedSelector = 0,
  });

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  late final EditorCoordinator _coordinator;
  AutosaveService? _autosave;

  EditorExportActions get _exportActions => EditorExportActions(
        ref: ref,
        coordinator: _coordinator,
      );

  /// 文档是否就绪（文件异步加载完成前显示加载态）。
  bool _ready = false;

  /// [_coordinator] 是否已初始化（异步加载完成前可能尚未赋值，dispose 时需守卫，
  /// 避免 LateInitializationError：用户在加载完成前导航离开）。
  bool _coordinatorReady = false;

  @override
  void initState() {
    super.initState();
    // 优先级：externalUri > filePath > seedSelector。
    // externalUri（外部应用打开）和 filePath（文件树）不能并存。
    if (widget.externalUri != null) {
      // P0 修复（2026-08-04）：外部应用通过 ACTION_VIEW 打开 .md 文件。
      // 通过 MethodChannel 反向调用 MainActivity.readUriBytes 读取字节流，
      // 用 decodeBytesAuto 解码（兼容 GBK / UTF-8 BOM），再走正常解析流程。
      _loadFromExternalUri(widget.externalUri!);
    } else if (widget.filePath != null) {
      // Phase 3.4.2：接入真实 .md 路径（ADR-0016 / Slice6），激活自动保存落盘。
      _loadFromFile(widget.filePath!);
    } else {
      _initSeed(widget.seedSelector);
      _ready = true;
    }
  }

  /// 构造种子 [InMemoryDocumentEditor] 并启动自动保存（演示 / 回退路径）。
  void _initSeed(int selector) {
    final editor = _buildSeedEditor(selector);
    final history = EditorHistory(maxHistorySize: 200);
    _coordinator = EditorCoordinator(
      editor: editor,
      history: history,
      observability: ref.read(observabilityProvider),
    );
    _coordinatorReady = true;
    _startAutosave();
  }

  /// 异步加载真实 .md 文件（Phase 3.4.2）。
  ///
  /// 经 [DocumentRepository.readDocument] 读取 → [MarkdownParser.parse] 解析为块 →
  /// 构造 [InMemoryDocumentEditor]。失败则回退种子文档（不阻断编辑器）。
  ///
  /// P1 修复（2026-08-04, B-4）：原实现 `catch (_) { _initSeed(...); }` 静默
  /// 吞掉所有异常（FileNotFound / 权限拒绝 / GBK 解码失败 / 解析崩溃），用户
  /// 看到的是"打开后变成演示文档"，完全不知发生了什么。修复后：
  /// - 错误进 observability（captureError，含 path / error 类型）
  /// - SnackBar 向用户反馈"无法打开文件 X，已加载演示文档"
  Future<void> _loadFromFile(String path) async {
    try {
      final repo = ref.read(fileRepositoryProvider);
      final doc = await repo.readDocument(path);
      // 当前路径需在首帧之后写入 provider（Riverpod 禁止在 build/initState 同步改 provider）。
      ref.read(currentPathProvider.notifier).state = path;
      final elements = MarkdownParser.parse(doc.content);
      final editor = InMemoryDocumentEditor(title: doc.title);
      for (final element in elements) {
        // EmptyLineElement 是 MarkdownParser 产出的「块分隔符」（空行辅助），
        // 不是可编辑块。BlockRenderer / LiveEditingState.wordCount 均不支持它，
        // 若插入会导致打开含空行的 .md 直接崩溃（见 BlockRenderer.build 注释
        // "EmptyLineElement 不应到达此处"）。加载时直接跳过分隔符。
        if (element is EmptyLineElement) continue;
        editor.insertBlock(editor.blockCount, element);
      }
      _coordinator = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 200),
        observability: ref.read(observabilityProvider),
      );
      _coordinatorReady = true;
      _startAutosave();
    } catch (e, st) {
      // P1 B-4：用户打开文件失败不再静默。
      debugPrint('[EditorPage] _loadFromFile failed: $e\n$st');
      ref.read(observabilityProvider).captureError(
            type: 'FileLoadError',
            message: '$e',
            commandName: '_loadFromFile',
            commandParams: {'path': path},
          );
      _initSeed(widget.seedSelector);
      if (!mounted) return;
      showFileLoadFailureSnackBar(context, path: path, error: e);
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }


  /// 异步加载外部 URI 指向的 .md 文件（P0 修复 2026-08-04）。
  ///
  /// 流程：[ExternalFileService.readContent] 通过 MethodChannel 反向调用
  /// [MainActivity.readUriBytes] 读取字节流 → [decodeBytesAuto] 解码（兼容
  /// GBK / UTF-8 BOM）→ [MarkdownParser.parse] 解析 → 构造
  /// [InMemoryDocumentEditor]。
  ///
  /// **不设置 [currentPathProvider]**：外部 URI（content://）不可写，
  /// 自动保存 [_saveDocument] 检测到 path == null 会返回 false（inert），
  /// 避免向不可写的 URI 写盘导致崩溃。
  ///
  /// P1 修复（2026-08-04, B-4）：原 `catch (_) { _initSeed(...); }` 静默吞掉
  /// MethodChannel 失败 / ContentResolver 读取失败 / 解析崩溃等。修复后：
  /// - 错误进 observability（captureError，含 uri / error 类型）
  /// - SnackBar 向用户反馈"无法打开外部文件，已加载演示文档"
  Future<void> _loadFromExternalUri(String uri) async {
    try {
      final content = await ref.read(externalFileServiceProvider).readContent(uri);
      // 从 URI 推导标题：取最后一段路径，去掉扩展名。失败兜底"未命名文档"。
      String title = '未命名文档';
      try {
        final decoded = Uri.decodeFull(uri);
        final lastSegment = decoded.split('/').last;
        if (lastSegment.isNotEmpty) {
          // 去掉 query string（content:// URI 可能带 ?xxx=yyy）
          final name = lastSegment.split('?').first;
          final dotIndex = name.lastIndexOf('.');
          title = dotIndex > 0 ? name.substring(0, dotIndex) : name;
        }
      } catch (e) {
        // P1 B-4：标题推导是 best-effort，不影响主流程，仅记录日志。
        debugPrint('[EditorPage] title derivation failed: $e');
      }
      final elements = MarkdownParser.parse(
        content,
        onError: buildParserErrorHandler(ref, uri),
      );
      final editor = InMemoryDocumentEditor(title: title);
      for (final element in elements) {
        if (element is EmptyLineElement) continue;
        editor.insertBlock(editor.blockCount, element);
      }
      _coordinator = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 200),
        observability: ref.read(observabilityProvider),
      );
      _coordinatorReady = true;
      _startAutosave();
    } catch (e, st) {
      // P1 B-4：外部 URI 加载失败不再静默。
      debugPrint('[EditorPage] _loadFromExternalUri failed: $e\n$st');
      ref.read(observabilityProvider).captureError(
            type: 'ExternalUriLoadError',
            message: '$e',
            commandName: '_loadFromExternalUri',
            commandParams: {'uri': uri},
          );
      _initSeed(widget.seedSelector);
      if (!mounted) return;
      showFileLoadFailureSnackBar(context, path: null, error: e);
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  /// 启动自动保存（ADR-0013：显式 DI，无全局单例）。
  ///
  /// P2 修复（2026-08-04）：注入 onError 回调，把磁盘满 / 权限拒绝 /
  /// 文件锁定等持久化失败送入 observability（captureError）。
  void _startAutosave() {
    _autosave = AutosaveService(
      source: _coordinator,
      save: _saveDocument,
      onError: (error, stack) {
        debugPrint('[EditorPage] autosave failed: $error\n$stack');
        ref.read(observabilityProvider).captureError(
              type: 'AutosaveError',
              message: '$error',
              commandName: '_saveDocument',
            );
      },
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
  ///
  /// P2 修复（2026-08-04, B-3）：明确区分两种"未落盘"情况：
  /// - **path == null**（演示文档 / 无主 .md）：**正常行为**，return false，
  ///   AutosaveService 进入 idle 不重试，**不进 observability**（避免噪音）。
  ///   仅在 dirty 时 debugPrint 提示"无路径跳过保存"，便于调试。
  /// - **writeDocument 异常**（磁盘满 / 权限 / 文件锁）：异常冒泡到
  ///   AutosaveService._saveOnce catch → onError 回调 → captureError，
  ///   进入 observability 作为 `AutosaveError`，并触发指数退避重试。
  Future<bool> _saveDocument() async {
    final path = ref.read(currentPathProvider);
    if (path == null) {
      // P2 B-3：演示文档 / 无主 .md 路径——正常跳过，不报错。
      // 仅在 dirty 时 debugPrint，便于调试"为什么没保存"。
      if (_coordinator.isDirty) {
        debugPrint('[EditorPage] autosave skipped: no path (demo document)');
      }
      return false;
    }
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

  @override
  void dispose() {
    _autosave?.stop();
    // ADR-0013：释放 DirtyStateTracker 的 StreamController（Level 3 评审 R1）。
    // [_coordinator] 可能尚未初始化（异步加载完成前已 dispose），需守卫避免
    // LateInitializationError。
    if (_coordinatorReady) _coordinator.dispose();
    // Phase 3.0：InMemoryDocumentEditor / EditorHistory 持有的是纯内存数据，
    // 无需显式释放。Phase 3.1+ 接入真实 .md 文件时需补充资源清理。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // 用 AnimatedBuilder 监听 ChangeNotifier（_coordinator）变化，
    // 当 coordinator.handle / setFocus / clearFocus / undo / redo 调用
    // notifyListeners() 时，触发 EditorShell 重建。
    final currentPath = ref.watch(currentPathProvider);
    // Phase 3.4.3 / ADR-0015：主题模式从 provider 读取，透传给 EditorShell → EditorAppBar。
    // chrome/ 保持 Riverpod-free，主题状态在此（唯一持 ref 的层）解析后向下传递。
    // 主题切换会由 main.dart（watch themeModeProvider）触发整个 MaterialApp 重建，
    // 故此处 watch 拿到的 mode 始终最新，切换按钮图标随之更新。
    final mode = ref.watch(themeModeProvider);
    // ADR-0014：文档存储基目录用于解析相对资源路径（assets/img_xxx.png）。
    // 由持有 ref 的页面层解析后透传，保持 chrome / blocks 层 Riverpod-free。
    final baseDir = ref.watch(docsDirProvider).value;
    return ExportProgressOverlay(
      child: EditorScope(
        coordinator: _coordinator,
        child: AnimatedBuilder(
          animation: _coordinator,
          builder: (context, _) => EditorShell(
            coordinator: _coordinator,
            currentPath: currentPath,
            onOpenFile: _openFile,
            themeMode: mode,
            onCycleTheme: () => ref.read(themeModeProvider.notifier).cycle(),
            baseDir: baseDir,
            // ADR-0014 + TC-ARCH-3：图片选择函数由 provider 注入，
            // chrome 层不直接 import core/services。
            pickImage: ref.read(imagePickAndImportProvider),
            // Phase 3.4 Slice 7 / 3.4.4：导出动作回调，AppBar 导出 PopupMenu 选中触发。
            onExportTo: (format) => _exportActions.handleExport(context, format),
            // Phase 3.7.3：诊断数据导出，AppBar more_vert 菜单触发。
            onExportDiagnostics: () => _exportActions.handleExportDiagnostics(context),
          ),
        ),
      ),
    );
  }


  /// 文件树点击：记忆"上次打开文件"路径（契约链3 强制"打开文件一致"），
  /// 并导航到该文件。用 [context.pushReplacement] 替换栈顶 /editor，保留下方 /home 或 /files
  /// 作为返回页（P1 修复 2026-08-06，phase3.5-realdevice-issues 问题 2）。
  /// 原 `context.go` 会替换整个栈，导致编辑器返回按钮无页可 pop。
  void _openFile(String path) {
    ref.read(lastOpenedPathProvider.notifier).set(path);
    context.pushReplacement('/editor?path=${Uri.encodeComponent(path)}');
  }
}
