/// 3.4.4 导出进度反馈 E2E（Phase 3.4 Slice 7 / PR #78）。
///
/// 覆盖：AppBar ios_share 按钮可展开 PDF/Word/TXT 三项
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_fixture.dart';

void main() {
  group('3.4.4 导出进度反馈', () {
    testWidgets('AppBar 导出菜单可见并含三项格式', (tester) async {
      await pumpEditorApp(tester, seedSelector: 0);

      expect(find.byIcon(Icons.ios_share), findsOneWidget);

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      expect(find.text('导出为 PDF'), findsOneWidget);
      expect(find.text('导出为 Word（.docx）'), findsOneWidget);
      expect(find.text('导出为 TXT'), findsOneWidget);
    });
  });
}
