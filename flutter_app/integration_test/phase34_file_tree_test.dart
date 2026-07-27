/// 3.4.2 文件树侧栏 E2E（Phase 3.4 Slice 6 / PR #77）。
///
/// 覆盖：AppBar 文件树按钮 toggle FileTreePanel 出现/消失
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_fixture.dart';

void main() {
  group('3.4.2 文件树侧栏', () {
    testWidgets('AppBar 文件树按钮切换面板出现/消失', (tester) async {
      await pumpEditorApp(tester, seedSelector: 0);

      expect(find.text('文件'), findsNothing);

      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      expect(find.text('文件'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      expect(find.text('文件'), findsNothing);
    });
  });
}
