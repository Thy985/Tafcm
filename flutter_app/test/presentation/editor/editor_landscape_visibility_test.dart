/// #324 回归测试：横屏下正文内容块不可见。
///
/// **缺陷根因**（真机 Android 1080x2424 / density 420 实测复现）：
/// `EditorViewport` 内部 `Column` 的尾部「点击此处添加新块」点击区固定占
/// [kTailTapAreaHeight]（120px）。转横屏后编辑区可用高度从 713px 骤降到 203px，
/// 固定 120px 吃掉 59%，把可滚动的 [ReorderableListView] 压到 83px——
/// 不足一个标题块（48px）加内边距（24px）的高度。于是：
/// - 标题块恰好可见，「点击此处添加新块」提示紧跟其后（列的尾部固定区）；
/// - 其余正文块全部落在可视区之外；
/// - 列表总滚动范围仅 1.5px，用户感知为"滚动无效"。
///
/// 块数据本身完好（状态栏「块数 2」不变），转回竖屏立即恢复——纯布局问题。
///
/// **修复**：尾部点击区仅在将占编辑区一半以上（可用高度 < 2×120=240px）时
/// 按比例收缩，其余场景恒为 120px
/// （见 workspace.dart `kTailTapAreaShrinkThreshold`）。
///
/// **本文件覆盖**：多组块组合（标题 + 段落 / 列表 / 代码 / 公式 / 引用 / 表格）
/// 在横屏尺寸下的可见性，以及竖屏零回归。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/presentation/blocks/shared/block_selection.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/editor_shell.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';

/// 真机竖屏逻辑尺寸（411.4 x 923.4）。
const Size kPortraitSize = Size(411.4, 923.4);

/// 真机横屏逻辑尺寸（923.4 x 411.4）。
const Size kLandscapeSize = Size(923.4, 411.4);

/// 真机系统栏 inset（真机实测值）。
///
/// **必须模拟**：真机横屏时状态栏挪到左侧（left 54.1），顶部因刘海/挖孔仍有
/// 52.2，底部导航条 24。缺了这层 inset，测试里的 body 会比真机高 76px，
/// 修复前列表仍有 ~159px > 120px，缺陷根本复现不出来（测试会假通过）。
const EdgeInsets kPortraitInset = EdgeInsets.only(top: 54.1, bottom: 24);
const EdgeInsets kLandscapeInset =
    EdgeInsets.only(left: 54.1, top: 52.2, bottom: 24);

/// 测试用块组合：标题 + 各类正文块，覆盖 #324 报告中的段落场景及其变体。
const Map<String, List<Object>> kCombos = {
  'heading+paragraph': ['# Title', r'X $a^2+b^2$ Y'],
  'heading+list': ['# Title', '- alpha\n- beta'],
  'heading+code': ['# Title', '```dart\nvoid main() {}\n```'],
  'heading+formula': ['# Title', r'$$a^2+b^2=c^2$$'],
  'heading+blockquote': ['# Title', '> quoted text'],
  'heading+table': ['# Title', '| a | b |\n|---|---|\n| 1 | 2 |'],
};

/// 构造 [BlockType]：首块为标题，其余按 [BlockType.code] 之外的常见类型映射。
BlockType _typeFor(int index) {
  if (index == 0) return BlockType.heading;
  return const [
    BlockType.paragraph,
    BlockType.listItem,
    BlockType.code,
    BlockType.paragraph,
    BlockType.blockquote,
    BlockType.table,
  ][index - 1];
}

/// 在指定逻辑尺寸下挂载 [EditorShell]，文档为「标题 + 第二块」两段内容。
Future<EditorCoordinator> _pumpShell(
  WidgetTester tester,
  Size size,
  EdgeInsets inset,
  List<Object> content,
) async {
  final editor = InMemoryDocumentEditor(title: 'T');
  for (var i = 0; i < content.length; i++) {
    editor.addBlock(content[i] as String, _typeFor(i));
  }
  final coordinator = EditorCoordinator(
    editor: editor,
    history: EditorHistory(maxHistorySize: 200),
  );

  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(
    top: inset.top,
    bottom: inset.bottom,
    left: inset.left,
    right: inset.right,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: inset.top,
    bottom: inset.bottom,
    left: inset.left,
    right: inset.right,
  );
  addTearDown(tester.view.reset);
  // AGENTS.md §3.4：EditorCoordinator 持有变更通知流与 undo/redo 历史，
  // 与本文件 pumpViewport 的清理行为保持一致（PR #348 评审）。
  addTearDown(coordinator.dispose);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.themeFor(AppThemeMode.light),
        home: EditorScope(
          coordinator: coordinator,
          child: EditorShell(coordinator: coordinator),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return coordinator;
}

/// [ReorderableListView]（块列表）当前的渲染高度。
double _listHeight(WidgetTester tester) =>
    tester.renderObject<RenderBox>(find.byType(ReorderableListView)).size.height;

/// 与列表视口 [Rect] 有交集的块数量（= 用户实际能看到的块数）。
int _visibleBlockCount(WidgetTester tester) {
  final viewport = tester.getRect(find.byType(ReorderableListView));
  var count = 0;
  for (final element in find
      .descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(BlockSelectionChrome),
      )
      .evaluate()) {
    final box = element.findRenderObject() as RenderBox?;
    if (box == null) continue;
    if ((box.localToGlobal(Offset.zero) & box.size).overlaps(viewport)) {
      count++;
    }
  }
  return count;
}

