import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/blocks/shared/block_drag_handle.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/editor_shell.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';

/// T1-2 真实拖拽手势测试（Phase 3.5.5 / TEST_GAP_PLAN Tier 1）。
///
/// 与 block_interaction_test 的区别：不直接构造 MoveBlockCommand，
/// 而是驱动完整 UI 链路：
/// ReorderableDragStartListener（BlockDragHandle）→ ReorderableListView
/// → onReorderItem → blockReorderArgs → MoveBlockCommand → BlockOperations.move。
void main() {
  late EditorCoordinator coordinator;

  EditorCoordinator buildCoordinator() {
    final editor = InMemoryDocumentEditor(title: 'drag');
    editor.insertBlock(editor.blockCount,
        ParagraphElement(children: [TextElement('Alpha block')]));
    editor.insertBlock(editor.blockCount,
        ParagraphElement(children: [TextElement('Bravo block')]));
    editor.insertBlock(editor.blockCount,
        ParagraphElement(children: [TextElement('Charlie block')]));
    return EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
  }

  Future<void> pumpViewport(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditorScope(
            coordinator: coordinator,
            child: AnimatedBuilder(
              animation: coordinator,
              builder: (context, _) => EditorViewport(
                coordinator: coordinator,
                blockKeys: <BlockId, GlobalKey>{},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 从 [handleIndex] 的拖拽手柄开始拖动 [dy] 像素后松手。
  ///
  /// [ReorderableDragStartListener] 是立即识别（无需长按），但拖动
  /// 需分步 move + pump，让 ReorderableListView 的落点计算随位置更新。
  Future<void> dragHandleBy(
      WidgetTester tester, int handleIndex, double dy) async {
    final handle = find.byType(BlockDragHandle).at(handleIndex);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kPressTimeout);
    const steps = 6;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, dy / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  setUp(() {
    coordinator = buildCoordinator();
  });

  tearDown(() {
    coordinator.dispose();
  });

  testWidgets('拖拽手柄下移一格：[A,B,C] → [B,A,C]', (tester) async {
    await pumpViewport(tester);
    final ids = List<BlockId>.of(coordinator.allIds);

    // 拖动距离 = 单块高 * 0.8：跨过「A↔B 中点的下阈值(0.5h)」实现一次交换，
    // 但远未到「B↔C 中点的上阈值(1.5h)」，因此恰好下移一格而非越位。
    // （ReorderableListView 按相邻项中点判定落点，1.5h 会越过两个中点变成两次交换）
    final c0 = tester.getCenter(find.text('Alpha block'));
    final c1 = tester.getCenter(find.text('Bravo block'));
    final delta = (c1.dy - c0.dy) * 0.8;

    await dragHandleBy(tester, 0, delta);

    expect(coordinator.allIds, [ids[1], ids[0], ids[2]],
        reason: '首块经真实拖拽手势应移动到第二位');
  });

  testWidgets('拖拽手柄上移一格：[A,B,C] → [A,C,B]', (tester) async {
    await pumpViewport(tester);
    final ids = List<BlockId>.of(coordinator.allIds);

    final c1 = tester.getCenter(find.text('Bravo block'));
    final c2 = tester.getCenter(find.text('Charlie block'));
    final delta = -(c2.dy - c1.dy) * 0.8;

    await dragHandleBy(tester, 2, delta);

    expect(coordinator.allIds, [ids[0], ids[2], ids[1]],
        reason: '末块经真实拖拽手势应上移到第二位');
  });

  testWidgets('拖动后回到原位松手：顺序不变（不派发命令）', (tester) async {
    await pumpViewport(tester);
    final ids = List<BlockId>.of(coordinator.allIds);
    final undoBefore = coordinator.canUndo;

    final handle = find.byType(BlockDragHandle).at(0);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kPressTimeout);
    // 下移再回到原位
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(coordinator.allIds, ids, reason: '落点未变时顺序应保持');
    expect(coordinator.canUndo, undoBefore,
        reason: 'oldIndex == newIndex 时 blockReorderArgs 返回 null，不产生历史事务');
  });
}
