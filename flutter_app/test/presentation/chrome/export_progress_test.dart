/// Slice 7 / 3.4.4 导出进度反馈测试（Phase 3.4 Task Contract v1.2 §4.1）。
///
/// 覆盖：
///   - ExportProgress 数据层：fraction / toString
///   - ExportProgressNotifier 状态机：start → report → complete / fail → reset
///   - ExportProgressOverlay widget：监听 [exportProgressProvider] 渲染 SnackBar
///   - EditorAppBar 导出 PopupMenu：onExportTo 注入时显示，null 时不渲染
///   - MarkdownExporter facade 透传 onProgress（via MarkdownExporter.register 注入 fake）
///
/// 测试 hermetic 化：
///   - EditorAppBar widget 测试仅用 raw EditorCoordinator，不触达磁盘
///   - MarkdownExporter 透传测试用 MarkdownExporter.register 注入 fake exporter，
///     addTearDown 自动恢复（避免 §6.1 全局静态状态泄漏）
///   - ExportProgressOverlay 测试不实际导出（fake MarkdownExporter），仅观察状态机
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/domain/providers/export_progress_provider.dart';
import 'package:formula_fix/domain/services/export_service.dart';
import 'package:formula_fix/presentation/chrome/editor_app_bar.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/widgets/export_progress_overlay.dart';

/// 假 PDF exporter：仅发出预定 onProgress 序列并返回最小字节（验证
/// MarkdownExporter 透传 onProgress 给下游实现）。
class _ProgressPdfExporter implements PdfExporterInterface {
  final List<ExportProgress> emittedProgress;
  _ProgressPdfExporter(this.emittedProgress);

  @override
  Future<Uint8List> export(
    String markdown, {
    String? title,
    String? author,
    bool isDark = false,
    ExportProgressCallback? onProgress,
  }) async {
    // 模拟至少 3 次回调：collecting → preRender → rendering → assembling（0/1 → 1/1）。
    onProgress?.call(const ExportProgress(
      stage: ExportStage.collectingFormulas,
      completed: 0,
      total: 1,
    ));
    onProgress?.call(const ExportProgress(
      stage: ExportStage.preRenderingFormulaSvg,
      completed: 5,
      total: 10,
    ));
    onProgress?.call(const ExportProgress(
      stage: ExportStage.renderingBlocks,
      completed: 7,
      total: 10,
    ));
    emittedProgress.addAll(<ExportProgress>[
      const ExportProgress(
        stage: ExportStage.collectingFormulas,
        completed: 0,
        total: 1,
      ),
      const ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 5,
        total: 10,
      ),
      const ExportProgress(
        stage: ExportStage.renderingBlocks,
        completed: 7,
        total: 10,
      ),
    ]);
    return Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
  }
}

/// 空 editor coordinator（in-memory，无 seed doc），用于 EditorAppBar widget 测试。
EditorCoordinator _emptyCoordinator() {
  return EditorCoordinator(
    editor: InMemoryDocumentEditor(),
    history: EditorHistory(maxHistorySize: 200),
  );
}

/// 包装在 Scaffold + MaterialApp 内的 pumpWidget 助手（Overlay 需 ScaffoldMessenger 上下文）。
Future<void> _pumpWithOverlay(
  WidgetTester tester,
  Widget child,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    ),
  );
}

