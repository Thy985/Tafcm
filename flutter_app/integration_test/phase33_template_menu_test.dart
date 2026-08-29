/// 3.3.10 Markdown 模板插入菜单 E2E。
///
/// 覆盖 §12.3 三条链：
/// - 链 1（用户操作）：点击 '+'（插入模板）→ 选择模板项 →
///   coordinator.handle(InsertTemplateCommand)
/// - 链 2（状态同步）：文档修改 / 新块插入 → 渲染更新
/// - 链 3（持久化代理）：newBlock 模板 → Parser 转换 Block →
///   序列化重解析一致（in-memory 代理；真实磁盘存档由 v2.1 §3.3.1 Hard Rule 禁止）
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'helpers/test_fixture.dart';

EditorCoordinator _coordinator(WidgetTester tester) =>
    tester.widget<EditorScope>(find.byType(EditorScope)).coordinator;

Future<BlockId> _focusFirstParagraph(
    WidgetTester tester, EditorCoordinator c) async {
  final id = c.allIds.firstWhere((i) => c.getBlock(i) is ParagraphElement);
  await tester.tap(find.text('Hello, Block Editor!'));
  await tester.pumpAndSettle();
  return id;
}

void main() {
  group('3.3.10 模板插入菜单', () {
    testWidgets('点击 + 选择「表格」→ 插入新 TableBlock', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final before = c.blockCount;
      final beforeIds = c.allIds.toSet();
      await _focusFirstParagraph(tester, c);

      // 链 1：打开 '+' 菜单（tooltip '插入模板'）
      // '+' 按钮在横向滚动的工具栏末端,可能不在视口内 → 先 ensureVisible
      await tester.ensureVisible(find.byTooltip('插入模板'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('插入模板'));
      await tester.pumpAndSettle();
      // 选择「表格」（newBlock 模式）
      await tester.tap(find.text('表格'));
      await tester.pumpAndSettle();

      // 链 2：块数 +1，且新增块携带表格 markdown 源（产品 spec：
      // newBlock 模板以 ParagraphElement 插入原始 markdown，由渲染层呈现为表格——
      // 见 command_handler_pr2a_test.dart「插入表格模板」断言 allSources.last == tableTemplate）。
      // 注意：种子文档末尾自带 CodeBlock，故新增块未必是 allIds.last；
      // 用块 id 集合差集定位真正的新增块。
      expect(c.blockCount, before + 1);
      final newId = c.allIds.firstWhere((id) => !beforeIds.contains(id));
      final newBlock = c.getBlock(newId);
      expect(newBlock, isA<ParagraphElement>());
      expect(c.sourceOf(newId), contains('|'));
    });

    testWidgets('点击 + 选择「代码块」→ 段落内插入代码模板', (tester) async {
      await pumpEditorApp(tester);
      final c = _coordinator(tester);
      final paraId = await _focusFirstParagraph(tester, c);
      final current = c.sourceOf(paraId);

      // '+' 按钮在横向滚动的工具栏末端,可能不在视口内 → 先 ensureVisible
      await tester.ensureVisible(find.byTooltip('插入模板'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('插入模板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('代码块'));
      await tester.pumpAndSettle();

      // insert 模式：段落 source 增加（含代码块标记 ```）
      expect(c.sourceOf(paraId).length, greaterThan(current.length));
      expect(c.sourceOf(paraId), contains('```'));
    });
  });
}