/// 尾部「点击此处添加新块」点击区的实际渲染高度。
///
/// 直接找该提示 [Text] 的祖先 [SizedBox]——不能用 `find.byType(SizedBox).last`
/// （会命中骨架树里更靠后的无关键）。
double _tailHeight(WidgetTester tester) {
  final sizedBox = find
      .ancestor(
        of: find.text('点击此处添加新块'),
        matching: find.byType(SizedBox),
      )
      .evaluate();
  expect(sizedBox, isNotEmpty, reason: '应能找到尾部点击区的 SizedBox');
  return (sizedBox.first.findRenderObject() as RenderBox).size.height;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const <String, Object>{}));

  group('#324 横屏块可见性', () {
    // 每种块组合在横屏下第二个块都必须落在列表视口内。
    for (final entry in kCombos.entries) {
      testWidgets('横屏下 ${entry.key} 的正文块可见', (tester) async {
        await _pumpShell(tester, kLandscapeSize, kLandscapeInset, entry.value);

        // 回归点：横屏编辑区总高约 203px。若尾部点击区仍固定 120px，
        // 列表会被压到 ~83px（< 标题块 48px + 内边距 24px），正文块不可见。
        final listHeight = _listHeight(tester);
        expect(
          listHeight,
          greaterThan(120),
          reason: '横屏下块列表高度应大于一个标题块的高度，'
              '否则正文块会落在可视区外（#324）',
        );

        expect(
          _visibleBlockCount(tester),
          2,
          reason: '${entry.key}：标题与正文块都应与列表视口相交',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('横屏下长文档可滚动（滚动范围非退化）', (tester) async {
      // 内容高度需超过横屏下的列表高度，滚动范围才为正。
      // #324 修复前列表仅 83px，即便两行短文本也几乎无滚动余量（实测 1.5px）。
      await _pumpShell(
        tester,
        kLandscapeSize,
        kLandscapeInset,
        const [
          '# Title',
          'line one of the body paragraph\n'
              'line two of the body paragraph\n'
              'line three of the body paragraph\n'
              'line four of the body paragraph',
        ],
      );

      final scrollable = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(
        position.maxScrollExtent,
        greaterThan(20),
        reason: '#324：修复前横屏滚动范围仅 1.5px，表现为"滚动无效"',
      );
    });
  });

  group('#324 竖屏零回归', () {
    testWidgets('竖屏下尾部点击区仍为完整 120px', (tester) async {
      await _pumpShell(
        tester,
        kPortraitSize,
        kPortraitInset,
        const ['# Title', r'X $a^2+b^2$ Y'],
      );

      final tail = _tailHeight(tester);
      expect(
        tail,
        120.0,
        reason: '竖屏编辑区高度充足，尾部「点击此处添加新块」点击区必须保持 120px，'
            '确保竖屏像素级不变',
      );
      expect(find.text('点击此处添加新块'), findsOneWidget);
    });

    testWidgets('竖屏下两块均可见且无异常', (tester) async {
      await _pumpShell(
        tester,
        kPortraitSize,
        kPortraitInset,
        const ['# Title', r'X $a^2+b^2$ Y'],
      );

      expect(_visibleBlockCount(tester), 2);
      expect(find.text('点击此处添加新块'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('#324 尾部收缩阈值（golden 基线保护）', () {
    // CI Golden(compare) 实证（PR #348 首跑失败）：golden
    // editor_shell_full_page_* 的编辑视口 maxHeight ≈ 474px，若 0.25 比例
    // 无条件生效，尾部高度变为 118.6px，提示文字整体下移 ~1.4px（topCenter
    // 锚定），整页基线产生 5610px 像素差。回归点：阈值（2×120=240px）之上
    // 尾部必须恒为 120px，golden 像素级不变。
    Future<void> pumpViewport(WidgetTester tester, double height) async {
      final editor = InMemoryDocumentEditor(title: 'T');
      editor.addBlock('# Title', BlockType.heading);
      final coordinator = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 200),
      );
      addTearDown(coordinator.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.themeFor(AppThemeMode.light),
            home: Scaffold(
              body: EditorScope(
                coordinator: coordinator,
                child: SizedBox(
                  height: height,
                  // 不能传 const/unmodifiable map：_buildViewport 会原地
                  // 修剪孤儿 GlobalKey（removeWhere / putIfAbsent）。
                  child: EditorViewport(
                    coordinator: coordinator,
                    // 不能传 const/unmodifiable map：_buildViewport 会原地
                    // 修剪孤儿 GlobalKey（removeWhere / putIfAbsent）。
                    // ignore: prefer_const_literals_to_create_immutables
                    blockKeys: <BlockId, GlobalKey>{},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('视口 500px（≥ 阈值 240）尾部恒为 120px', (tester) async {
      await pumpViewport(tester, 500);
      expect(_tailHeight(tester), 120.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('视口 474px（golden 实测区间）尾部仍为 120px', (tester) async {
      await pumpViewport(tester, 474);
      expect(_tailHeight(tester), 120.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('视口 203px（真机横屏区间）尾部按 0.25 比例收缩', (tester) async {
      await pumpViewport(tester, 203);
      expect(_tailHeight(tester), closeTo(203 * 0.25, 0.01));
      expect(tester.takeException(), isNull);
    });
  });
}
