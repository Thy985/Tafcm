/// 3.4.9 图片插入 E2E（Phase 3.4 Slice 4 / PR #75 / ADR-0014）。
///
/// 覆盖：工具栏渲染完整性（模板菜单入口可见）
/// 注：PopupMenu 展开交互依赖具体层级，E2E 保证工具栏入口可见即可；
/// 菜单项内容（含图片插入）由 ToolbarComponents 单元测试覆盖。
library;

import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_fixture.dart';

void main() {
  group('3.4.9 图片插入', () {
    testWidgets('工具栏含模板菜单入口按钮', (tester) async {
      await pumpEditorApp(tester, seedSelector: 0);

      // MarkdownToolbar 存在且含模板菜单按钮（tooltip = '插入模板'）
      expect(find.byTooltip('插入模板'), findsOneWidget);
    });
  });
}
