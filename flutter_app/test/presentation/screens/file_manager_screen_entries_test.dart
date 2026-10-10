/// issue #338 回归测试：FileManagerScreen 自服务入口。
///
/// 背景：「文件」Tab 是应用的主实体列表页，原实现只有 AppBar 标题 + 列表，
/// 没有任何新建 / 导入入口 —— 用户必须跨 Tab 回首页才能发起新建文档。
/// QA 实测（冷启动落点 = 文件 Tab）：新建文档需 3 步（跨 Tab 才能发起）。
///
/// 本测试锁定四件事：
/// 1. AppBar 存在搜索 / 导入 / 新建三个可点入口（tooltip 标签稳定）。
/// 2. 搜索入口通向 /search（全 App 搜索能力早已实现，但入口从未渲染 —— #338）。
/// 3. 空状态下引导文案指向右上按钮，不再说「在编辑器中保存文档后将显示在此处」
///    （该提示在有了页内新建入口后已不成立）。
/// 4. 非空列表状态下三个入口依然可达（不被列表布局挤掉）。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/presentation/screens/file_manager_screen.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/providers/file_repository_provider.dart';

/// 不触发真实文件 I/O 的 [FileRepository] 桩：固定返回构造时给定的文档列表。
class _FixedListFileRepository extends FileRepository {
  _FixedListFileRepository(this.docs);

  final List<Document> docs;

  @override
  Future<List<Document>> listDocuments() async => docs;

  @override
  Stream<List<Document>> watchAllDocuments() async* {
    yield docs;
  }

  @override
  Future<String> createDocument(String title, String content) async =>
      '/tmp/fake-${docs.length}.md';
}

/// 测试用 [FilePicker] 桩。必须继承（而非 implements）[FilePicker]，
/// 因为 file_picker 的 PlatformInterface 用 token 校验 set platform 的实例。
/// `result` 为 null 时模拟「用户取消选择」，避免测试依赖真实 SAF 弹窗。
class _MockFilePicker extends FilePicker {
  _MockFilePicker([this.result]);

  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => result;
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 挂最小 GoRouter（/files + /editor），让 doc_actions 里的
  /// `context.go('/editor?path=...')` 可被路由器消费而非抛 "no Scope"。
  /// /editor 用占位 Scaffold 代替真实 EditorPage（后者会触发文件 I/O + WebView）。
  Future<void> _pumpFiles(
    WidgetTester tester,
    List<Document> docs, {
    FilePickerResult? pickResult,
  }) async {
    final mockPicker = _MockFilePicker(pickResult);
    FilePicker.platform = mockPicker;

    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder: (context, state) => const FileManagerScreen(),
        ),
        GoRoute(
          path: '/editor',
          builder: (context, state) => Scaffold(
            body: Center(
              child: Column(
                children: [
                  const Text('editor-stub'),
                  // 回显完整 URI：用于断言外部 .md 走只读（readOnly=1）。
                  Text('uri=${state.uri}'),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('search-stub'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileRepositoryProvider.overrideWithValue(
            _FixedListFileRepository(docs),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.lightTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('issue #338 FileManagerScreen 自服务入口', () {
    testWidgets('AppBar 含搜索 + 导入 + 新建三个入口', (tester) async {
      await _pumpFiles(tester, const []);

      expect(find.byTooltip('搜索'), findsOneWidget);
      expect(find.byTooltip('导入 .md 文件'), findsOneWidget);
      expect(find.byTooltip('新建文档'), findsOneWidget);
    });

    testWidgets('点搜索入口进 /search', (tester) async {
      await _pumpFiles(tester, const []);

      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('search-stub'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('导入/新建入口均可点击且不抛异常（取消选择时不导航）', (tester) async {
      await _pumpFiles(tester, const []);

      await tester.tap(find.byTooltip('导入 .md 文件'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 用户取消选择 → 停留在文件页
      expect(find.text('文件'), findsOneWidget);

      await tester.tap(find.byTooltip('新建文档'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 新建成功 → 跳到 /editor 占位
      expect(find.text('editor-stub'), findsOneWidget);
    });

    testWidgets('导入外部 .md 以只读打开（URI 带 readOnly=1，锁 #330 契约）',
        (tester) async {
      await _pumpFiles(
        tester,
        const [],
        pickResult: FilePickerResult([
          PlatformFile(path: '/mock/big.md', name: 'big.md', size: 100),
        ]),
      );

      await tester.tap(find.byTooltip('导入 .md 文件'));
      await tester.pumpAndSettle();

      expect(find.text('editor-stub'), findsOneWidget);
      expect(find.textContaining('readOnly=1'), findsOneWidget,
          reason: '外部 .md 必须带 readOnly=1，否则退化为「可编辑但退出即丢」（#330）');
    });

    testWidgets('空状态引导文案指向右上按钮，不再要求去编辑器保存',
        (tester) async {
      await _pumpFiles(tester, const []);

      expect(find.text('暂无保存的文件'), findsOneWidget);
      expect(find.text('点右上角按钮新建，或导入已有的 .md'), findsOneWidget);
      // 旧文案已失效（有了页内新建入口），必须不再出现
      expect(find.textContaining('在编辑器中保存'), findsNothing);
    });

    testWidgets('非空列表下三个入口依然可达', (tester) async {
      final docs = [
        Document(
          id: 'd1',
          title: '测试文档',
          content: '# 测试文档\n\n正文内容',
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 2),
        ),
      ];
      await _pumpFiles(tester, docs);

      expect(find.byTooltip('搜索'), findsOneWidget);
      expect(find.byTooltip('导入 .md 文件'), findsOneWidget);
      expect(find.byTooltip('新建文档'), findsOneWidget);
      // 文档标题正常渲染，入口未把列表挤掉
      expect(find.text('测试文档'), findsOneWidget);
    });
  });
}
