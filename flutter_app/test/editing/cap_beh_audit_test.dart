/// CAP-BEH 审计测试（Phase 3.9 Behavior Audit 补充）。
///
/// 针对用户真机发现过的三类错块问题做确定性回归：
/// - CAP-BEH-003 Undo 错块：多块混合操作 undo 后块身份（allIds）与
///   内容（allSources）映射正确，不串块
/// - CAP-BEH-003b Coalescing 错块：连续操作 coalescing 后 undo 一次
///   恢复到 coalescing 起点（不多退不少退）
/// - CAP-BEH-006 Focus 异常：编辑模型层无 focus 接口（presentation 层
///   input_handler_test 已覆盖），此处用 selection 状态代理验证
///   块焦点位置的确定性
///
/// 与 undo_redo_fuzz_test（随机序列）互补：本文件是确定性错块场景。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/block_operations.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/core/editing/transaction.dart';
import 'package:formula_fix/core/editing/transaction_builder.dart';
import 'package:formula_fix/data/models/document.dart';

import 'helpers/mock_document_editor.dart';

void main() {
  group('CAP-BEH Behavior Audit（错块专项）', () {
    test('CAP-BEH-003 Undo 错块：多块混合操作 undo 后身份/内容不串块', () {
      final editor = MockDocumentEditor();
      final a = editor.addParagraph('A');
      final b = editor.addParagraph('B');
      final c = editor.addParagraph('C');
      final initialSources = editor.allSources.toList();
      final initialIds = editor.allIds.toList();
      final history = EditorHistory();

      final builder = TransactionBuilder(
        origin: TransactionOrigin.programmatic,
        onChange: (tx) => history.push(tx),
      );
      final ops = BlockOperations(editor, builder);

      // 混合操作：删 B + 在 A 后插 D + merge A→(剩余)
      ops.delete(b);
      ops.insertAfter(a, ParagraphElement(children: [TextElement('D')]));
      ops.merge(a, c);
      final tx1 = builder.commit();

      final midSources = editor.allSources.toList();
      expect(midSources, isNot(equals(initialSources)),
          reason: '操作应改变状态');

      // undo 全部 → 身份（allIds）与内容（allSources）完整恢复
      final tx = history.undo(tx1);
      expect(tx, isNotNull);
      for (final op in tx!.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.allSources, equals(initialSources),
          reason: 'undo 后内容应完整恢复（不丢块不串块）');
      expect(editor.allIds.length, initialIds.length,
          reason: 'undo 后块数量应恢复');
      // 关键：undo 后块身份与初始一致（顺序 + 内容对应）
      for (var i = 0; i < initialIds.length; i++) {
        expect(editor.allIds[i], initialIds[i],
            reason: '第 $i 个块身份应等于初始（undo 不串块）');
      }
    });

    test('CAP-BEH-003b Coalescing 错块：连续 op 合并后 undo 一次回到起点', () {
      final editor = MockDocumentEditor();
      final base = editor.addParagraph('base');
      final history = EditorHistory();

      // 连续 3 次 insertAfter（应 coalescing 为 1 个 Transaction）
      final builder = TransactionBuilder(
        origin: TransactionOrigin.programmatic,
        onChange: (tx) => history.push(tx),
      );
      final ops = BlockOperations(editor, builder);
      ops.insertAfter(base, ParagraphElement(children: [TextElement('x1')]));
      ops.insertAfter(base, ParagraphElement(children: [TextElement('x2')]));
      ops.insertAfter(base, ParagraphElement(children: [TextElement('x3')]));
      final tx = builder.commit();

      // insertAfter(base, ...) 每次插到 base 之后 → 后插的在前
      expect(editor.allSources, equals(['base', 'x3', 'x2', 'x1']));
      expect(tx.ops.length, 3, reason: '3 个 op 应记录在同一 Transaction');

      // undo 一次 → 全部撤销（coalescing 边界：不多退不少退）
      final undone = history.undo(tx);
      expect(undone, isNotNull);
      for (final op in undone!.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.allSources, equals(['base']),
          reason: 'undo 一次应回到 coalescing 起点（base）');
    });

    test('CAP-BEH-006 Focus 异常代理：块位置确定性（insert 后焦点块可定位）', () {
      final editor = MockDocumentEditor();
      final base = editor.addParagraph('base');
      final history = EditorHistory();
      final builder = TransactionBuilder(
        origin: TransactionOrigin.programmatic,
        onChange: (tx) => history.push(tx),
      );
      final ops = BlockOperations(editor, builder);

      // 在 base 后插入 → 新块位置确定（indexOf 可定位 = 焦点可落位）
      final newId = ops.insertAfter(
        base,
        ParagraphElement(children: [TextElement('focus-target')]),
      );
      final tx = builder.commit();
      expect(newId, isNotNull);
      expect(editor.indexOf(newId!), 1,
          reason: '插入块应位于 base 之后（index=1，焦点可确定性落位）');

      // undo → 块消失（焦点区域随 undo 回收，不残留悬空引用）
      final undone = history.undo(tx);
      for (final op in undone!.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.indexOf(newId), -1,
          reason: 'undo 后块应不存在（无悬空块引用）');
      expect(editor.blockCount, 1);
    });

    test('CAP-BEH-003c Redo 错块：redo 后块身份恢复（不指向错误块）', () {
      final editor = MockDocumentEditor();
      final base = editor.addParagraph('base');
      final history = EditorHistory();
      final builder = TransactionBuilder(
        origin: TransactionOrigin.programmatic,
        onChange: (tx) => history.push(tx),
      );
      final ops = BlockOperations(editor, builder);

      ops.insertAfter(base, ParagraphElement(children: [TextElement('r1')]));
      ops.insertAfter(base, ParagraphElement(children: [TextElement('r2')]));
      final tx = builder.commit();

      // undo 全部
      final undone = history.undo(tx);
      for (final op in undone!.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.allSources, equals(['base']));

      // redo 全部 → 块身份/内容恢复（不串块）
      final redone = history.redo(tx);
      expect(redone, isNotNull);
      for (final op in redone!.ops) {
        op.apply(editor);
      }
      // insertAfter(base, ...) 后插在前 → [base, r2, r1]
      expect(editor.allSources, equals(['base', 'r2', 'r1']),
          reason: 'redo 后内容应恢复');
      // 插入块 index 确定（焦点可落位）
      final ids = editor.allIds;
      expect(ids.length, 3);
      expect(editor.indexOf(ids[1]), 1);
      expect(editor.indexOf(ids[2]), 2);
    });
  });

  group('CAP-BEH-008 Paste 行为审计', () {
    test('paste 多字符一次性提交（单 Transaction，不逐字符拆分）', () {
      final editor = MockDocumentEditor();
      final id = editor.addParagraph('');
      final history = EditorHistory();
      final builder = TransactionBuilder(
        origin: TransactionOrigin.paste,
        onChange: (tx) => history.push(tx),
      );
      BlockOperations(editor, builder)
          .updateSource(id, editor.sourceOf(id) + 'hello');
      final tx = builder.commit();

      expect(editor.sourceOf(id), equals('hello'),
          reason: 'paste 内容应完整写入目标块');
      expect(tx.ops.length, equals(1),
          reason: 'paste 5 字符应是一次性单 op（不逐字符拆分）');
      expect(history.undoCount, equals(1),
          reason: 'paste 应只产生 1 个 undo 栈条目');
    });

    test('paste 与 keyboard 不 coalescing（undo 独立）', () {
      final editor = MockDocumentEditor();
      final id = editor.addParagraph('');
      final history = EditorHistory();

      void commitWith(String text, TransactionOrigin origin) {
        final b = TransactionBuilder(
          origin: origin,
          onChange: (tx) => history.push(tx),
        );
        BlockOperations(editor, b)
            .updateSource(id, editor.sourceOf(id) + text);
        b.commit();
      }

      commitWith('abc', TransactionOrigin.keyboard);
      commitWith('XYZ', TransactionOrigin.paste);
      commitWith('d', TransactionOrigin.keyboard);

      expect(editor.sourceOf(id), equals('abcXYZd'));
      expect(history.undoCount, equals(3),
          reason: 'paste 与 keyboard 不同 origin 不应合并');
    });

    test('paste undo 完整恢复（不残留半截内容）', () {
      final editor = MockDocumentEditor();
      final id = editor.addParagraph('prefix');
      final history = EditorHistory();
      final builder = TransactionBuilder(
        origin: TransactionOrigin.paste,
        onChange: (tx) => history.push(tx),
      );
      BlockOperations(editor, builder)
          .updateSource(id, editor.sourceOf(id) + '粘贴内容');
      final tx = builder.commit();

      expect(editor.sourceOf(id), equals('prefix粘贴内容'));

      // undo → 完整回滚（中文多字符也不残留）
      final undone = history.undo(tx);
      for (final op in undone!.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.sourceOf(id), equals('prefix'),
          reason: 'paste undo 应完整回滚（无半截残留）');
    });

    test('paste 多行内容 → 块内文本保真（换行不丢失）', () {
      final editor = MockDocumentEditor();
      final id = editor.addParagraph('');
      final history = EditorHistory();
      final builder = TransactionBuilder(
        origin: TransactionOrigin.paste,
        onChange: (tx) => history.push(tx),
      );
      // 粘贴多行文本（如从外部复制）
      BlockOperations(editor, builder)
          .updateSource(id, editor.sourceOf(id) + 'line1\nline2\nline3');
      final tx = builder.commit();

      expect(editor.sourceOf(id), equals('line1\nline2\nline3'),
          reason: 'paste 多行文本换行应保真');

      final undone = history.undo(tx);
      for (final op in undone!.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.sourceOf(id), equals(''),
          reason: 'paste 多行 undo 应完整回滚');
    });
  });

  group('CAP-BEH-005 Selection 目标块确定性', () {
    test('split 后右块 index = 左块 index+1（光标落位确定性）', () {
      final editor = MockDocumentEditor();
      final a = editor.addParagraph('A');
      final history = EditorHistory();
      final builder = TransactionBuilder(
        origin: TransactionOrigin.programmatic,
        onChange: (tx) => history.push(tx),
      );
      final ops = BlockOperations(editor, builder);
      ops.split(a, 1); // 'A' → 'A' | ''（offset 1 拆分）
      builder.commit();

      expect(editor.blockCount, 2, reason: 'split 后应多一块');
      // 左块仍在原 index，右块在 index+1（selection 可确定性落位）
      final leftIdx = editor.indexOf(a);
      expect(leftIdx, greaterThanOrEqualTo(0));
      expect(editor.allIds[leftIdx + 1], isNotNull,
          reason: 'split 后 index+1 处应有新块（光标可落位）');
    });

    test('merge 后左块保留、右块移除（selection 目标块确定）', () {
      final editor = MockDocumentEditor();
      final left = editor.addParagraph('left');
      final right = editor.addParagraph('right');
      final history = EditorHistory();
      final builder = TransactionBuilder(
        origin: TransactionOrigin.programmatic,
        onChange: (tx) => history.push(tx),
      );
      final ops = BlockOperations(editor, builder);
      ops.merge(left, right);
      builder.commit();

      expect(editor.blockCount, 1, reason: 'merge 后只剩左块');
      expect(editor.indexOf(left), 0, reason: '左块保留（index=0）');
      expect(editor.indexOf(right), -1, reason: '右块移除（selection 不悬空）');
    });

    test('undo merge 后块身份恢复（selection 不指向悬空块）', () {
      final editor = MockDocumentEditor();
      final left = editor.addParagraph('left');
      final right = editor.addParagraph('right');
      final history = EditorHistory();
      final builder = TransactionBuilder(
        origin: TransactionOrigin.programmatic,
        onChange: (tx) => history.push(tx),
      );
      final ops = BlockOperations(editor, builder);
      ops.merge(left, right);
      final tx = builder.commit();
      expect(editor.blockCount, 1);

      // undo merge → 两块恢复
      final undone = history.undo(tx);
      for (final op in undone!.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.blockCount, 2, reason: 'undo merge 后两块恢复');
      expect(editor.indexOf(left), 0);
      expect(editor.indexOf(right), 1,
          reason: 'undo 后右块回到 index=1（selection 可确定性恢复）');
    });
  });
}
