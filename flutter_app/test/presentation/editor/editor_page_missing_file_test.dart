/// #319 widget 回归：resume 检测接线——observer 触发守护 → 重建 → 告知。
///
/// 覆盖 EditorPage 的**接线**：WidgetsBindingObserver 在 resume 时调用
/// 守护逻辑，文件缺失 → `writeDocument` + SnackBar；文件健在 → 无打扰。
///
/// **测试环境须知**：testWidgets 体内任何真实文件 I/O 都不会推进（fake
/// async 区），故本文件仓储全部用内存 fake、路径用哨兵值；守护逻辑本身
/// （含真实文件系统行为）由 `doc_file_resume_guard_test.dart` 用普通
/// `test()` + 临时目录覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/core/document_repository.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_page.dart';
import 'package:tafcm/presentation/editor/editor_shell.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/providers/current_path_provider.dart';
import 'package:tafcm/providers/file_repository_provider.dart';

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
    throw UnimplementedError(
        'NoopPlatformInAppWebViewWidget.controllerFromPlatform');
  }

  @override
  void dispose() {}
}

/// 内存 fake：`documentFileExists` 可编程；写动作被记录。零真实 I/O。
class _FakeDocRepository implements DocumentRepository {
  bool fileExists;
  final List<String> writtenPaths = [];
  final List<String> writtenContents = [];

  _FakeDocRepository({required this.fileExists});

  @override
  Future<bool> documentFileExists(String path) async => fileExists;

  @override
  Future<void> writeDocument(String path,
      {required String title, required String content}) async {
    writtenPaths.add(path);
    writtenContents.add(content);
    fileExists = true; // 写后即存在（与真实仓储一致）
  }

  @override
  Future<Document> readDocument(String path) async =>
      throw StateError('widget 测试不走真实读路径（seed 回退）');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不应被本测试触达');
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  const docPath = '/sentinel/documents/t319_doc.md';

  /// 泵真实 EditorPage（读路径抛错 → 种子回退，不产生真实 I/O），并把
  /// currentPath 指到哨兵路径（模拟「已打开真实文档」状态）。
  Future<void> pumpEditor(
    WidgetTester tester,
    _FakeDocRepository repo,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileRepositoryProvider.overrideWithValue(repo),
          currentPathProvider.overrideWith((ref) => docPath),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: EditorPage(filePath: docPath, seedSelector: 0),
        ),
      ),
    );
    // 不用 pumpAndSettle：真实编辑器含持续动画（光标闪烁），永不收敛。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EditorShell), findsOneWidget,
        reason: '前置：编辑器外壳已就绪');
  }

  testWidgets('resume 时文件缺失 → 写回内存内容并 SnackBar 告知', (tester) async {
    final repo = _FakeDocRepository(fileExists: false);
    await pumpEditor(tester, repo);

    // 加载失败回退种子时已展示一条「无法打开文件」SnackBar（5s）。测试
    // fake-async 计时下它的消失计时器不推进、会永久占住 ScaffoldMessenger
    // 队列，重建告知排在其后永不可见（探针实测）——resume 前主动清掉，
    // 让本测试只关注重建告知自身。
    ScaffoldMessenger.of(tester.element(find.byType(EditorShell)))
        .hideCurrentSnackBar();
    await tester.pump(const Duration(seconds: 1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    expect(repo.writtenPaths, [docPath],
        reason: '#319：resume 检测到文件缺失必须立即写回');
    expect(repo.writtenContents.single, isNotEmpty);
    expect(find.textContaining('已从磁盘消失，已从内存重建'), findsOneWidget,
        reason: '#319：不得静默——用户必须被告知文件消失与重建');

    expect(repo.writtenPaths, [docPath],
        reason: '#319：resume 检测到文件缺失必须立即写回');
    expect(repo.writtenContents.single, isNotEmpty);
    expect(find.textContaining('已从磁盘消失，已从内存重建'), findsOneWidget,
        reason: '#319：不得静默——用户必须被告知文件消失与重建');
  });


  testWidgets('resume 时文件健在 → 静默返回，不写不告知', (tester) async {
    final repo = _FakeDocRepository(fileExists: true);
    await pumpEditor(tester, repo);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    expect(repo.writtenPaths, isEmpty, reason: '文件健在时不得重写');
    expect(find.textContaining('已从磁盘消失'), findsNothing,
        reason: '文件健在时不得打扰用户');
  });

  testWidgets('演示文档（无落盘主）resume → 不触发守护', (tester) async {
    final repo = _FakeDocRepository(fileExists: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fileRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const EditorPage(seedSelector: 0),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EditorShell), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    expect(repo.writtenPaths, isEmpty,
        reason: '演示文档无 currentPath，守护必须跳过（不为种子文档凭空建文件）');
  });
}
