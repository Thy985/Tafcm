/// Issue #329 回归测试：标题块 Enter 的块类型延续语义（Typora 对齐）。
///
/// **缺陷**（QA 2026-10-04 batch B，动态复现 3 次）：标题块（`# heading One`）
/// 末尾按 Enter 新建的块自动带 `# ` 前缀，后续输入被拼进标题
/// （`- list item` → `# - list item`）。根因：`BlockOperation._applySplit`
/// 左右两半均用源块类型重建（`toElement(rightSource, heading)`），新块继承
/// 标题类型。修复：resolver（ADR-0019 唯一裁决点）对标题 Enter 显式传
/// `newBlockType: BlockType.paragraph`，经 SplitBlockCommand / BlockOperations
/// 链路穿透到 split 原语；其余类型不传 override，维持继承基线。
///
/// 语义选择（Typora 对齐）：
/// - 末尾 Enter：`# heading One|` + Enter → `# heading One` + 空段落；
/// - 中间拆分：`# abc|def` + Enter → `# abc`（标题）+ `def`（段落）；
/// - 块首（offset=0）：右半经 tryTransform 检出 `# ` 回到 heading，与旧版一致；
/// - 列表 / 任务列表 / 引用 Enter 行为为既有正确基线，本文件同步钉住防回归。
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
  group('Resolver 裁决：heading Enter → newBlockType=paragraph（issue #329）', () {
    late EditorCoordinator coordinator;
    late BlockBehaviorResolver resolver;
    late BlockId headingId;
    late BlockId paraId;
    late BlockId listId;
    late BlockId quoteId;

    setUp(() {
      final editor = InMemoryDocumentEditor(title: 'issue-329');
      editor.insertBlock(
          editor.blockCount,
          const HeadingElement(level: 1, children: [TextElement('heading One')]));
      editor.insertBlock(editor.blockCount,
          const ParagraphElement(children: [TextElement('para')]));
      editor.insertBlock(editor.blockCount,
          const ListElement(children: [TextElement('item')], ordered: false));
      editor.insertBlock(editor.blockCount,
          const ListElement(children: [TextElement('')], ordered: false));
      editor.insertBlock(
          editor.blockCount,
          const BlockquoteElement(children: [TextElement('')]));
      coordinator = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 50),
      );
      resolver = const BlockBehaviorResolver();
      headingId = coordinator.allIds[0];
      paraId = coordinator.allIds[1];
      listId = coordinator.allIds[2];
      quoteId = coordinator.allIds[4];
    });

    tearDown(() => coordinator.dispose());

    test('标题末尾 Enter → SplitBlockCommand(newBlockType: paragraph)', () {
      final cmd = resolver.resolveEnter(coordinator, headingId,
          const TextSelection.collapsed(offset: _kHeadingSource.length));
      expect(cmd, isA<SplitBlockCommand>());
      expect((cmd as SplitBlockCommand).newBlockType, BlockType.paragraph);
    });

    test('标题中间拆分 Enter → 同样传 paragraph（Typora：后半为段落）', () {
      final cmd = resolver.resolveEnter(
          coordinator, headingId, const TextSelection.collapsed(offset: 5));
      expect(cmd, isA<SplitBlockCommand>());
      expect((cmd as SplitBlockCommand).newBlockType, BlockType.paragraph);
    });

    test('空标题 Enter → 传 paragraph（端到端真正"退出标题"）', () {
      // 空 heading（source '# '）需要独立夹具：清掉文本后语义为空。
      final editor = InMemoryDocumentEditor(title: 'empty-heading');
      final emptyHeadingId = editor.insertBlock(
          0,
          const HeadingElement(level: 1, children: [TextElement('')]));
      final c = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 20),
      );
      final cmd = resolver.resolveEnter(
          c, emptyHeadingId, const TextSelection.collapsed(offset: 2));
      expect(cmd, isA<SplitBlockCommand>());
      expect((cmd as SplitBlockCommand).newBlockType, BlockType.paragraph);
      c.dispose();
    });

    test('基线：paragraph Enter → 不传 override（newBlockType 为 null）', () {
      final cmd = resolver.resolveEnter(coordinator, paraId,
          const TextSelection.collapsed(offset: 4));
      expect(cmd, isA<SplitBlockCommand>());
      expect((cmd as SplitBlockCommand).newBlockType, isNull);
    });

    test('基线：listItem 非空 Enter → InsertTextCommand（不回归）', () {
      final cmd = resolver.resolveEnter(
          coordinator, listId, const TextSelection.collapsed(offset: 6));
      expect(cmd, isA<InsertTextCommand>());
    });

    test('基线：空 listItem Enter → SplitBlockCommand 且不传 override', () {
      final editor = InMemoryDocumentEditor(title: 'empty-list');
      final emptyListId = editor.insertBlock(
          0, const ListElement(children: [TextElement('')], ordered: false));
      final c = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 20),
      );
      final cmd = resolver.resolveEnter(
          c, emptyListId, const TextSelection.collapsed(offset: 2));
      expect(cmd, isA<SplitBlockCommand>());
      expect((cmd as SplitBlockCommand).newBlockType, isNull);
      c.dispose();
    });

    test('基线：空 blockquote Enter → SplitBlockCommand 且不传 override', () {
      final cmd = resolver.resolveEnter(
          coordinator, quoteId, const TextSelection.collapsed(offset: 2));
      expect(cmd, isA<SplitBlockCommand>());
      expect((cmd as SplitBlockCommand).newBlockType, isNull);
    });
  });

  group('内核执行：split 原语右半类型 override', () {
    late MockDocumentEditor editor;
    late TransactionBuilder builder;
    late BlockOperations ops;

    setUp(() {
      editor = MockDocumentEditor();
      builder = TransactionBuilder(origin: TransactionOrigin.programmatic);
      ops = BlockOperations(editor, builder);
    });

    test('标题末尾回车：右半为空段落，source 无 "# "', () {
      final id = editor.addBlock(_kHeadingSource, BlockType.heading);

      expect(ops.split(id, _kHeadingSource.length,
          newBlockType: BlockType.paragraph), isTrue);

      expect(editor.blockCount, equals(2));
      expect(editor.getBlock(id), isA<HeadingElement>());
      expect(editor.sourceOf(id), equals(_kHeadingSource));
      final newId = editor.allIds.last;
      expect(editor.getBlock(newId), isA<ParagraphElement>());
      expect(editor.sourceOf(newId), equals(''),
          reason: '新段落 source 必须为空，不得残留 "# " 前缀');
    });

    test('标题中间拆分：前半保留标题语义，后半为段落（Typora）', () {
      // '# abc|def'：offset 5 = '# abc'.length
      final id = editor.addBlock('# abcdef', BlockType.heading);

      expect(ops.split(id, 5, newBlockType: BlockType.paragraph), isTrue);

      expect(editor.blockCount, equals(2));
      expect(editor.getBlock(id), isA<HeadingElement>());
      expect(editor.sourceOf(id), equals('# abc'));
      final newId = editor.allIds.last;
      expect(editor.getBlock(newId), isA<ParagraphElement>());
      expect(editor.sourceOf(newId), equals('def'),
          reason: '后半块是普通段落，不含 "# " 前缀');
    });

    test('空标题末尾回车：左空标题 + 右空段落', () {
      final id = editor.addBlock('# ', BlockType.heading);

      expect(ops.split(id, 2, newBlockType: BlockType.paragraph), isTrue);

      expect(editor.blockCount, equals(2));
      expect(editor.getBlock(id), isA<HeadingElement>());
      expect(editor.sourceOf(id), equals('# '));
      final newId = editor.allIds.last;
      expect(editor.getBlock(newId), isA<ParagraphElement>());
      expect(editor.sourceOf(newId), equals(''));
    });

    test('块首（offset=0）不回归：右半经 tryTransform 回到 heading', () {
      final id = editor.addBlock('# Title', BlockType.heading);

      expect(ops.split(id, 0, newBlockType: BlockType.paragraph), isTrue);

      expect(editor.blockCount, equals(2));
      // 左：空标题（与旧版一致）
      expect(editor.getBlock(id), isA<HeadingElement>());
      expect(editor.sourceOf(id), equals('# '));
      // 右：'# Title' 以 paragraph 重建后由 tryTransform 检出 "# " 回 heading
      final newId = editor.allIds.last;
      expect(editor.getBlock(newId), isA<HeadingElement>());
      expect(editor.sourceOf(newId), equals('# Title'));
    });

    test('基线：list 块 split 不传 override → 右半继承 listItem（不回归）', () {
      final id = editor.addBlock('- item', BlockType.listItem);

      expect(ops.split(id, 6), isTrue);

      expect(editor.blockCount, equals(2));
      final newId = editor.allIds.last;
      expect(editor.getBlock(newId), isA<ListElement>(),
          reason: '无 override 时右半继承源块类型（原语义）');
      expect(editor.sourceOf(newId), equals('- '));
    });
  });

  group('端到端：resolver → coordinator → 输入不被拼进标题', () {
    test('末尾回车后输入 "- item" 生成列表项，标题块不受污染', () {
      final editor = InMemoryDocumentEditor(title: 'issue-329-e2e');
      final headingId = editor.insertBlock(
          0,
          const HeadingElement(level: 1, children: [TextElement('heading One')]));
      final coordinator = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 50),
      );
      const resolver = BlockBehaviorResolver();

      // 1. 标题末尾按 Enter
      final cmd = resolver.resolveEnter(coordinator, headingId,
          const TextSelection.collapsed(offset: _kHeadingSource.length));
      if (cmd is! SplitBlockCommand) {
        fail('heading Enter 应裁决为 SplitBlockCommand，实际 $cmd');
      }
      expect(cmd.newBlockType, BlockType.paragraph);
      expect(coordinator.handle(cmd), isTrue);

      expect(coordinator.allIds, hasLength(2));
      final newId = coordinator.allIds.last;
      expect(editor.getBlock(newId), isA<ParagraphElement>());
      expect(editor.sourceOf(newId), equals(''));

      // 2. 接着输入 "- item"（issue 原文的污染路径）
      expect(
          coordinator.handle(UpdateBlockSourceCommand(
            blockId: newId,
            newSource: '- item',
          )),
          isTrue);

      expect(editor.sourceOf(newId), equals('- item'));
      expect(editor.getBlock(newId), isA<ListElement>(),
          reason: '输入被 Markdown 快捷规则识别为列表项，而非拼进标题');
      expect(editor.sourceOf(headingId), equals(_kHeadingSource),
          reason: '原标题块内容不变，无 "# - item" 拼接');

      // 3. 输入 "**bold**"：仍是段落（含粗体 inline），不是标题
      expect(
          coordinator.handle(UpdateBlockSourceCommand(
            blockId: newId,
            newSource: '**bold**',
          )),
          isTrue);
      expect(editor.getBlock(newId), isA<ParagraphElement>());
      expect(editor.sourceOf(newId), equals('**bold**'));

      coordinator.dispose();
    });
  });

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
