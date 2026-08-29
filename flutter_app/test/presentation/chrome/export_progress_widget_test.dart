/// Slice 7 / 3.4.4 导出进度 — widget 测试。
///
/// 覆盖（Phase 3.4 Task Contract v1.2 §4.1）：
///   - EditorAppBar 导出 PopupMenu：onExportTo 注入时显示，null 时不渲染
///   - ExportProgressOverlay widget：监听 [exportProgressProvider] 渲染 SnackBar
///
/// 数据层 / 状态机 / facade 透传测试在 `export_progress_test.dart`（同目录），
/// 拆分以保证每个测试文件 ≤ 400 行（TC-ARCH-7）。
///
/// 测试 hermetic 化：
///   - EditorAppBar widget 测试仅用 raw EditorCoordinator，不触达磁盘
///   - ExportProgressOverlay 用 addPostFrameCallback 调度 state 变化，绕过
///     Riverpod `ref.listen` 不在初始值时触发的语义
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/domain/providers/export_progress_provider.dart';
import 'package:tafcm/domain/services/export_service.dart';
import 'package:tafcm/presentation/chrome/editor_app_bar.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/widgets/export_progress_overlay.dart';

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

/// 通用 pump 助手：先挂 widget，然后在第一个 postFrame 回调里执行 [seed]
/// 修改 provider 状态，绕过 ref.listen 不在初始值时触发的语义。
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
  await tester.pump();
  await tester.pump();
}

void main() {
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

    testWidgets('选中格式后 onExportTo 收到对应 ExportFormat',
        (tester) async {
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
      // 先 start 让 Overlay 显示 SnackBar，之后 reset() → Overlay 收 Idle，预期隐藏。
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

      container.read(exportProgressProvider.notifier).reset();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('包裹子树不被改变样式注入', (tester) async {
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
