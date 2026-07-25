/// 3.4.1 TOC 大纲面板 E2E（Phase 3.4 纯 UI / 导航，豁免链 3 持久化）。
///
/// 覆盖 §12.3 链 1（用户操作：点击目录图标 → 抽屉打开 → 点击条目）
/// 与链 2（状态同步：coordinator.focusedId 变为目标标题块）。
///
/// 平台：本测试在 Android Emulator 跑（见 Phase 3.4 Task Contract §4.4 平台矩阵）。
library;

import 'package:flutter/material.dart' show Icons, Key;
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'helpers/test_fixture.dart';

/// 从 widget 树取出真实 [EditorCoordinator]（UI 绑定的同一实例）。
EditorCoordinator _coordinator(WidgetTester tester) =>
    tester.widget<EditorScope>(find.byType(EditorScope)).coordinator;

void main() {
  group('3.4.1 TOC 大纲面板', () {
    testWidgets('点击目录图标打开抽屉，列出标题，点击跳转聚焦', (tester) async {
      // seedSelector=1 载入 demo2（标题层级示例，含 3 个标题）
      await pumpEditorApp(tester, seedSelector: 1);
      final c = _coordinator(tester);

      // 文档含至少一个标题块
      final headingIds = c.allIds
          .where((id) => c.getBlock(id) is HeadingElement)
          .toList();
      expect(headingIds, isNotEmpty);

      // 打开目录抽屉
      await tester.tap(find.byIcon(Icons.list_alt));
      await tester.pumpAndSettle();

      // 抽屉标题「目录」可见
      expect(find.text('目录'), findsWidgets);

      // 取首个标题块 id，点击其 TOC 条目（key = 'toc_<BlockId>'）
      final targetId = headingIds.first;
      await tester.tap(find.byKey(Key('toc_$targetId')));
      await tester.pumpAndSettle();

      // 链 2：点击后 coordinator 聚焦了目标标题块（跳转生效）
      expect(c.focusedId, targetId);
    });
  });
}
