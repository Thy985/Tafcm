/// P1 真机 E2E：验证问题 2/3/6 修复。
///
/// **对应文档**：docs/releases/phase3.5-realdevice-issues.md 问题 2/3/6
/// **修复内容**：
/// - 问题 2: 返回按钮 canPop + go('/home') 兜底
/// - 问题 3: 工具条全禁用时隐藏 + 触屏长按触发
/// - 问题 6.1: 语法高亮主题随 app 主题切换
/// - 问题 6.5: 编辑态显示 language chip
/// - 问题 6.4: 导出代码块 CJK fontFallback
///
/// 运行：flutter test integration_test/phase35_p1_e2e_test.dart -d <device>
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

import 'package:tafcm/domain/services/export_service.dart';
import 'package:tafcm/presentation/blocks/code/code_block.dart';
import 'package:tafcm/presentation/blocks/shared/block_toolbar.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/states/block_view_state.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'helpers/test_fixture_file.dart';

EditorCoordinator _coord(WidgetTester tester) {
  final scope = tester.widget<EditorScope>(find.byType(EditorScope));
  return scope.coordinator;
}

void main() {
  group('P1 E2E: 问题3 — 单块时 BlockToolbar 不显示', () {
    testWidgets('E2E-P1-1: 单块状态下 BlockToolbar 不可见', (tester) async {
      final path = await createTestDoc(
        title: 'p1-toolbar-single',
        content: '唯一块',
      );
      await pumpEditorFromFile(tester, filePath: path);

      // 单块状态：上移/下移/删除全禁用 → BlockToolbar 应返回 SizedBox.shrink()
      // 即使 BlockSelectionChrome 尝试显示，BlockToolbar 内部全禁用会隐藏
      final toolbarFinder = find.byType(BlockToolbar);
      if (toolbarFinder.evaluate().isNotEmpty) {
        // 如果 BlockToolbar 存在于 widget 树，验证它渲染为 SizedBox.shrink
        final toolbar = tester.widget<BlockToolbar>(toolbarFinder);
        final coord = toolbar.coordinator;
        final canMoveUp = toolbar.index > 0;
        final canMoveDown = toolbar.index < (coord.blockCount - 1);
        final canDelete = coord.blockCount > 1;
        expect(canMoveUp || canMoveDown || canDelete, isFalse,
            reason: '单块时上移/下移/删除应全部禁用');
      }
      // 验证：单块时不应有可见的 BlockToolbar 渲染内容
      expect(find.byType(BlockToolbar), findsNothing,
          reason: '单块时 BlockToolbar 应完全不渲染（全禁用 → SizedBox.shrink 不进 Stack）');
    });
  });

  group('P1 E2E: 问题6.1 — 语法高亮主题随 app 主题切换', () {
    testWidgets('E2E-P1-2: dark 主题下 CodeBlock 使用 atomOneDarkTheme', (tester) async {
      final path = await createTestDoc(
        title: 'p1-code-dark',
        content: '```dart\nvoid main() {}\n```',
      );
      await pumpEditorFromFile(tester, filePath: path, theme: AppTheme.darkTheme);

      // 验证 CodeBlock 存在
      expect(find.byType(CodeBlock), findsOneWidget,
          reason: '应渲染一个 CodeBlock');

      // 验证 HighlightView 存在
      expect(find.byType(HighlightView), findsOneWidget,
          reason: '应渲染 HighlightView');

      // 验证当前 Brightness 为 dark
      final context = tester.element(find.byType(CodeBlock));
      expect(Theme.of(context).brightness, equals(Brightness.dark),
          reason: '应处于 dark 主题');

      // 验证 HighlightView 的 theme 为 atomOneDarkTheme（非 githubTheme）
      final highlightView = tester.widget<HighlightView>(find.byType(HighlightView));
      expect(highlightView.theme, equals(atomOneDarkTheme),
          reason: 'dark 主题下应使用 atomOneDarkTheme');
      expect(highlightView.theme, isNot(equals(githubTheme)),
          reason: 'dark 主题下不应使用 githubTheme');
    });

    testWidgets('E2E-P1-3: light 主题下 CodeBlock 使用 githubTheme', (tester) async {
      final path = await createTestDoc(
        title: 'p1-code-light',
        content: '```dart\nvoid main() {}\n```',
      );
      await pumpEditorFromFile(tester, filePath: path, theme: AppTheme.lightTheme);

      expect(find.byType(HighlightView), findsOneWidget);

      final context = tester.element(find.byType(CodeBlock));
      expect(Theme.of(context).brightness, equals(Brightness.light));

      final highlightView = tester.widget<HighlightView>(find.byType(HighlightView));
      expect(highlightView.theme, equals(githubTheme),
          reason: 'light 主题下应使用 githubTheme');
    });
  });

  group('P1 E2E: 问题6.5 — 编辑态显示 language chip', () {
    testWidgets('E2E-P1-4: 代码块进入编辑态后 language chip 可见', (tester) async {
      final path = await createTestDoc(
        title: 'p1-code-edit-chip',
        content: '```python\nprint("hello")\n```',
      );
      await pumpEditorFromFile(tester, filePath: path);

      final coord = _coord(tester);
      final codeBlockId = coord.allIds.first;

      // 进入编辑态
      coord.setFocus(codeBlockId);
      await tester.pumpAndSettle();

      // 验证 viewState 为 editing
      final vs = coord.viewStateOf(codeBlockId);
      expect(vs?.mode, equals(RenderMode.editing),
          reason: '代码块应处于编辑态');

      // 验证 language chip 文本 "python" 可见
      expect(find.text('python'), findsOneWidget,
          reason: '编辑态应显示 language chip "python"');
    });

    testWidgets('E2E-P1-5: 无 language 的代码块编辑态不显示 chip', (tester) async {
      final path = await createTestDoc(
        title: 'p1-code-no-lang',
        content: '```\nplain code\n```',
      );
      await pumpEditorFromFile(tester, filePath: path);

      final coord = _coord(tester);
      final codeBlockId = coord.allIds.first;

      coord.setFocus(codeBlockId);
      await tester.pumpAndSettle();

      // 无 language 时不应有 language chip
      // plaintext 是 _normalizeLanguage 的 fallback，但 language 为空时不显示 chip
      expect(find.text('plaintext'), findsNothing,
          reason: '无 language 的代码块编辑态不应显示 chip');
    });
  });

  group('P1 E2E: 问题6.4 — 导出代码块中文注释字体', () {
    testWidgets('E2E-P1-6: PDF 含代码块中文注释 + 字体子集嵌入', (tester) async {
      const markdown = '''# 代码块中文注释导出测试

```dart
// 中文注释：计算斐波那契数列
int fib(int n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2); // 递归调用
}
```
''';

      final bytes = await MarkdownExporter.exportToPdf(
        markdown,
        title: '代码块中文注释测试',
        isDark: false,
      );

      // PDF 基本验证
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46],
          reason: 'PDF 头必须是 %PDF');

      // P1 关键断言：PDF 应嵌入 TrueType 字体子集
      // 修复前：代码块用 Courier（无 CJK）→ 中文注释方框
      // 修复后：fontFallback: [cjkFont] → CJK 字符回退 NotoSansSC
      final pdfStr = String.fromCharCodes(bytes);
      expect(
        pdfStr.contains('/FontFile2') || pdfStr.contains('/FontFile3'),
        isTrue,
        reason: 'PDF 应嵌入 TrueType 字体子集（含 CJK fontFallback）',
      );

      // PDF 应足够大（含 CJK 字体子集 + 代码内容）
      expect(bytes.length, greaterThan(10000),
          reason: '含 CJK 代码注释的 PDF 应 > 10KB');
    });

    testWidgets('E2E-P1-7: Word 含代码块中文注释', (tester) async {
      const markdown = '''# Word 代码块中文测试

```python
# 中文注释
print("你好世界")
```
''';

      final bytes = await MarkdownExporter.exportToWord(
        markdown,
        title: 'Word代码中文测试',
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.sublist(0, 2), [0x50, 0x4B],
          reason: 'Word 头必须是 PK');
      expect(bytes.length, greaterThan(3000),
          reason: '含中文代码注释的 Word 应 > 3KB');
    });
  });

  group('P1 E2E: 问题2 — 返回按钮逻辑', () {
    testWidgets('E2E-P1-8: 编辑器 AppBar 有返回按钮', (tester) async {
      final path = await createTestDoc(
        title: 'p1-back-button',
        content: '测试返回',
      );
      await pumpEditorFromFile(tester, filePath: path);

      // 验证 AppBar 存在且有返回按钮
      expect(find.byType(AppBar), findsWidgets,
          reason: '编辑器应有 AppBar');

      // 查找返回箭头图标
      final backFinder = find.byTooltip('返回');
      expect(backFinder, findsOneWidget,
          reason: 'AppBar 应有"返回"按钮');
    });
  });
}