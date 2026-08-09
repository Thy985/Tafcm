import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_intent.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/editor/workspace.dart';
import 'package:formula_fix/presentation/states/block_view_state.dart';
import 'package:formula_fix/presentation/theme/app_theme.dart';

/// 真机 P0 回归（phase3.5-realdevice-issues.md）：
/// - #1 回车分块 / 即点即插（AS-1.1 / AS-1.2 / AS-1.3）
/// - #4 工具栏格式命令不复活已删文本（AS-4.1~4.5）
///
/// 全部经 [EditorCoordinator.dispatch]（ADR-0019 Intent Layer）验证，
/// 不再走 `onSubmitted` 错误路径。回车真机软键盘路径（TextInputFormatter 拦截
/// `\n`）须真机 E2E 回归（AS-I.1），此处验证 dispatcher→resolver→command 接线。
void main() {
  late EditorCoordinator coordinator;

  EditorCoordinator _buildCoordinator(
      {bool withCode = false, bool twoParagraphs = false}) {
    final editor = InMemoryDocumentEditor(title: 't');
    editor.insertBlock(editor.blockCount,
        ParagraphElement(children: [TextElement('Para 1')]));
    if (twoParagraphs) {
      editor.insertBlock(editor.blockCount,
          ParagraphElement(children: [TextElement('Para 2')]));
    }
    if (withCode) {
      editor.insertBlock(editor.blockCount,
          const CodeElement(code: 'x=1', language: 'py'));
    }
    return EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
  }

  Future<void> _pump(WidgetTester tester) async {
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

  setUp(() => coordinator = _buildCoordinator());
  tearDown(() => coordinator.dispose());

  // AS-1.1 / AS-1.2：经 dispatcher 派发 EnterPressedIntent → resolver → command。
  // 非空段落回车 → SplitBlockCommand（分块），P0 修复（2026-08-09）真机问题 5。
  testWidgets('EnterPressedIntent 非空段落回车分块（#1 经 dispatcher）',
      (tester) async {
    await _pump(tester);
    final first = coordinator.allIds.first;
    final before = coordinator.blockCount;
    final offset = coordinator.sourceOf(first).length;

    coordinator.intents.dispatch(EnterPressedIntent(
      first,
      TextSelection.collapsed(offset: offset),
    ));
    await tester.pumpAndSettle();

    expect(coordinator.blockCount, before + 1, reason: '非空段落回车分块');
    expect(coordinator.focusedId, coordinator.allIds.last,
        reason: '焦点移到新块');
  });

  // AS-1.3：点击尾部空白区追加新块（gesture → appendBlock）
  testWidgets('点击工作区尾部空白追加新块（#1 即点即插）', (tester) async {
    await _pump(tester);
    final before = coordinator.blockCount;
    await tester.tap(find.text('点击此处添加新块'));
    await tester.pumpAndSettle();
    expect(coordinator.blockCount, before + 1);
    expect(coordinator.focusedId, coordinator.allIds.last);
  });

  // Code 块回车：块内换行（AS-I.4），不分块
  testWidgets('Code 块 Enter 块内换行不分块', (tester) async {
    coordinator = _buildCoordinator(withCode: true);
    await _pump(tester);
    final codeId = coordinator.allIds.last;
    final before = coordinator.blockCount;

    coordinator.intents.dispatch(EnterPressedIntent(
      codeId,
      const TextSelection.collapsed(offset: 1),
    ));
    await tester.pumpAndSettle();

    expect(coordinator.blockCount, before, reason: '代码块内换行不分块');
    expect(coordinator.sourceOf(codeId), contains('\n'));
  });

  // 块首退格合并（§4.1）
  testWidgets('块首退格合并上一块并聚焦连接点', (tester) async {
    coordinator = _buildCoordinator(twoParagraphs: true);
    await _pump(tester);
    final second = coordinator.allIds[1];
    final first = coordinator.allIds[0];
    final before = coordinator.blockCount;

    coordinator.intents.dispatch(DeleteIntent(
      second,
      true,
      const TextSelection.collapsed(offset: 0),
    ));
    await tester.pumpAndSettle();

    expect(coordinator.blockCount, before - 1, reason: '合并后少一块');
    expect(coordinator.focusedId, first, reason: '焦点移到合并后的上一块');
  });

  // AS-4.4：删除后未提交，格式命令经 dispatcher 不应复活已删文本
  testWidgets('工具栏格式命令经 dispatcher 不复活已删文本（#4）', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'flush');
    editor.addParagraph('abcdef');
    coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
    final id = coordinator.allIds.first;
    coordinator.setFocus(id);
    coordinator.updateViewState(
      id,
      BlockViewState(id: id, selection: const TextSelection(baseOffset: 0, extentOffset: 3)),
    );

    // 模拟「输入 abcdef → 删除 cde → 立即点 B」：删除只更新 live 层
    coordinator.updateLiveSource(id, 'abf');
    expect(coordinator.sourceOf(id), 'abcdef', reason: 'domain 尚未提交');

    // 经 dispatcher 派发加粗：内部先 flush live→domain，再包裹当前真实文本
    coordinator.intents.dispatch(ToolbarActionIntent(
      id,
      ToolbarActionKind.bold,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    ));

    expect(coordinator.sourceOf(id), '**abf**');
    expect(coordinator.sourceOf(id), isNot(contains('cde')));
  });
}
