/// Issue #329 回归测试（下）：split 新块类型的 Undo / Redo 与 Replay 保真。
///
/// 与 [heading_enter_continuation_test.dart]（resolver 裁决 / 内核 split /
/// 端到端语义）同源拆分——TC-ARCH-7 单文件 ≤400 行（test 无豁免）。
/// 覆盖：undo 无幽灵块 / redo BlockId 稳定 / newBlockType 随事件序列化
/// 重放 / 旧事件流（无该字段）兼容。
library;

import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_operations.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/core/editing/transaction.dart' show TransactionOrigin;
import 'package:tafcm/core/editing/transaction_builder.dart';
import 'package:tafcm/core/observability/models.dart' show ReplayCommandEvent;
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/block_behavior_resolver.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/commands/command_handler.dart';
import 'package:tafcm/presentation/commands/commands.dart';
import 'package:tafcm/presentation/observability/command_replayer.dart';

import '../../editing/helpers/mock_document_editor.dart';

/// 标题 Enter 场景下的源块 source（issue #329 原文样例）。
const _kHeadingSource = '# heading One';

/// 标题源长度（const 上下文使用；`String.length` 非 const 表达式）。
const _kHeadingSourceLength = 13;

void main() {
  group('Undo / Redo：无幽灵块', () {
    test('undo 恢复单标题，redo 复现段落新块且 BlockId 稳定', () {
      final editor = MockDocumentEditor();
      final builder = TransactionBuilder(origin: TransactionOrigin.programmatic);
      final ops = BlockOperations(editor, builder);
      final id = editor.addBlock(_kHeadingSource, BlockType.heading);

      ops.split(id, _kHeadingSource.length,
          newBlockType: BlockType.paragraph);
      builder.commit(label: 'split');

      // Undo：逆序 revert → 恢复为单个标题块
      for (final op in builder.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.blockCount, equals(1));
      expect(editor.sourceOf(id), equals(_kHeadingSource));
      expect(editor.getBlock(id), isA<HeadingElement>());

      // Redo：正序 re-apply（op-delta 模型）→ 2 块，右半为空段落
      for (final op in builder.ops) {
        op.apply(editor);
      }
      expect(editor.blockCount, equals(2));
      expect(editor.sourceOf(id), equals(_kHeadingSource));
      final redoneId = editor.allIds.last;
      expect(editor.getBlock(redoneId), isA<ParagraphElement>());
      expect(editor.sourceOf(redoneId), equals(''));

      // 再次 undo / redo：无幽灵块，BlockId 复用（幂等）
      for (final op in builder.ops.reversed) {
        op.revert(editor);
      }
      expect(editor.blockCount, equals(1));
      for (final op in builder.ops) {
        op.apply(editor);
      }
      expect(editor.blockCount, equals(2));
      expect(editor.allIds.last.value, equals(redoneId.value),
          reason: 'redo 复用首次分配的 BlockId，不产生幽灵块');
    });
  });

  group('Replay 保真：newBlockType 随事件序列化', () {
    test('serialize：heading Enter 命令携带 newBlockType=paragraph', () {
      const command = SplitBlockCommand(
        blockId: BlockId('h1'),
        offset: _kHeadingSourceLength,
        newBlockType: BlockType.paragraph,
      );

      final event = CommandReplayer.serialize(command);
      expect(event.params['newBlockType'], equals('paragraph'));
    });

    test('serialize：null override 不落盘（继承语义）', () {
      const command = SplitBlockCommand(
        blockId: BlockId('p1'),
        offset: 3,
      );

      final event = CommandReplayer.serialize(command);
      expect(event.params.containsKey('newBlockType'), isFalse);
    });

    test('replay：heading Enter 事件重放后新块为段落（与实时执行一致）', () {
      final editor = InMemoryDocumentEditor(title: 'issue-329-replay');
      final headingId = editor.insertBlock(
          0,
          const HeadingElement(level: 1, children: [TextElement('heading One')]));
      final handler = CommandHandler(
        editor: editor,
        history: EditorHistory(maxHistorySize: 50),
      );

      final events = [
        ReplayCommandEvent(
          commandName: 'SplitBlockCommand',
          params: {
            'blockId': headingId.value,
            'offset': _kHeadingSource.length,
            'newBlockType': 'paragraph',
          },
          origin: 'keyboard',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results, hasLength(1));
      expect(results.single.success, isTrue);
      expect(editor.blockCount, equals(2));
      final newId = editor.allIds.last;
      expect(editor.getBlock(newId), isA<ParagraphElement>(),
          reason: '重放路径同样产出段落新块（序列化保真）');
      expect(editor.sourceOf(newId), equals(''));
    });

    test('replay：旧事件流（无 newBlockType 字段）兼容，右半继承源类型', () {
      final editor = InMemoryDocumentEditor(title: 'issue-329-legacy');
      final paraId = editor.insertBlock(
          0,
          const ParagraphElement(children: [TextElement('helloworld')]));
      final handler = CommandHandler(
        editor: editor,
        history: EditorHistory(maxHistorySize: 50),
      );

      final events = [
        ReplayCommandEvent(
          commandName: 'SplitBlockCommand',
          params: {'blockId': paraId.value, 'offset': 5},
          origin: 'keyboard',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results.single.success, isTrue);
      expect(editor.blockCount, equals(2));
      expect(editor.getBlock(editor.allIds.last), isA<ParagraphElement>());
      expect(editor.sourceOf(editor.allIds.last), equals('world'));
    });
  });
}
