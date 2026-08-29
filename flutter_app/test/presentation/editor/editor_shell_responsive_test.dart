/// P1-1 响应式断点体系回归测试（UI_FIX_PLAN）。
///
/// 锁定两种关键响应式行为，避免日后回归：
/// 1. 宽屏(≥600)：点击「文件树」→ 侧栏以 [SizedBox(width:260)] 内联出现（编辑器被挤占但结构不变）。
/// 2. 窄屏(<600，如 375)：点击「文件树」→ 侧栏退化为 endDrawer 覆盖层（不再内联 260 挤占编辑区），
///    且无 RenderFlex 溢出。
/// 3. [FormulaInsertDialog]：窄屏宽度不超过屏宽 90%，宽屏保持 480。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_shell.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/panels/file_tree_panel.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/presentation/widgets/formula_insert_dialog.dart';
import 'package:tafcm/providers/file_repository_provider.dart';

/// 测试用 `InAppWebViewPlatform` 桩：返回空 Widget，避免单元测试初始化平台 WebView。
class _FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return _NoopPlatformInAppWebViewWidget(params);
  }
}

class _NoopPlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _NoopPlatformInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    throw UnimplementedError('NoopPlatformInAppWebViewWidget.controllerFromPlatform');
  }

  @override
  void dispose() {}
}

/// 返回固定文档列表的仓储桩，用于驱动 [FileTreePanel] 渲染。
class _FixedListFileRepository extends FileRepository {
  final List<Document> _docs;
  _FixedListFileRepository(this._docs);

  @override
  Future<List<Document>> listDocuments() async => _docs;
}

