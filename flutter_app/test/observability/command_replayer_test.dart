/// CommandReplayer 测试：验�?Command Replay 的序列化、反序列化、重放和状态验证�?///
/// 落地 ADR-0021 §2.5（Layer 5：Command Replay System�? §3.7.4�?library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/presentation/observability/command_replayer.dart';
import 'package:formula_fix/core/observability/canonical_fingerprint.dart';
import 'package:formula_fix/core/observability/models.dart' hide CommandOrigin;
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/commands/command_handler.dart';
import 'package:formula_fix/presentation/commands/commands.dart';
import 'package:formula_fix/presentation/prototype/_shared/in_memory_document_editor.dart';

void main() {
  group('ReplayCommandEvent', () {
    test('toJson / fromJson round-trip', () {
      const event = ReplayCommandEvent(
        commandName: 'UpdateBlockSourceCommand',
        params: {'blockId': 'test_block', 'newSource': 'hello'},
        origin: 'keyboard',
        beforeStateHash: 'abc123',
        afterStateHash: 'def456',
      );

      final json = event.toJson();
      final restored = ReplayCommandEvent.fromJson(json);

      expect(restored.commandName, equals('UpdateBlockSourceCommand'));
      expect(restored.params['blockId'], equals('test_block'));
      expect(restored.params['newSource'], equals('hello'));
      expect(restored.origin, equals('keyboard'));
      expect(restored.beforeStateHash, equals('abc123'));
      expect(restored.afterStateHash, equals('def456'));
    });

    test('fromJson handles missing optional fields', () {
      final json = <String, Object?>{
        'commandName': 'SplitBlockCommand',
        'params': <String, Object?>{'blockId': 'b1', 'offset': 5},
        'origin': 'keyboard',
      };

      final event = ReplayCommandEvent.fromJson(json);
      expect(event.commandName, equals('SplitBlockCommand'));
      expect(event.beforeStateHash, isNull);
      expect(event.afterStateHash, isNull);
    });

    test('fromJson handles empty params', () {
      final json = <String, Object?>{
        'commandName': 'DeleteBlockCommand',
        'params': <String, Object?>{},
        'origin': 'menu',
      };

      final event = ReplayCommandEvent.fromJson(json);
      expect(event.commandName, equals('DeleteBlockCommand'));
      expect(event.params, isEmpty);
    });
  });

  group('CommandReplayer.serialize', () {
    test('serializes UpdateBlockSourceCommand', () {
      final command = UpdateBlockSourceCommand(
        blockId: BlockId('test_block'),
        newSource: 'hello world',
        origin: CommandOrigin.keyboard,
      );

      final event = CommandReplayer.serialize(command);
      expect(event.commandName, equals('UpdateBlockSourceCommand'));
      expect(event.params['blockId'], equals('test_block'));
      expect(event.params['newSource'], equals('hello world'));
      expect(event.origin, equals('keyboard'));
    });

    test('serializes SplitBlockCommand', () {
      final command = SplitBlockCommand(
        blockId: BlockId('b1'),
        offset: 5,
        origin: CommandOrigin.keyboard,
      );

      final event = CommandReplayer.serialize(command);
      expect(event.commandName, equals('SplitBlockCommand'));
      expect(event.params['blockId'], equals('b1'));
      expect(event.params['offset'], equals(5));
    });

    test('serializes InsertTextCommand', () {
      final command = InsertTextCommand(
        blockId: BlockId('b1'),
        text: 'hello',
        cursorOffset: 0,
        origin: CommandOrigin.menu,
      );

      final event = CommandReplayer.serialize(command);
      expect(event.commandName, equals('InsertTextCommand'));
      expect(event.params['blockId'], equals('b1'));
      expect(event.params['text'], equals('hello'));
      expect(event.origin, equals('menu'));
    });
  });

  group('ReplayCommandEvent.fromTraceEntry', () {
    test('converts CommandTraceEntry to ReplayCommandEvent', () {
      final traceEntry = CommandTraceEntry(
        commandName: 'UpdateBlockSourceCommand',
        params: {'blockId': 'b1', 'newSource': 'test'},
        origin: CommandOrigin.keyboard,
        timestamp: DateTime(2026, 8, 3, 10, 30, 0),
        transactionId: 'tx_001',
        succeeded: true,
        beforeStateHash: 'hash_before',
        afterStateHash: 'hash_after',
        traceId: 'trc_0001',
        spanId: 'cmd_0001',
      );

      final event = ReplayCommandEvent.fromTraceEntry(traceEntry);
      expect(event.commandName, equals('UpdateBlockSourceCommand'));
      expect(event.params['blockId'], equals('b1'));
      expect(event.beforeStateHash, equals('hash_before'));
      expect(event.afterStateHash, equals('hash_after'));
    });
  });

  group('CommandReplayer replay', () {
    late InMemoryDocumentEditor editor;
    late EditorHistory history;
    late CommandHandler handler;

    setUp(() {
      editor = InMemoryDocumentEditor();
      history = EditorHistory();
      handler = CommandHandler(editor: editor, history: history);
    });

    test('replays single UpdateBlockSourceCommand', () {
      // 准备初始状�?      final id = editor.addParagraph('initial');

      // 构建 replay 事件
      final events = [
        ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {'blockId': id.value, 'newSource': 'updated'},
          origin: 'keyboard',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results, hasLength(1));
      expect(results[0].success, isTrue);
      expect(results[0].hashMatch, isTrue,
          reason: '未指�?afterStateHash 时视为匹�?);
      expect(editor.sourceOf(id), equals('updated'),
          reason: '重放�?block source 应更�?);
    });

    test('replays multiple commands sequentially', () {
      // 准备初始状态：2 个块
      final id1 = editor.addParagraph('first');
      final id2 = editor.addParagraph('second');

      // 构建 replay 事件序列：先更新�?，再合并�?到块1
      final events = [
        ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {'blockId': id1.value, 'newSource': 'updated first'},
          origin: 'keyboard',
        ),
        ReplayCommandEvent(
          commandName: 'MergeWithPreviousCommand',
          params: {'blockId': id2.value},
          origin: 'keyboard',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results, hasLength(2));
      expect(results[0].success, isTrue,
          reason: 'UpdateBlockSourceCommand 应成�?);
      expect(results[1].success, isTrue,
          reason: 'MergeWithPreviousCommand 应成�?);
      expect(editor.blockCount, equals(1),
          reason: '合并后应�?1 个块');
    });

    test('replays with state hash verification', () {
      // 使用固定 BlockId 确保两个 editor 产生相同 fingerprint
      const fixedId = 'fixed_block';
      editor.insertBlock(0, ParagraphElement(children: [TextElement('hello')]),
          preserveId: BlockId(fixedId));

      // 计算预期�?afterStateHash
      handler.handle(UpdateBlockSourceCommand(
        blockId: BlockId(fixedId),
        newSource: 'world',
        origin: CommandOrigin.keyboard,
      ));
      final blocks = [
        MapEntry<String, DocumentElement>(fixedId, editor.getBlock(BlockId(fixedId))!),
      ];
      final expectedHash = canonicalFingerprint(blocks);

      // 重置 editor 到相同初始状态（使用相同固定 BlockId�?      editor = InMemoryDocumentEditor();
      editor.insertBlock(0, ParagraphElement(children: [TextElement('hello')]),
          preserveId: BlockId(fixedId));
      handler = CommandHandler(editor: editor, history: history);

      // 用预�?hash 构建 replay 事件
      final events = [
        ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {'blockId': fixedId, 'newSource': 'world'},
          origin: 'keyboard',
          afterStateHash: expectedHash,
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results, hasLength(1));
      expect(results[0].success, isTrue);
      expect(results[0].hashMatch, isTrue,
          reason: 'actual hash 应与 expected hash 匹配');
      expect(results[0].actualHash, equals(expectedHash));
    });

    test('reports hash mismatch when state diverges', () {
      final id = editor.addParagraph('hello');

      // 使用错误的预�?hash
      final events = [
        ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {'blockId': id.value, 'newSource': 'world'},
          origin: 'keyboard',
          afterStateHash: 'wrong_hash_that_will_not_match',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results, hasLength(1));
      expect(results[0].success, isTrue,
          reason: '命令执行成功');
      expect(results[0].hashMatch, isFalse,
          reason: 'hash 不匹�?);
    });

    test('handles deserialization failure gracefully', () {
      // 未知 commandName �?反序列化失败
      final events = [
        ReplayCommandEvent(
          commandName: 'NonExistentCommand',
          params: {},
          origin: 'keyboard',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results, hasLength(1));
      expect(results[0].success, isFalse);
      expect(results[0].error, contains('Deserialization failed'));
    });

    test('handles execution failure (invalid blockId)', () {
      // 指向不存在的 blockId
      final events = [
        ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {'blockId': 'non_existent', 'newSource': 'test'},
          origin: 'keyboard',
        ),
      ];

      // CommandHandler 内部�?catch 异常并返�?false
      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results, hasLength(1));
      expect(results[0].success, isFalse);
    });

    test('continues after failure (does not stop on error)', () {
      final id = editor.addParagraph('hello');

      final events = [
        // 第一条：失败（未�?command�?        ReplayCommandEvent(
          commandName: 'NonExistentCommand',
          params: {},
          origin: 'keyboard',
        ),
        // 第二条：应成�?        ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {'blockId': id.value, 'newSource': 'world'},
          origin: 'keyboard',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replay();

      expect(results, hasLength(2));
      expect(results[0].success, isFalse,
          reason: '第一条应失败');
      expect(results[1].success, isTrue,
          reason: '第二条应继续执行');
      expect(editor.sourceOf(id), equals('world'),
          reason: '第二条命令应成功执行');
    });

    test('allSucceeded returns true only when all pass', () {
      final id = editor.addParagraph('hello');

      // 全部成功
      final events = [
        ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {'blockId': id.value, 'newSource': 'world'},
          origin: 'keyboard',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      replayer.replay();
      expect(replayer.allSucceeded, isTrue);
      expect(replayer.failureCount, equals(0));
    });

    test('replay allSucceeded is false when some fail', () {
      final events = [
        ReplayCommandEvent(
          commandName: 'NonExistentCommand',
          params: {},
          origin: 'keyboard',
        ),
      ];

      final replayer = CommandReplayer(handler: handler, events: events);
      replayer.replay();
      expect(replayer.allSucceeded, isFalse);
      expect(replayer.failureCount, equals(1));
    });

    test('replayFrom starts from specified index', () {
      final id = editor.addParagraph('hello');

      // 先执行到失败位置
      final events = List<ReplayCommandEvent>.generate(5, (i) {
        return ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {'blockId': id.value, 'newSource': 'step_$i'},
          origin: 'keyboard',
        );
      });

      final replayer = CommandReplayer(handler: handler, events: events);
      final results = replayer.replayFrom(2); // 从第 3 条开�?
      expect(results, hasLength(3)); // 3-5 �?3 �?      expect(results[0].success, isTrue);
      expect(editor.sourceOf(id), equals('step_4'),
          reason: '最后一条命令的 source 应为 step_4');
    });
  });

  group('CommandReplayer round-trip (serialize �?deserialize �?replay)', () {
    test('full round-trip for UpdateBlockSourceCommand', () {
      final editor = InMemoryDocumentEditor();
      final history = EditorHistory();
      final handler = CommandHandler(editor: editor, history: history);
      final id = editor.addParagraph('initial');

      // 1. 构造并执行原始 Command
      final originalCommand = UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'roundtrip test',
        origin: CommandOrigin.keyboard,
      );
      expect(handler.handle(originalCommand), isTrue);

      // 2. 序列�?      final event = CommandReplayer.serialize(originalCommand);

      // 3. 重置编辑器到初始状�?      final replayEditor = InMemoryDocumentEditor();
      final replayHistory = EditorHistory();
      final replayHandler = CommandHandler(
        editor: replayEditor,
        history: replayHistory,
      );
      final replayId = replayEditor.addParagraph('initial');

      // 4. 修正 blockId（新 editor �?blockId 不同�?      final correctedEvent = ReplayCommandEvent(
        commandName: event.commandName,
        params: {
          'blockId': replayId.value,
          'newSource': event.params['newSource'],
        },
        origin: event.origin,
      );

      // 5. 重放
      final replayer = CommandReplayer(
        handler: replayHandler,
        events: [correctedEvent],
      );
      final results = replayer.replay();

      expect(results, hasLength(1));
      expect(results[0].success, isTrue);
      expect(replayEditor.sourceOf(replayId), equals('roundtrip test'));
    });
  });
}