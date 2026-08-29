/// Phase 3.4.2 文件树 review 补充测试。
///
/// 覆盖 PR #77 代码评审指出的三处待补强：
/// 1. [EditorPage] 真实 .md 加载失败时回退种子文档，UI 正常（不抛未捕获异常）。
/// 2. [BootstrapScreen] 重启恢复：SharedPreferences 含上次路径 → 导航到 `/editor?path=...`。
/// 3. [EditorShell] 文件树开关：`_showFileTree` 切换时 [FileTreePanel] 出现 / 消失。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/main.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_page.dart';
import 'package:tafcm/presentation/editor/editor_shell.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/seed_documents.dart';
import 'package:tafcm/presentation/panels/file_tree_panel.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/providers/file_repository_provider.dart';
import 'package:tafcm/providers/last_opened_path_provider.dart';

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

/// [DocumentRepository.readDocument] 直接抛异常，用于验证 EditorPage 加载失败回退路径。
class _ThrowingFileRepository extends FileRepository {
  @override
  Future<Document> readDocument(String path) async =>
      throw Exception('injected read failure');
}

/// 返回固定文档列表的仓储桩，用于验证 EditorShell 文件树侧栏渲染。
class _FixedListFileRepository extends FileRepository {
  final List<Document> _docs;
  _FixedListFileRepository(this._docs);

  @override
  Future<List<Document>> listDocuments() async => _docs;
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    // 测试环境需 mock SharedPreferences，否则 BootstrapScreen 的 getInstance() 卡在 loading。
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 3.4.2 文件树 review 补充测试', () {
    /// 1. EditorPage 打开不存在/不可读的真实 .md → 回退种子文档，UI 正常。
    testWidgets('EditorPage 文件加载失败回退种子文档且 UI 正常',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileRepositoryProvider.overrideWithValue(_ThrowingFileRepository()),
          ],
          // Phase 3.4.3 / ADR-0015：EditorTokens 需通过 ThemeData.extensions 注入，
          // 否则 CodeBlock 等使用 EditorTokens.of(context) 的块会抛"未注入"。
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const EditorPage(filePath: '/nonexistent.md', seedSelector: 0),
          ),
        ),
      );

      // 加载（异步失败 → 回退种子）完成，编辑器外壳出现，无未捕获异常。
      await tester.pumpAndSettle();
      expect(find.byType(EditorShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    /// 2. BootstrapScreen 恢复路径：SharedPreferences 含上次打开路径 → 进入 /editor。
    testWidgets('BootstrapScreen 含上次路径时恢复导航到 /editor',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        kLastOpenedPathPrefKey: '/documents/last_opened.md',
      });

      await tester.pumpWidget(
        ProviderScope(
          // 用抛出异常的仓储覆盖，避免测试环境对真实文件 I/O 的拦截导致挂起；
          // 重点验证「启动屏→/editor」的恢复导航，而非文件内容加载本身。
          overrides: [fileRepositoryProvider.overrideWithValue(_ThrowingFileRepository())],
          child: const TafcmApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 恢复导航应进入编辑器路由（展示 EditorShell），而非停留在文件管理页。
      expect(find.byType(EditorShell), findsOneWidget);
      expect(find.text('文件管理'), findsNothing);
    });

    /// 3. EditorShell 文件树开关：点击「文件树」按钮，FileTreePanel 出现；再点消失。
    testWidgets('EditorShell 文件树 toggle 切换 FileTreePanel 出现/消失',
        (WidgetTester tester) async {
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
      final coordinator = EditorCoordinator(
        editor: SeedDocuments.createDemo1(),
        history: EditorHistory(maxHistorySize: 200),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileRepositoryProvider
                .overrideWithValue(_FixedListFileRepository(docs)),
          ],
          // Phase 3.4.3 / ADR-0015：EditorTokens 需通过 ThemeData.extensions 注入，
          // 否则种子文档中的 CodeBlock 等使用 EditorTokens.of(context) 的块会抛"未注入"。
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: EditorScope(
              coordinator: coordinator,
              child: EditorShell(coordinator: coordinator),
            ),
          ),
        ),
      );

      // 初始：文件树隐藏。
      expect(find.byType(FileTreePanel), findsNothing);

      // 点击「文件树」按钮 → 侧栏出现。
      await tester.tap(find.byTooltip('文件树'));
      await tester.pumpAndSettle();
      expect(find.byType(FileTreePanel), findsOneWidget);

      // 再次点击 → 侧栏隐藏。
      await tester.tap(find.byTooltip('文件树'));
      await tester.pumpAndSettle();
      expect(find.byType(FileTreePanel), findsNothing);
    });
  });
}
