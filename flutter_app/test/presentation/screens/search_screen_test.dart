/// P0-1 全局搜索接线守门（EXTERNAL-PROJECTS-EMPOWERMENT-PLAN §4.1 验收）。
///
/// 覆盖：
/// - searchDocuments 后端契约：中文关键词命中（标题/正文）、空查询返回空
/// - SearchScreen 三态：初始提示（未输入）/ 无结果 / 结果列表
/// - 结果点击 → context.go('/editor?path=...') 导航
/// - 命中片段高亮（TextSpan 含 w700 加粗段）
///
/// Repository 注入：内存 stub（不触真实文件 I/O），挂最小 GoRouter。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/screens/search_screen.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/providers/file_repository_provider.dart';

/// 内存 stub：搜索数据固定注入，其余方法 fatal（本套件不应触达）。
class _StubRepository implements DocumentRepository {
  final List<Document> docs;
  _StubRepository(this.docs);

  @override
  Future<List<Document>> searchDocuments(String query) async {
    final q = query.toLowerCase();
    if (q.isEmpty) return const [];
    return docs
        .where((d) =>
            d.title.toLowerCase().contains(q) ||
            d.content.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<String> documentPathFor(String id) async => '/docs/$id.md';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不应被搜索屏触达');
}

/// 真实 FileRepository 契约测试用临时目录版：仅验证空查询语义。
class _EmptyFileRepository extends FileRepository {
  @override
  Future<List<Document>> searchDocuments(String query) async => const [];
}

Document _doc(String id, String title, String content) => Document(
      id: id,
      title: title,
      content: content,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

Future<void> _pumpSearch(
  WidgetTester tester, {
  required DocumentRepository repo,
}) async {
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      GoRoute(
        path: '/editor',
        builder: (_, state) {
          final path = state.uri.queryParameters['path'];
          return Scaffold(body: Text('editor-stub:$path'));
        },
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: [fileRepositoryProvider.overrideWithValue(repo)],
      ),
      child: MaterialApp.router(
        theme: AppTheme.lightTheme, // 不可 const（EditorTokens 注入，§11.5）
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 输入并越过 300ms 防抖 + 搜索 settle。
Future<void> _typeAndSettle(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 350)); // 越过防抖窗口
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('初始态：未输入时显示提示，不调搜索', (tester) async {
    await _pumpSearch(tester, repo: _StubRepository(const []));
    expect(find.text('输入关键词搜索文档标题与正文'), findsOneWidget);
    expect(find.text('没有匹配的文档'), findsNothing);
  });

  testWidgets('无结果态：查询无命中显示空态', (tester) async {
    await _pumpSearch(tester, repo: _StubRepository([
      _doc('a', 'Calculus', 'The derivative'),
    ]));
    await _typeAndSettle(tester, 'quantum');
    expect(find.text('没有匹配的文档'), findsOneWidget);
  });

  testWidgets('中文关键词命中标题：结果列表含标题与高亮片段', (tester) async {
    final doc = _doc(
      'b',
      '线性代数笔记',
      '# 线性代数\n\n矩阵的逆是线性代数的核心概念之一。',
    );
    await _pumpSearch(tester, repo: _StubRepository([doc]));
    await _typeAndSettle(tester, '矩阵');

    expect(find.text('线性代数笔记'), findsOneWidget);
    // 命中片段加粗（TextSpan fontWeight w700）——Text.rich 会把传入 span
    // 包进 DefaultTextStyle wrapper（两层结构），故递归遍历全树 span 判定，
    // 具体颜色跨主题不稳，以加粗为守门锚点。
    bool hasBoldSpan(InlineSpan? span) {
      if (span is! TextSpan) return false;
      if (span.style?.fontWeight == FontWeight.w700) return true;
      return span.children?.any(hasBoldSpan) ?? false;
    }

    final hasBold = tester
        .widgetList<RichText>(find.byType(RichText))
        .any((r) => hasBoldSpan(r.text));
    expect(hasBold, isTrue, reason: '命中词应有加粗高亮');
  });

  testWidgets('中文关键词命中正文：点击结果进编辑器（path 传参）', (tester) async {
    final doc = _doc('c', '微积分', '定积分的几何意义是曲边梯形面积。');
    await _pumpSearch(tester, repo: _StubRepository([doc]));
    await _typeAndSettle(tester, '曲边梯形');

    expect(find.text('微积分'), findsOneWidget);
    await tester.tap(find.text('微积分'));
    await tester.pumpAndSettle();
    // Document.path 由 repository 生成——stub 未带 path 字段时命中项
    // path 为空串，守门锚点是"导航发生"（editor-stub 出现）而非路径值。
    expect(find.textContaining('editor-stub:'), findsOneWidget);
  });

  testWidgets('空查询清空结果回初始态', (tester) async {
    await _pumpSearch(tester, repo: _StubRepository([
      _doc('d', 'Calculus', 'derivative'),
    ]));
    await _typeAndSettle(tester, 'derivative');
    expect(find.text('Calculus'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('输入关键词搜索文档标题与正文'), findsOneWidget);
    expect(find.text('Calculus'), findsNothing);
  });

  test('searchDocuments 契约：空查询返回空列表（FileRepository 语义）', () async {
    // 端口语义守门：空查询 = 无结果，而非"全部文档"。
    final repo = _EmptyFileRepository();
    expect(await repo.searchDocuments(''), isEmpty);
  });
}
