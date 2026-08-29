/// T3-1 块交互 E2E（Tier 3）。
///
/// 覆盖真实设备交互链路：长按手柄拖动重排 → 顺序断言；tap 选中（无 hover，依赖
/// T1-1 修复）→ 工具栏出现 → 点删除/转换 → 文档变化。
///
/// 运行：Android 模拟器 `flutter test integration_test/phase35_block_interaction_test.dart`
/// （CI 不跑 integration_test，结果作为手动门禁记入 verification report）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/presentation/blocks/shared/block_drag_handle.dart';
import 'package:tafcm/presentation/blocks/shared/block_toolbar.dart';
import 'helpers/test_fixture_file.dart';

void main() {
  group('T3-1 block interaction E2E', () {
    testWidgets('长按手柄拖动重排 → 块顺序变化', (tester) async {
      final path = await createTestDoc(
        title: 'reorder',
        content: '块甲\n\n块乙\n\n块丙',
      );
      await pumpEditorFromFile(tester, filePath: path);

      // 初始顺序：甲 在 乙 上方
      final topJia0 = tester.getTopLeft(find.text('块甲')).dy;
      final topYi0 = tester.getTopLeft(find.text('块乙')).dy;
      expect(topJia0, lessThan(topYi0), reason: '初始 甲 应在 乙 上方');

      // 拖拽第一块的拖拽手柄向下越过一块
      final handle = find.byType(BlockDragHandle).at(0);
      final center = tester.getCenter(handle);
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 500)); // ReorderableDragStartListener 长按时延触发拖拽
      await gesture.moveBy(const Offset(0, 220));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // 重排后：甲 应在 乙 下方
      final topJia1 = tester.getTopLeft(find.text('块甲')).dy;
      final topYi1 = tester.getTopLeft(find.text('块乙')).dy;
      expect(topJia1, greaterThan(topYi1), reason: '重排后 甲 应在 乙 下方');
    });

    testWidgets('tap 选中（无 hover）→ BlockToolbar 可见（T1-1 修复）', (tester) async {
      final path = await createTestDoc(
        title: 'select',
        content: '块甲\n\n块乙',
      );
      await pumpEditorFromFile(tester, filePath: path);

      // 手机没有 hover，只能靠 tap 选中
      await tester.tap(find.text('块甲'));
      await tester.pumpAndSettle();

      // 触屏路径下工具栏应可见
      expect(find.byType(BlockToolbar), findsWidgets,
          reason: 'tap 选中后 BlockToolbar 应出现（不依赖 hover）');
    });

    testWidgets('点删除 → 块从文档移除', (tester) async {
      final path = await createTestDoc(
        title: 'delete',
        content: '块甲\n\n块乙',
      );
      await pumpEditorFromFile(tester, filePath: path);

      await tester.tap(find.text('块甲'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除'));
      await tester.pumpAndSettle();

      expect(find.text('块甲'), findsNothing, reason: '删除后 块甲 应消失');
      expect(find.text('块乙'), findsWidgets, reason: '块乙 应保留');
    });

    testWidgets('点转换类型 → 菜单展开可触达（无 hover，T1-1 修复）', (tester) async {
      final path = await createTestDoc(
        title: 'convert',
        content: '块甲\n\n块乙',
      );
      await pumpEditorFromFile(tester, filePath: path);

      await tester.tap(find.text('块甲'));
      await tester.pumpAndSettle();
      // 触屏无 hover：靠 tap 选中后点"转换类型"展开菜单
      await tester.tap(find.byTooltip('转换类型'));
      await tester.pumpAndSettle();

      // 菜单露出三种目标类型（正文 / 标题 / 引用），证明转换入口在触屏可达。
      // 实际“选目标 → 改源”的执行链由 unit 测试覆盖（block_convert T1-4
      // applyBlockPrefix：段落→标题加 `# `、→引用加 `> `），headless
      // integration_test 下 PopupMenuItem 的 onSelected 命中为已知 harness 限制，
      // 完整 item-select→transform 留作 Tier 4 真机人工验收。
      expect(find.text('正文'), findsWidgets, reason: '转换菜单应含“正文”');
      expect(find.text('标题'), findsWidgets, reason: '转换菜单应含“标题”');
      expect(find.text('引用'), findsWidgets, reason: '转换菜单应含“引用”');

      // 收起菜单（菜单打开时工具条 convert 按钮已隐藏，改为点击 ModalBarrier）
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });
  });
}
