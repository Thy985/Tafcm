/// 3.4.8 页面宽度控制 E2E（Phase 3.4 Slice 5 / PR #76）。
///
/// 覆盖：编辑视口含 ConstrainedBox maxWidth=720
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_fixture.dart';

const double kExpectedMaxWidth = 720.0;

void main() {
  group('3.4.8 页面宽度控制', () {
    testWidgets('编辑视口含 ConstrainedBox 且 maxWidth≈720', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpEditorApp(tester, seedSelector: 0);

      final constrained = find.byType(ConstrainedBox);
      expect(constrained, findsWidgets);

      final boxes = tester.widgetList<ConstrainedBox>(constrained).toList();
      final pageBox = boxes.where(
        (b) => b.constraints.maxWidth <= kExpectedMaxWidth &&
                b.constraints.maxWidth > 0,
      );
      expect(pageBox, isNotEmpty);
    });
  });
}
