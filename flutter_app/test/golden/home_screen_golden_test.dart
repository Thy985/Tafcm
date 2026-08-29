/// P0-2 首页整页 golden —— 还原度 Top 1 盲区补强。
///
/// 覆盖 [HomeScreen] 三主题（light / dark / sepia）× 两内容态（空 / 有文档）
/// 的标准 800×1200 基线，外加窄屏 375 三主题基线（拦截窄屏破版）。
///
/// 数据经 [documentListProvider].overrideWith 注入固定 Stream，绕过真实文件
/// I/O；[recentDocumentsProvider] / [earlierDocumentsProvider] 派生自它，自动
/// 反映注入数据（前 3 篇=最近，第 4 篇起=更早）。
///
/// 用 [pumpFullScreenGolden] 直接以 HomeScreen 为 home（不嵌套 Scaffold），忠实
/// 还原 P0-4「内容顶到最顶、只留系统状态栏」的视觉。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/screens/home_screen.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/providers/file_repository_provider.dart';
import 'golden_helpers.dart';

/// 5 篇文档：前 3 篇落入「最近」，后 2 篇落入「更早」，两区均渲染。
List<Document> _populatedDocs() => <Document>[
      Document(
        id: 'doc-1',
        title: 'Calculus Cheat Sheet',
        content: '# Calculus\n\nThe derivative of x^2 is 2x.',
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 7, 20, 9, 12),
      ),
      Document(
        id: 'doc-2',
        title: 'Linear Algebra Notes',
        content: '# Linear Algebra\n\nA matrix times its inverse is I.',
        createdAt: DateTime(2026, 2, 2),
        updatedAt: DateTime(2026, 7, 18, 14, 30),
      ),
      Document(
        id: 'doc-3',
        title: 'Probability Basics',
        content: '# Probability\n\nP(A ∪ B) = P(A) + P(B) - P(A ∩ B).',
        createdAt: DateTime(2026, 3, 15),
        updatedAt: DateTime(2026, 7, 15, 8, 0),
      ),
      Document(
        id: 'doc-4',
        title: 'Complex Numbers',
        content: '# Complex Numbers\n\nEuler: e^{iπ} + 1 = 0.',
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 6, 30, 20, 45),
      ),
      Document(
        id: 'doc-5',
        title: 'Discrete Math',
        content: '# Discrete Math\n\nA graph is bipartite iff it has no odd cycle.',
        createdAt: DateTime(2026, 5, 5),
        updatedAt: DateTime(2026, 5, 28, 11, 11),
      ),
    ];

List<Override> _docOverrides(List<Document> docs) => <Override>[
      documentListProvider.overrideWith((_) => Stream.value(docs)),
    ];

Future<void> _pumpHome(
  WidgetTester tester,
  ThemeData theme,
  List<Document> docs, {
  Size size = const Size(800, 1200),
}) async {
  await pumpFullScreenGolden(
    tester,
    // 注入固定 now，保证相对时间（_relativeTime）跨运行时确定，
    // 否则 DateTime.now() 在基线生成与 CI 间漂移导致 golden 像素差。
    HomeScreen(now: DateTime(2026, 7, 30, 12, 0)),
    theme: theme,
    size: size,
    overrides: _docOverrides(docs),
  );
}

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  group('P0-2 HomeScreen 整页 golden（800×1200）', () {
    testWidgets('light / 空状态', (tester) async {
      await _pumpHome(tester, AppTheme.lightTheme, const <Document>[]);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_light_empty.png'),
      );
    });

    testWidgets('light / 有文档', (tester) async {
      await _pumpHome(tester, AppTheme.lightTheme, _populatedDocs());
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_light_populated.png'),
      );
    });

    testWidgets('dark / 空状态', (tester) async {
      await _pumpHome(tester, AppTheme.darkTheme, const <Document>[]);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_dark_empty.png'),
      );
    });

    testWidgets('dark / 有文档', (tester) async {
      await _pumpHome(tester, AppTheme.darkTheme, _populatedDocs());
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_dark_populated.png'),
      );
    });

    testWidgets('sepia / 空状态', (tester) async {
      await _pumpHome(tester, AppTheme.sepiaTheme, const <Document>[]);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_sepia_empty.png'),
      );
    });

    testWidgets('sepia / 有文档', (tester) async {
      await _pumpHome(tester, AppTheme.sepiaTheme, _populatedDocs());
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_sepia_populated.png'),
      );
    });
  });

  group('P0-2 HomeScreen 窄屏 golden（375×1200，破版守护）', () {
    testWidgets('narrow / light / 有文档', (tester) async {
      await _pumpHome(
        tester,
        AppTheme.lightTheme,
        _populatedDocs(),
        size: const Size(375, 1200),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_narrow_light.png'),
      );
    });

    testWidgets('narrow / dark / 有文档', (tester) async {
      await _pumpHome(
        tester,
        AppTheme.darkTheme,
        _populatedDocs(),
        size: const Size(375, 1200),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_narrow_dark.png'),
      );
    });

    testWidgets('narrow / sepia / 有文档', (tester) async {
      await _pumpHome(
        tester,
        AppTheme.sepiaTheme,
        _populatedDocs(),
        size: const Size(375, 1200),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/home_screen_narrow_sepia.png'),
      );
    });
  });
}
