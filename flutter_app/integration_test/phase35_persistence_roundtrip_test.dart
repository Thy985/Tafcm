/// T3-3 持久化 round-trip E2E（Tier 3）。
///
/// 编辑含 $$ 公式 + 表格 + 代码块的文档 → autosave → 重启 app → 重新打开 →
/// AST 与渲染一致（对应 Release Gate G6）。
///
/// 运行：Android 模拟器 `flutter test integration_test/phase35_persistence_roundtrip_test.dart`
/// （CI 不跑 integration_test，结果作为手动门禁记入 verification report）。
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/presentation/blocks/code/code_block.dart';
import 'helpers/test_fixture_file.dart';

void main() {
  group('T3-3 persistence round-trip E2E', () {
    testWidgets('含公式+表格+代码块的文档 autosave→重启→重开 一致', (tester) async {
      const content = r'''
# 标题

这是正文段落，用于编辑验证。

$$E = mc^2$$

| 列A | 列B |
|---|---|
| 1 | 2 |

```dart
void main() {
  print('hi');
}
```
''';
      final path = await createTestDoc(title: 'roundtrip', content: content);
      await pumpEditorFromFile(tester, filePath: path);

      // 初次渲染断言
      final hasFormula = find.byType(SvgPicture).evaluate().isNotEmpty ||
          find.byType(Math).evaluate().isNotEmpty;
      expect(hasFormula, isTrue, reason: '公式应渲染（SVG 或 fallback）');
      expect(find.text('列A'), findsWidgets, reason: '表格应渲染');
      expect(find.text('列B'), findsWidgets, reason: '表格单元格应渲染');
      // 代码块在文档底部，可能懒加载未构建 → 滚动到底部使其可见
      await tester.fling(
          find.byType(Scrollable).first, const Offset(0, -800), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(CodeBlock), findsWidgets, reason: '代码块应渲染');

      // 滚回顶部，使正文段落重新进入视口
      await tester.fling(
          find.byType(Scrollable).first, const Offset(0, 800), 1000);
      await tester.pumpAndSettle();

      // 编辑正文段落
      await tester.tap(find.text('这是正文段落，用于编辑验证。'));
      await tester.pumpAndSettle();
      final bodyField = find.ancestor(
        of: find.text('这是正文段落，用于编辑验证。'),
        matching: find.byType(TextField),
      );
      await tester.enterText(bodyField, '这是（已编辑）正文段落。');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 等 autosave（debounce 1.5s）+ 落盘
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final onDisk = await io.File(path).readAsString();
      expect(onDisk, contains('已编辑'), reason: '编辑应已落盘');

      // 模拟关 App
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final onDisk2 = await io.File(path).readAsString();
      debugPrint('T3-3 reopen disk content:\n$onDisk2');

      // 重新打开同一文件
      await pumpEditorFromFile(tester, filePath: path);

      // 重开后渲染一致（轮询等待异步加载）
      var found = false;
      for (var i = 0; i < 12 && !found; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        found = find.textContaining('已编辑').evaluate().isNotEmpty;
      }
      if (!found) {
        final texts = find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .toList();
        debugPrint('T3-3 reopen visible texts: $texts');
      }
      expect(found, isTrue, reason: '编辑内容应保留');
      final hasFormula2 = find.byType(SvgPicture).evaluate().isNotEmpty ||
          find.byType(Math).evaluate().isNotEmpty;
      expect(hasFormula2, isTrue, reason: '公式重开后应仍在');
      expect(find.text('列A'), findsWidgets, reason: '表格重开后应仍在');
      // 滚动到底部使代码块可见后再断言
      await tester.fling(
          find.byType(Scrollable).first, const Offset(0, -800), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(CodeBlock), findsWidgets, reason: '代码块重开后应仍在');
    });

    testWidgets('公式在 autosave 中序列化为 \$\$...\$ 不丢', (tester) async {
      const content = '# 公式文档\n\n'
          r'$$E = mc^2$$';
      final path = await createTestDoc(title: 'rt2', content: content);
      await pumpEditorFromFile(tester, filePath: path);

      // 触发一次编辑以驱动 autosave（仅编辑标题，不触动公式块）。
      // 注意：chrome（如状态栏/标题栏）里也有同文案 Text（带 ellipsis），
      // 用 overflow 谓词锁定编辑器内的标题 Text。
      final headingText = find.byWidgetPredicate((w) =>
          w is Text && w.data == '公式文档' && w.overflow != TextOverflow.ellipsis);
      await tester.tap(headingText.first);
      await tester.pumpAndSettle();
      // 聚焦后标题块进入编辑态：Text 被替换为含源码 `# 公式文档` 的 TextField，
      // 因此不能再用 ancestor(of: Text)，直接按 controller 文本谓词定位。
      final headingField = find.byWidgetPredicate((w) =>
          w is TextField && (w.controller?.text.contains('公式文档') ?? false));
      expect(headingField, findsOneWidget, reason: '标题编辑框应聚焦');
      final srcText =
          (tester.widget<TextField>(headingField)).controller!.text;
      // 保留标题前缀（如 `# `），只在末尾追加，避免块类型被降级
      await tester.enterText(headingField, '$srcText（已编辑）');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final onDisk = await io.File(path).readAsString();
      expect(onDisk, contains('E = mc^2'),
          reason: '公式 LaTeX 应在 autosave 中保留');
    });
  });
}
