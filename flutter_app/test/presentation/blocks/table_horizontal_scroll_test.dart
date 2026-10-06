/// #328 回归：表格横向滚动 + 慢速滑动不被长按选中打断。
///
/// **缺陷证据**（QA 2026-10-04 实拍 `.wt/qa-shots/features/31/32`）：超宽
/// 表格横滑时，BlockSelectionChrome 的 500ms 长按计时器在滑动途中触发——
/// 块选中、工具条弹出、块状态重建打断横滚手势；滑动前后表格滚动位置不变。
///
/// **修复语义**（本文件固化）：
/// - 手指移动超过 touch slop = 滑动 → 长按计时取消，横滑只滚动表格、
///   不触发选中/工具条；
/// - 静止触摸 ≥500ms 仍是长按 → 选中工具条照常弹出（原行为保留）；
/// - 表格横向滚动能力（既有 SingleChildScrollView）在快速横滑下生效。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/blocks/shared/block_toolbar.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/editor/workspace.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';

/// 首列长文本：让表格固有宽度远超视口（IntrinsicColumnWidth 不换行）。
const String _kLongCellText =
    '长单元格内容测试：这一列故意放很长的文字看看是否会撑出去屏幕右侧'
    '边界之外导致完全不可见见见见见见见见见见见见见见见见见见';

Future<EditorCoordinator> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final editor = InMemoryDocumentEditor(title: 't');
  editor.insertBlock(
    editor.blockCount,
    TableElement(
      headers: [
        [TextElement(_kLongCellText)],
        [TextElement('状态列')],
      ],
      rows: [
        [
          [TextElement('a')],
          [TextElement('b')],
        ],
      ],
    ),
  );
  final coordinator = EditorCoordinator(
    editor: editor,
    history: EditorHistory(maxHistorySize: 50),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: EditorScope(
          coordinator: coordinator,
          child: Workspace(coordinator: coordinator, blockKeys: {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return coordinator;
}

/// 表格横向 Scrollable（视口内第二个 Scrollable：第一个是纵向块列表）。
ScrollableState _tableHorizontalScrollable(WidgetTester tester) {
  final scrollables = find
      .byType(Scrollable)
      .evaluate()
      .map((e) => e as StatefulElement)
      .map((e) => e.state as ScrollableState)
      .where((s) => s.position.axis == Axis.horizontal)
      .toList();
  expect(scrollables, isNotEmpty, reason: '表格应包含横向 Scrollable');
  return scrollables.first;
}

/// 表格可视区内的一个起始点（表格可能超宽，取其可视矩形左侧）。
Offset _dragStart(WidgetTester tester) {
  final tableRect = tester.getRect(find.byType(Table).first);
  return Offset(tableRect.left + 150, tableRect.center.dy);
}

void main() {
  testWidgets('快速横滑 → 表格滚动，无选中工具条', (tester) async {
    final coordinator = await _pumpShell(tester);
    final start = _dragStart(tester);

    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(-280, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    final table = _tableHorizontalScrollable(tester);
    expect(table.position.pixels, greaterThan(0),
        reason: '#328：横滑后表格必须滚动（右侧列可达）');
    expect(
      coordinator.viewStateOf(coordinator.allIds.first)?.longPressed ?? false,
      isFalse,
      reason: '滑动不是长按——不得触发选中',
    );
    expect(find.byType(BlockToolbar), findsNothing);
  });

  testWidgets('慢速横滑（>500ms，会撞上旧长按计时器）→ 表格滚动且不触发选中',
      (tester) async {
    final coordinator = await _pumpShell(tester);
    final start = _dragStart(tester);

    // 总时长 600ms 的慢速横滑：旧实现的 500ms 计时器会在滑动途中触发
    // （QA 实测的工具条弹出即此机制），修复后必须被移动判定取消。
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final table = _tableHorizontalScrollable(tester);
    expect(table.position.pixels, greaterThan(0),
        reason: '#328：慢速横滑也必须滚动（旧版在此场景被长按选中打断）');
    expect(
      coordinator.viewStateOf(coordinator.allIds.first)?.longPressed ?? false,
      isFalse,
      reason: '#328：移动超过 touch slop 即为滑动，不得触发长按选中',
    );
    expect(find.byType(BlockToolbar), findsNothing,
        reason: '#328：滑动途中不得弹出块工具条（QA 实拍证据 31/32）');
  });

  testWidgets('静止触摸 ≥500ms → 长按选中工具条照常弹出（原行为保留）',
      (tester) async {
    await _pumpShell(tester);
    final start = _dragStart(tester);

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(BlockToolbar), findsOneWidget,
        reason: '长按选中是既有交互基线，不得回归');
  });
}
