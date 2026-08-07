/// ADR-0020 D3 spike：CommandHandler 失败原子�?+ typing-session 粒度验证�?///
/// 验证�?/// - 成功命令 �?编辑器变�?+ 恰好 1 个历史条目（typing session = 1 Transaction�?/// - 失败命令 �?编辑器状态精确恢复（无部分变异泄漏）
/// - revertBuilder helper �?�?op 事务逆序 revert 精确恢复（D3 原子性核心）
/// - revertBuilder 后可立即开新事务（不阻塞）
///
/// 落地 ADR-0020 D3（E �?spike）�?library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/block_operations.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/core/editing/transaction.dart';
import 'package:formula_fix/core/editing/transaction_builder.dart';
import 'package:formula_fix/core/editing/transaction_rollback.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/commands/command_handler.dart';
import 'package:formula_fix/presentation/commands/commands.dart';
import 'package:formula_fix/presentation/prototype/_shared/in_memory_document_editor.dart';

void main() {
  group('ADR-0020 D3 spike: CommandHandler 原子�?, () {
    late InMemoryDocumentEditor editor;
    late EditorHistory history;
    late CommandHandler handler;

    setUp(() {
      editor = InMemoryDocumentEditor();
      history = EditorHistory();
      handler = CommandHandler(editor: editor, history: history);
    });

    test('成功命令：编辑器变更 + 恰好 1 个历史条目（typing session 粒度�?, () {
      final id = editor.addParagraph('hello');
      final ok = handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'hello world',
      ));
      expect(ok, isTrue);
      expect(editor.sourceOf(id), equals('hello world'));

      // 一个命�?= 一�?Transaction = 一�?undo 步（D3 粒度：typing session 合并�?      expect(history.undoCount, equals(1),
          reason: 'D3 粒度：单命令应产生单历史条目');
    });

    test('失败命令：编辑器状态精确恢复（无部分变异泄漏）', () {
      final id = editor.addParagraph('hello');
      final initialSources =
          editor.allIds.map((i) => editor.sourceOf(i)).toList();

      // 第一块无法合�?�?失败；_handleMerge �?ops.merge 前返�?false（不变异），
      // 失败路径 revertBuilder 亦不应留下任何残留�?      final ok = handler.handle(MergeWithPreviousCommand(blockId: id));
      expect(ok, isFalse);
      expect(editor.allIds.map((i) => editor.sourceOf(i)).toList(),
          equals(initialSources),
          reason: '失败命令后编辑器应完全未�?);
      expect(history.undoCount, equals(0),
          reason: '失败命令不应污染历史�?);
    });

    test('revertBuilder：多 op 事务逆序 revert 精确恢复（D3 原子性核心）', () {
      final aId = editor.addParagraph('a');
      final bId = editor.addParagraph('b');
      final initialIds = editor.allIds.toList();
      final initialSources =
          initialIds.map((i) => editor.sourceOf(i)).toList();

      final builder =
          TransactionBuilder(origin: TransactionOrigin.programmatic);
      final ops = BlockOperations(editor, builder);

      // �?op：insert + split + �?insert
      ops.insertAfter(aId, const ParagraphElement(children: [TextElement('x')]));
      ops.split(aId, 0);
      ops.insertAfter(bId, const ParagraphElement(children: [TextElement('y')]));
      expect(builder.opCount, equals(3));
      expect(editor.blockCount, equals(5));

      // 模拟命令中途失�?�?原子回滚
      revertBuilder(builder, editor);

      // 精确恢复
      expect(editor.blockCount, equals(2));
      expect(editor.allIds, equals(initialIds));
      expect(editor.allIds.map((i) => editor.sourceOf(i)).toList(),
          equals(initialSources));
      expect(builder.isCompleted, isTrue);
      expect(history.undoCount, equals(0));
    });

    test('revertBuilder 后可立即开新事务（不阻塞）', () {
      final aId = editor.addParagraph('a');

      final builder1 =
          TransactionBuilder(origin: TransactionOrigin.programmatic);
      final ops1 = BlockOperations(editor, builder1);
      ops1.insertAfter(aId, const ParagraphElement(children: [TextElement('b')]));
      revertBuilder(builder1, editor);
      expect(builder1.isCompleted, isTrue);

      final builder2 =
          TransactionBuilder(origin: TransactionOrigin.programmatic);
      final ops2 = BlockOperations(editor, builder2);
      ops2.insertAfter(aId, const ParagraphElement(children: [TextElement('c')]));
      final tx = builder2.commit();
      expect(tx.ops.length, equals(1));
      expect(editor.sourceOf(editor.allIds.last), equals('c'));
    });
  });
}
