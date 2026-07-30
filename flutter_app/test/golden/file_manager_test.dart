/// TC-GOLDEN-1: FileManager 布局（P1-4 矩阵扩充）
///
/// 对应 docs/PHASE1_TEST_PLAN.md §11 Golden UI 测试。
///
/// 目的：布局回归保护 + 像素回归保护（空状态为最高频路径）。
/// 方法：pump FileManagerScreen（override [documentListProvider] 注入空流，绕过
/// 真实文件 I/O）→ 结构性断言 + 与 golden 基线像素比对。
///
/// ## Tag 策略
///
/// 本文件 library 级声明 `@Tags(['golden'])`，CI 的 `golden` job
/// （ci.yml `if: true`）跑 `flutter test --tags golden` 与 Linux 基线比对。
/// 主 test job 用 `--exclude-tags golden` 排除本文件，避免跨平台字体渲染差异
/// 在主 job 抖动。基线由 Linux（WSL / CI 同环境）生成，禁 Windows 本机基线。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/screens/file_manager_screen.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';
import 'package:formula_fix/providers/file_repository_provider.dart';
import 'golden_helpers.dart';

/// 空文档列表 —— 用于覆盖 [documentListProvider]，绕过真实文件 I/O。
Stream<List<Document>> _emptyDocsStream() async* {
  yield const <Document>[];
}

List<Override> _emptyOverrides() => <Override>[
      documentListProvider.overrideWith((_) => _emptyDocsStream()),
    ];

Future<void> _pumpFileManager(
  WidgetTester tester,
  ThemeData theme, {
  Size size = const Size(800, 1200),
}) async {
  await pumpFullScreenGolden(
    tester,
    const FileManagerScreen(),
    theme: theme,
    size: size,
    overrides: _emptyOverrides(),
  );
}

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  group('TC-GOLDEN-1 FileManager 空状态布局', () {
    testWidgets('light @800：空状态 + 像素基线', (tester) async {
      await _pumpFileManager(tester, AppTheme.lightTheme);

      // 结构性断言：布局回归守护
      expect(find.text('文件'), findsWidgets, reason: 'AppBar 应显示「文件」标题');
      expect(find.text('暂无保存的文档'), findsWidgets,
          reason: '空状态应显示「暂无保存的文档」');
      expect(find.byIcon(Icons.folder_open_outlined), findsWidgets,
          reason: '空状态应显示 folder_open_outlined 图标');

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/file_manager.png'),
      );
    });

    testWidgets('light @834（平板宽度）', (tester) async {
      await _pumpFileManager(
        tester,
        AppTheme.lightTheme,
        size: const Size(834, 1200),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/file_manager_light_834.png'),
      );
    });

    testWidgets('dark @800', (tester) async {
      await _pumpFileManager(tester, AppTheme.darkTheme);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/file_manager_dark.png'),
      );
    });

    testWidgets('dark @834（平板宽度）', (tester) async {
      await _pumpFileManager(
        tester,
        AppTheme.darkTheme,
        size: const Size(834, 1200),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('golden/file_manager_dark_834.png'),
      );
    });
  });

  group('TC-GOLDEN-3 工具栏布局', () {
    testWidgets('FileManager AppBar 布局稳定', (tester) async {
      await _pumpFileManager(tester, AppTheme.lightTheme);
      expect(find.byType(AppBar), findsWidgets);
      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}