void main() {
  group('3.4.4 ExportProgress 数据层', () {
    test('fraction：0/1 = 0.0', () {
      const p = ExportProgress(
        stage: ExportStage.collectingFormulas,
        completed: 0,
        total: 1,
      );
      expect(p.fraction, 0.0);
    });

    test('fraction：total==0 返回 0.0（防御除零）', () {
      const p = ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 0,
        total: 0,
      );
      expect(p.fraction, 0.0);
    });

    test('fraction：5/10 = 0.5', () {
      const p = ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 5,
        total: 10,
      );
      expect(p.fraction, 0.5);
    });

    test('fraction：10/10 = 1.0', () {
      const p = ExportProgress(
        stage: ExportStage.renderingBlocks,
        completed: 10,
        total: 10,
      );
      expect(p.fraction, 1.0);
    });

    test('toString 含阶段名与百分比', () {
      const p = ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 3,
        total: 4,
      );
      expect(p.toString(), contains('preRenderingFormulaSvg'));
      expect(p.toString(), contains('3/4'));
      expect(p.toString(), contains('75.0%'));
    });
  });

  group('3.4.4 ExportProgressNotifier 状态机', () {
    late ProviderContainer container;
    late ExportProgressNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(exportProgressProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('初始 = ExportIdleState', () {
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
    });

    test('start(format) → ExportInProgressState 含 format 与初始进度', () {
      notifier.start(ExportFormat.pdf);
      final state = container.read(exportProgressProvider);
      expect(state, isA<ExportInProgressState>());
      final inProgress = state as ExportInProgressState;
      expect(inProgress.format, ExportFormat.pdf);
      expect(inProgress.progress.stage, ExportStage.collectingFormulas);
    });

    test('report 在 InProgress 期间推进 stage 与 fraction', () {
      notifier.start(ExportFormat.pdf);
      notifier.report(const ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 5,
        total: 10,
      ));
      final state = container.read(exportProgressProvider) as ExportInProgressState;
      expect(state.progress.stage, ExportStage.preRenderingFormulaSvg);
      expect(state.progress.fraction, 0.5);
    });

    test('report 在 Idle 状态被忽略（防御状态不一致）', () {
      // notifier 未 start，直接 report。
      notifier.report(const ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 5,
        total: 10,
      ));
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
    });

    test('complete(format, bytes) → ExportCompletedState 含 bytes', () {
      notifier.start(ExportFormat.docx);
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      notifier.complete(ExportFormat.docx, bytes);
      final state = container.read(exportProgressProvider);
      expect(state, isA<ExportCompletedState>());
      expect((state as ExportCompletedState).bytes, bytes);
    });

    test('fail(format, kind) → ExportFailedState 含 kind', () {
      notifier.start(ExportFormat.txt);
      notifier.fail(ExportFormat.txt, ExportFailure.renderError);
      final state = container.read(exportProgressProvider);
      expect(state, isA<ExportFailedState>());
      expect((state as ExportFailedState).failure, ExportFailure.renderError);
    });

    test('reset() → ExportIdleState（无论之前状态）', () {
      notifier.start(ExportFormat.pdf);
      notifier.reset();
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
    });
  });

  group('3.4.4 MarkdownExporter facade 透传 onProgress', () {
    late _ProgressPdfExporter fake;
    late List<ExportProgress> emitted;
    late void Function() disposeFake;

    setUp(() {
      emitted = <ExportProgress>[];
      fake = _ProgressPdfExporter(emitted);
      disposeFake = MarkdownExporter.register(pdf: fake);
    });

    tearDown(() {
      disposeFake();
    });

    test('exportToPdf 调用 onProgress 三次（收集→预渲染→渲染）', () async {
      final received = <ExportProgress>[];
      final bytes = await MarkdownExporter.exportToPdf(
        '# 标题\n\n正文',
        onProgress: received.add,
      );
      expect(bytes.isNotEmpty, true);
      expect(received.length, 3);
      expect(received[0].stage, ExportStage.collectingFormulas);
      expect(received[1].stage, ExportStage.preRenderingFormulaSvg);
      expect(received[2].stage, ExportStage.renderingBlocks);
    });

    test('不传 onProgress：仍正常工作（向后兼容）', () async {
      // 无回调时不抛错——确认注册 fake 不会因缺回调破坏旧路径。
      final bytes = await MarkdownExporter.exportToPdf('# hello');
      expect(bytes.isNotEmpty, true);
    });
  });

  group('3.4.4 EditorAppBar 导出 PopupMenu', () {
    testWidgets('注入 onExportTo 时显示 ios_share 按钮 + 3 格式项',
        (tester) async {
      final coordinator = _emptyCoordinator();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: EditorAppBar(
              coordinator: coordinator,
              onExportTo: (_) {},
            ),
          ),
        ),
      );

      expect(find.byTooltip('导出'), findsOneWidget);

      // 打开 PopupMenu → 看到 3 个格式项
      await tester.tap(find.byTooltip('导出'));
      await tester.pumpAndSettle();
      expect(find.text('导出为 PDF'), findsOneWidget);
      expect(find.text('导出为 Word（.docx）'), findsOneWidget);
      expect(find.text('导出为 TXT'), findsOneWidget);
    });

    testWidgets('onExportTo == null 时不渲染导出按钮', (tester) async {
      final coordinator = _emptyCoordinator();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: EditorAppBar(coordinator: coordinator),
          ),
        ),
      );
      expect(find.byTooltip('导出'), findsNothing);
    });

    testWidgets('选中格式后 onExportTo 收到对应 ExportFormat', (tester) async {
      final coordinator = _emptyCoordinator();
      ExportFormat? received;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: EditorAppBar(
              coordinator: coordinator,
              onExportTo: (fmt) => received = fmt,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('导出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出为 Word（.docx）'));
      await tester.pumpAndSettle();
      expect(received, ExportFormat.docx);
    });
  });

  group('3.4.4 ExportProgressOverlay SnackBar 渲染', () {
    /// 通用的 Pump 助手：先挂 widget，然后在第一个 postFrame 回调里执行 [seed]
    /// 修改 provider 状态，绕过 ref.listen 不在初始值时触发的语义。
    ///
    /// Riverpod 行为：`ref.listen(listener)` 仅在后续状态变化时调用，
    /// 不会在初次注册时调用。如果在 pumpWidget 前就改 state，listener 不会被
    /// 触发，Overlay 看不到任何 SnackBar —— 这正是失败用例的根因。
    Future<void> pumpOverlayWithSeed(
      WidgetTester tester,
      void Function(ProviderContainer container) seed,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    seed(container);
                  });
                  return const ExportProgressOverlay(
                    child: Text('anchor'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      // Frame 1：widget 挂载 + ref.listen 注册 + addPostFrame 入队
      await tester.pump();
      // Frame 2：addPostFrame 执行 → state 变化 → listener 触发 → SnackBar 出现
      await tester.pump();
    }

    testWidgets('InProgress → SnackBar 含 LinearProgressIndicator',
        (tester) async {
      await pumpOverlayWithSeed(tester, (container) {
        final n = container.read(exportProgressProvider.notifier);
        n.start(ExportFormat.pdf);
        n.report(const ExportProgress(
          stage: ExportStage.preRenderingFormulaSvg,
          completed: 5,
          total: 10,
        ));
      });

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('正在导出'), findsOneWidget);
      expect(find.textContaining('5/10'), findsOneWidget);
    });

    testWidgets('Completed → SnackBar 含"已导出"文案', (tester) async {
      await pumpOverlayWithSeed(tester, (container) {
        container.read(exportProgressProvider.notifier).complete(
          ExportFormat.pdf,
          Uint8List.fromList(<int>[1, 2, 3]),
        );
      });

      expect(find.textContaining('已导出'), findsOneWidget);
    });

    testWidgets('Failed → SnackBar 含友好错误文案', (tester) async {
      await pumpOverlayWithSeed(tester, (container) {
        container.read(exportProgressProvider.notifier).fail(
          ExportFormat.docx,
          ExportFailure.renderError,
        );
      });

      expect(find.textContaining('渲染失败'), findsOneWidget);
    });

    testWidgets('Idle → 任何残留 SnackBar 被清除', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 先 start 让 Overlay 显示 SnackBar，之后 reset() → Overlay 收 Idle，预期隐藏。
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    container.read(exportProgressProvider.notifier).start(ExportFormat.pdf);
                  });
                  return const ExportProgressOverlay(child: Text('anchor'));
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);

      // reset → Overlay 进入 Idle → hideCurrent + 不显示新 SnackBar
      container.read(exportProgressProvider.notifier).reset();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('包裹子树不被改变样式注入', (tester) async {
      // ExportProgressOverlay 必须透明地包住 child（不引入额外 Scaffold / Theme 副作用）。
      await _pumpWithOverlay(
        tester,
        const ExportProgressOverlay(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text('child-anchor'),
          ),
        ),
      );
      expect(find.text('child-anchor'), findsOneWidget);
    });
  });
}