/// 在指定逻辑尺寸下挂载 [EditorShell]，注入文档列表，返回构建好的 tester 环境。
Future<void> _pumpShell(WidgetTester tester, Size size, List<Document> docs) async {
  final coordinator = EditorCoordinator(
    editor: InMemoryDocumentEditor(title: 'Responsive'),
    history: EditorHistory(maxHistorySize: 200),
  );
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: ProviderScope(
        overrides: [
          fileRepositoryProvider.overrideWithValue(_FixedListFileRepository(docs)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: EditorScope(
            coordinator: coordinator,
            child: EditorShell(coordinator: coordinator),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  final docs = <Document>[
    Document(
      id: 'aaa',
      title: 'Doc A',
      content: '# A',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    ),
    Document(
      id: 'bbb',
      title: 'Doc B',
      content: '# B',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 3),
    ),
  ];

  group('P1-1 响应式断点', () {
    /// 宽屏：文件树内联 SizedBox(width:260)，结构不变。
    testWidgets('宽屏(800) 文件树内联 SizedBox(260)', (tester) async {
      await _pumpShell(tester, const Size(800, 1200), docs);

      // 初始隐藏。
      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 260.0),
        findsNothing,
      );

      // 点击「文件树」→ 内联侧栏出现。
      await tester.tap(find.byTooltip('文件树'));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 260.0),
        findsOneWidget,
      );
      expect(find.byType(FileTreePanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    /// 窄屏(375)：文件树退化为 endDrawer，不再内联 260，无溢出。
    testWidgets('窄屏(375) 文件树退化为 endDrawer 且不内联 260', (tester) async {
      await _pumpShell(tester, const Size(375, 812), docs);

      // 初始隐藏。
      expect(find.byType(FileTreePanel), findsNothing);

      // 点击「文件树」→ 打开 endDrawer（覆盖层），不应出现内联 260 列。
      await tester.tap(find.byTooltip('文件树'));
      await tester.pumpAndSettle();

      // 关键回归：窄屏下不得内联 SizedBox(width:260) 挤占编辑区。
      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 260.0),
        findsNothing,
      );
      // 但文件树仍可通过抽屉访问。
      expect(find.byType(FileTreePanel), findsOneWidget);
      // 主编辑区不得溢出。
      expect(tester.takeException(), isNull);
    });

    /// FormulaInsertDialog：窄屏不溢出且宽度 ≤ 屏宽 90%；宽屏保持 480。
    testWidgets('FormulaInsertDialog 窄屏宽度不溢出且不超过屏宽 90%',
        (tester) async {
      // 375 窄屏。
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(375, 800)),
          child: MaterialApp(
            home: FormulaInsertDialog(displayMode: false, isDark: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull); // 无溢出

      final narrowOuter = tester.widget<Container>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints is BoxConstraints,
          ),
        ),
      );
      // min(480, 375 * 0.9) = 337.5（固定宽存于 constraints.maxWidth）
      expect((narrowOuter.constraints as BoxConstraints).maxWidth, closeTo(337.5, 0.01));

      // 800 宽屏 —— 仍为 480。
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 800)),
          child: MaterialApp(
            home: FormulaInsertDialog(displayMode: false, isDark: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final wideOuter = tester.widget<Container>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints is BoxConstraints,
          ),
        ),
      );
      expect((wideOuter.constraints as BoxConstraints).maxWidth, closeTo(480.0, 0.01));
    });
  });

  // P1 验收补充（2026-08-04）：焦点模式双击退出交互测试。
  //
  // editor_shell.dart 在 GestureDetector 上：
  //   onDoubleTap: _focusMode ? _toggleFocus : null
  // 即焦点模式下双击退出，非焦点模式下双击不响应（避免单击延迟影响 TextField）。
  // 此处锁定两条关键行为，避免后续手势处理重构静默改变交互契约。
  group('P1-3 焦点模式双击退出', () {
    /// 进入焦点模式：点击 AppBar 的「焦点模式」IconButton（tooltip='焦点模式'）。
    Future<void> _enterFocusMode(WidgetTester tester) async {
      await tester.tap(find.byTooltip('焦点模式'));
      await tester.pumpAndSettle();
    }

    testWidgets('焦点模式下双击编辑区 → 退出焦点模式（AppBar 重新出现）',
        (tester) async {
      await _pumpShell(tester, const Size(800, 1200), docs);

      // 初始：AppBar + StatusBar 可见（非焦点模式）。
      expect(find.byTooltip('焦点模式'), findsOneWidget);
      expect(find.byTooltip('退出焦点模式'), findsNothing);

      // 进入焦点模式：AppBar 隐藏（tooltip 变为 '退出焦点模式' 不存在因 AppBar 已 null）。
      await _enterFocusMode(tester);
      await tester.pumpAndSettle();
      // AppBar 隐藏后，"焦点模式" / "退出焦点模式" 两个 tooltip 都不应出现。
      expect(find.byTooltip('焦点模式'), findsNothing);
      expect(find.byTooltip('退出焦点模式'), findsNothing);

      // 双击编辑区（Workspace 区域） → _toggleFocus → 退出焦点模式。
      // 用 find.byType(Workspace) 定位编辑区，避免点到 AppBar/StatusBar。
      final workspaceFinder = find.byType(Workspace);
      expect(workspaceFinder, findsOneWidget);
      await tester.tap(workspaceFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(workspaceFinder);
      await tester.pumpAndSettle();

      // 退出焦点模式后 AppBar 回归，「焦点模式」tooltip 重新可见。
      expect(find.byTooltip('焦点模式'), findsOneWidget,
          reason: '双击应退出焦点模式，AppBar 重新出现');
      expect(tester.takeException(), isNull);
    });

    testWidgets('非焦点模式下双击编辑区 → 无响应（AppBar 仍可见）',
        (tester) async {
      await _pumpShell(tester, const Size(800, 1200), docs);

      // 初始即为非焦点模式，AppBar 可见。
      expect(find.byTooltip('焦点模式'), findsOneWidget);

      // 双击编辑区：onDoubleTap 在非焦点模式下为 null，不应触发 _toggleFocus。
      final workspaceFinder = find.byType(Workspace);
      expect(workspaceFinder, findsOneWidget);
      await tester.tap(workspaceFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(workspaceFinder);
      await tester.pumpAndSettle();

      // 关键回归：AppBar 仍可见（焦点模式未被触发）。
      expect(find.byTooltip('焦点模式'), findsOneWidget,
          reason: '非焦点模式下 onDoubleTap=null，双击不应切换状态');
      expect(find.byTooltip('退出焦点模式'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
