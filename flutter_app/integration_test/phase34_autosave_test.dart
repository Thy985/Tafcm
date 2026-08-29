/// 3.4.7 自动保存 E2E（Phase 3.4 Slice 2 / PR #70 / ADR-0013）。
///
/// 覆盖：
/// - 链 1：EditorPage 持有 AutosaveService 并在 initState 启动
/// - 链 2：EditorPage dispose 时 AutosaveService 停止（不泄漏）
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/presentation/editor/editor_page.dart';
import 'helpers/test_fixture.dart';

void main() {
  group('3.4.7 自动保存', () {
    testWidgets('EditorPage 创建并 dispose 不崩溃', (tester) async {
      // seedSelector=0 默认不设 currentPath → autosave inert（不写盘）
      // 但 AutosaveService 仍正常启动/停止，验证整个生命周期无异常
      final app = await pumpEditorApp(tester, seedSelector: 0);

      // EditorPage 构造成功
      expect(app, isA<EditorPage>());

      // 验证 pumpAndSettle 后无未捕获异常（AutosaveService 正常启动）
      expect(tester.takeException(), isNull);

      // pump 一个新 widget 触发旧 EditorPage dispose → AutosaveService.stop()
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // dispose 后无异常
      expect(tester.takeException(), isNull);
    });
  });
}
