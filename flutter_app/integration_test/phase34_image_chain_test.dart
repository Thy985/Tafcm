/// 3.4.9 图片全链路（用户旅程级，区别于旧 Feature Presence 仅断言工具栏按钮可见）。
///
/// 链路：打开 .md → 工具栏「插入模板」→ 图片项（经覆盖的 pickImage 注入固定相对
/// 路径，触发真实 [_handleInsertImage] 路径插入 `![](assets/img_e2e.png)`）→
/// 自动保存落盘 → 关闭重开 → 磁盘仍含图片 markdown 且渲染层把不可解析本地图
/// 回退为占位文本 `[图片]`。
///
/// 注：生产 [imagePickAndImportProvider] 值类型为 `Future<String?> Function()`
/// （不可为 null），故 headless 下真实 [ImagePicker] 返回 null/抛异常会被静默跳过，
/// 无法验证插入。E2E 通过覆盖 provider 注入固定路径，走真实插入路径。
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/presentation/chrome/toolbar_components.dart';

import 'helpers/test_fixture_file.dart';

void main() {
  group('3.4.9 图片全链路', () {
    testWidgets('工具栏插入图片→自动保存→重开内容保留并渲染', (tester) async {
      final path = await createTestDoc(
        title: '图片链',
        content: '# 标题\n\n这是一段包含图片的测试段落。\n',
      );

      // 注入固定图片路径，触发真实插入路径（headless 下真实 ImagePicker 不可用）。
      const stubPath = 'assets/img_e2e.png';
      await pumpEditorFromFile(
        tester,
        filePath: path,
        imagePicker: () async => stubPath,
      );

      // 聚焦段落块（设置 lastFocusedId，供模板插入定位）
      final paragraph = find.text('这是一段包含图片的测试段落。');
      expect(paragraph, findsWidgets);
      await tester.tap(paragraph);
      await tester.pumpAndSettle();

      // 窄屏下 toolbar 横向溢出：把 SingleChildScrollView 滚到最右，让最右侧的
      // TemplateMenuButton 进入可视区（否则 tester.tap 中心落屏外、菜单不弹）。
      // 从滚动视图左内边距（无按钮）起拖，避免落在 FormatButton 上被其手势消费。
      final scroller = find.ancestor(
        of: find.byType(TemplateMenuButton),
        matching: find.byType(SingleChildScrollView),
      );
      final svRect = tester.getRect(scroller);
      await tester.dragFrom(
        Offset(svRect.left + 4, svRect.center.dy),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();

      // 打开模板菜单。用 byType 直接定位按钮本体（render box 在屏内）。
      final menuBtn = find.byType(TemplateMenuButton);
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      // 菜单弹出有动画，等久一点确保 PopupMenuItem 已构建
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 菜单内「图片」项：find.text 为精确匹配，正文「包含图片的测试段落」不命中，
      // 仅命中菜单项 Text('图片')，无歧义。
      final imageItem = find.text('图片');
      expect(imageItem, findsWidgets);
      await tester.tap(imageItem.first);
      await tester.pumpAndSettle();

      // 等待自动保存防抖（1.5s）+ 余量
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // ---- 落盘断言：磁盘文件包含图片 markdown ----
      final disk1 = await io.File(path).readAsString();
      expect(disk1, contains('![](assets/img_e2e.png)'));

      // ---- 重开断言：关闭后重新打开，图片 markdown 仍在 ----
      await pumpEditorFromFile(
        tester,
        filePath: path,
        imagePicker: () async => stubPath,
      );
      // 等图片占位回退渲染（ImageElement → 占位 TextSpan）
      await tester.pumpAndSettle(const Duration(seconds: 2));
      final disk2 = await io.File(path).readAsString();
      expect(disk2, contains('![](assets/img_e2e.png)'));
      expect(tester.takeException(), isNull);

      // ---- 渲染断言：不可解析本地图回退为占位文本 [图片] ----
      // 注意：ParagraphBlock 把 ImageElement 渲染为 TextSpan（RichText 的一部分），
      // 不是独立 Text widget，故 find.text 无法命中。遍历 RichText 检查其
      // toPlainText() 是否包含占位符（空 alt → '[图片]'）。
      final hasImagePlaceholder = tester
          .widgetList<RichText>(find.byType(RichText))
          .any((rt) => rt.text.toPlainText().contains('[图片]'));
      expect(hasImagePlaceholder, isTrue);
    });
  });
}
