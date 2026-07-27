/// 3.4.9 图片插入 E2E（Phase 3.4 Slice 4 / PR #75 / ADR-0014）。
///
/// 覆盖：工具栏图片按钮可见 + 模板菜单展开
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_fixture.dart';

void main() {
  group('3.4.9 图片插入', () {
    testWidgets('工具栏含图片按钮且点击弹出模板菜单', (tester) async {
      await pumpEditorApp(tester, seedSelector: 0);

      expect(find.byIcon(Icons.image), findsOneWidget);

      await tester.tap(find.byIcon(Icons.image));
      await tester.pumpAndSettle();

      expect(find.textContaining('图片'), findsAny);
    });
  });
}
