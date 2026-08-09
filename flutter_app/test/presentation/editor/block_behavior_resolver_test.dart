import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/editor/block_behavior_resolver.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_intent.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/commands/commands.dart';

/// [BlockBehaviorResolver] 纯单测（规范 §3 / §4.1 / §4.4 + ADR-0019）。
///
/// 验证 Intent → Command 的唯一裁决点：所有行为映射集中在 resolver.switch，
/// 不依赖任何 Block 子类。这是 per-block 写法（被否决）的对照基准。
void main() {
  late EditorCoordinator coordinator;
  late BlockBehaviorResolver resolver;
  late BlockId paraId;
  late BlockId headingId;
  late BlockId codeId;

  setUp(() {
    final editor = InMemoryDocumentEditor(title: 'resolver');
    editor.insertBlock(editor.blockCount,
        ParagraphElement(children: [TextElement('hello')]));
    editor.insertBlock(editor.blockCount,
        const HeadingElement(level: 1, text: 'title'));
    editor.insertBlock(editor.blockCount,
        const CodeElement(code: 'x=1', language: 'py'));
    coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );
    resolver = const BlockBehaviorResolver();
    paraId = coordinator.allIds[0];
    headingId = coordinator.allIds[1];
    codeId = coordinator.allIds[2];
  });

  tearDown(() => coordinator.dispose());

  group('Enter 矩阵（§3）', () {
    test('Paragraph（非空）→ SplitBlockCommand（回车分块，Typora 语义）', () {
      final cmd = resolver.resolveEnter(
          coordinator, paraId, const TextSelection.collapsed(offset: 3));
      expect(cmd, isA<SplitBlockCommand>());
    });

    test('Paragraph（空块）→ SplitBlockCommand（空行 Enter = 新建段，Typora 语义）', () {
      final editor = InMemoryDocumentEditor(title: 'empty_para');
      editor.insertBlock(0, const ParagraphElement(children: [TextElement('')]));
      final c = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 20),
      );
      final emptyId = c.allIds.first;
      final cmd = resolver.resolveEnter(
          c, emptyId, const TextSelection.collapsed(offset: 0));
      expect(cmd, isA<SplitBlockCommand>());
      c.dispose();
    });

    test('Heading（非空）→ SplitBlockCommand（回车分块，标题不应多行）', () {
      final cmd = resolver.resolveEnter(
          coordinator, headingId, const TextSelection.collapsed(offset: 2));
      expect(cmd, isA<SplitBlockCommand>());
    });

    test('Heading（空块）→ SplitBlockCommand（空标题 Enter = 退出标题，落为段落兄弟）', () {
      final editor = InMemoryDocumentEditor(title: 'empty_h1');
      editor.insertBlock(0, const HeadingElement(level: 2, text: ''));
      final c = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 20),
      );
      final emptyId = c.allIds.first;
      final cmd = resolver.resolveEnter(
          c, emptyId, const TextSelection.collapsed(offset: 0));
      expect(cmd, isA<SplitBlockCommand>());
      c.dispose();
    });

    test('Code → InsertTextCommand("\\n")（块内换行，不分块）', () {
      final cmd = resolver.resolveEnter(
          coordinator, codeId, const TextSelection.collapsed(offset: 1));
      expect(cmd, isA<InsertTextCommand>());
      expect((cmd as InsertTextCommand).text, '\n');
    });
  });

  group('Backspace 块首合并（§4.1）', () {
    test('Paragraph → MergeWithPreviousCommand', () {
      final cmd = resolver.resolveBackspaceAtStart(coordinator, paraId);
      expect(cmd, isA<MergeWithPreviousCommand>());
    });

    test('Code → null（不可合并）', () {
      expect(resolver.resolveBackspaceAtStart(coordinator, codeId), isNull);
    });
  });

  group('Toolbar 语义动作（§4.4）', () {
    const sel = TextSelection(baseOffset: 0, extentOffset: 5);
    const noSel = TextSelection.collapsed(offset: 0);

    test('Bold 有选区 → WrapSelectionCommand', () {
      final cmd = resolver.resolveToolbarAction(
          coordinator, paraId, ToolbarActionKind.bold, sel);
      expect(cmd, isA<WrapSelectionCommand>());
    });

    test('Bold 无选区 → InsertTextCommand("****")', () {
      final cmd = resolver.resolveToolbarAction(
          coordinator, paraId, ToolbarActionKind.bold, noSel);
      expect(cmd, isA<InsertTextCommand>());
      expect((cmd as InsertTextCommand).text, '****');
    });

    test('H1 → InsertTextCommand("# ")', () {
      final cmd = resolver.resolveToolbarAction(
          coordinator, paraId, ToolbarActionKind.h1, noSel);
      expect(cmd, isA<InsertTextCommand>());
      expect((cmd as InsertTextCommand).text, '# ');
    });
  });
}
