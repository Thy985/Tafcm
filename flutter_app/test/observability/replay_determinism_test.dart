/// Test 3: Replay 确定性验证�?///
/// 这是最重要的验证——证明编辑器状态是确定性的�?///
/// 流程�?/// 1. 固定 seed document: Paragraph(text: "hello")
/// 2. 执行命令序列：InsertText(" world") �?WrapSelection(0,5) �?UpdateBlockSource
/// 3. 记录第一次执行后�?afterStateHash
/// 4. 重置到相同的 seed document
/// 5. 重放相同的命令序�?/// 6. 验证 afterHash 一�?///
/// 如果第一�?A83F91，Replay B72D22，说明编辑器状态不是确定性的�?library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/core/observability/canonical_fingerprint.dart';
import 'package:formula_fix/presentation/observability/command_replayer.dart';
import 'package:formula_fix/core/observability/models.dart' hide CommandOrigin;
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/commands/command_handler.dart';
import 'package:formula_fix/presentation/commands/commands.dart';
import 'package:formula_fix/presentation/prototype/_shared/in_memory_document_editor.dart';

/// �?DocumentEditor 计算当前 fingerprint�?String _computeFingerprint(InMemoryDocumentEditor editor) {
  final blocks = editor.allIds
      .map((id) =>
          MapEntry<String, DocumentElement?>(id.value, editor.getBlock(id)))
      .where((e) => e.value != null)
      .map((e) => MapEntry(e.key, e.value!))
      .toList();
  return canonicalFingerprint(blocks);
}

/// 创建带有固定 seed document 的编辑器环境�?///
/// 返回 (editor, handler)，[fixedId] 用于保证 BlockId 分配可预测�?(InMemoryDocumentEditor, CommandHandler) _createEditor(String fixedId) {
  final editor = InMemoryDocumentEditor();
  final history = EditorHistory();

  // 使用固定 BlockId 创建 seed document
  editor.insertBlock(
    0,
    ParagraphElement(children: [TextElement('hello')]),
    preserveId: BlockId(fixedId),
  );

  final handler = CommandHandler(editor: editor, history: history);
  return (editor, handler);
}

void main() {
  // 固定 BlockId，确保两次执行产生相�?fingerprint
  const kFixedBlockId = 'fixed_block_seed';

  group('Replay 确定性验�?, () {
    test('InsertText �?WrapSelection �?UpdateBlockSource 回放 hash 一�?, () {
      // ============ 第一次执�?============
      final (editor1, handler1) = _createEditor(kFixedBlockId);

      // 执行 Command 1: InsertText(" world") 在末�?      final insertCmd = InsertTextCommand(
        blockId: BlockId(kFixedBlockId),
        text: ' world',
        origin: CommandOrigin.keyboard,
      );
      expect(handler1.handle(insertCmd), isTrue,
          reason: 'InsertText 应成�?);
      final hash1 = _computeFingerprint(editor1);
      final source1 = editor1.sourceOf(BlockId(kFixedBlockId));

      // 验证中间状�?      expect(source1, equals('hello world'),
          reason: 'InsertText �?source 应为 "hello world"');

      // 执行 Command 2: WrapSelection(0, 5, "**", "**")
      final wrapCmd = WrapSelectionCommand(
        blockId: BlockId(kFixedBlockId),
        prefix: '**',
        suffix: '**',
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        origin: CommandOrigin.menu,
      );
      expect(handler1.handle(wrapCmd), isTrue,
          reason: 'WrapSelection 应成�?);
      final hash2 = _computeFingerprint(editor1);
      final source2 = editor1.sourceOf(BlockId(kFixedBlockId));

      // 验证中间状�?      expect(source2, equals('**hello** world'),
          reason: 'WrapSelection �?source 应为 "**hello** world"');

      // 执行 Command 3: UpdateBlockSource 确认最终状�?      final updateCmd = UpdateBlockSourceCommand(
        blockId: BlockId(kFixedBlockId),
        newSource: '**hello** world',
        origin: CommandOrigin.keyboard,
      );
      expect(handler1.handle(updateCmd), isTrue,
          reason: 'UpdateBlockSource 应成�?);
      final hash3 = _computeFingerprint(editor1);
      final source3 = editor1.sourceOf(BlockId(kFixedBlockId));
      expect(source3, equals('**hello** world'),
          reason: '最�?source 应为 "**hello** world"');

      // ============ 构建 Replay 事件 ============
      final events = [
        ReplayCommandEvent(
          commandName: 'InsertTextCommand',
          params: {
            'blockId': kFixedBlockId,
            'text': ' world',
            'cursorOffset': 0,
          },
          origin: 'keyboard',
          afterStateHash: hash1,
        ),
        ReplayCommandEvent(
          commandName: 'WrapSelectionCommand',
          params: {
            'blockId': kFixedBlockId,
            'prefix': '**',
            'suffix': '**',
            'selection': {
              'baseOffset': 0,
              'extentOffset': 5,
              'affinity': 'downstream',
              'isDirectional': false,
            },
          },
          origin: 'menu',
          afterStateHash: hash2,
        ),
        ReplayCommandEvent(
          commandName: 'UpdateBlockSourceCommand',
          params: {
            'blockId': kFixedBlockId,
            'newSource': '**hello** world',
          },
          origin: 'keyboard',
          afterStateHash: hash3,
        ),
      ];

      // ============ 重置到相�?seed ============
      final (editor2, handler2) = _createEditor(kFixedBlockId);

      // ============ Replay ============
      final replayer = CommandReplayer(handler: handler2, events: events);
      final results = replayer.replay();

      // ============ 验证 ============
      expect(results, hasLength(3),
          reason: '应重�?3 条命�?);

      // 验证每条命令�?hash 匹配
      expect(results[0].success, isTrue,
          reason: 'Replay InsertText 应成�?);
      expect(results[0].hashMatch, isTrue,
          reason: 'InsertText �?hash 应匹�? expected=${results[0].expectedHash}, actual=${results[0].actualHash}');
      expect(results[0].actualHash, equals(hash1),
          reason: 'Replay �?hash 应与第一次执行一�?);

      expect(results[1].success, isTrue,
          reason: 'Replay WrapSelection 应成�?);
      expect(results[1].hashMatch, isTrue,
          reason: 'WrapSelection �?hash 应匹�?);
      expect(results[1].actualHash, equals(hash2),
          reason: 'Replay �?hash 应与第一次执行一�?);

      expect(results[2].success, isTrue,
          reason: 'Replay UpdateBlockSource 应成�?);
      expect(results[2].hashMatch, isTrue,
          reason: 'UpdateBlockSource �?hash 应匹�?);
      expect(results[2].actualHash, equals(hash3),
          reason: 'Replay �?hash 应与第一次执行一�?);

      // 最终状态一�?      expect(editor2.sourceOf(BlockId(kFixedBlockId)),
          equals('**hello** world'),
          reason: 'Replay �?source 应与第一次执行一�?);

      // 验证 allSucceeded
      expect(replayer.allSucceeded, isTrue,
          reason: '所�?replay 应全部成功且 hash 匹配');
      expect(replayer.failureCount, equals(0));
    });

    test('Replay 一致性：多次重放产生相同 hash', () {
      // 验证重放本身也是确定性的——重复重放两次应产生相同结果
      final (editor1, handler1) = _createEditor(kFixedBlockId);

      // 执行命令
      handler1.handle(InsertTextCommand(
        blockId: BlockId(kFixedBlockId),
        text: ' world',
        origin: CommandOrigin.keyboard,
      ));

      final hash = _computeFingerprint(editor1);

      // 构建 Replay 事件
      final events = [
        ReplayCommandEvent(
          commandName: 'InsertTextCommand',
          params: {
            'blockId': kFixedBlockId,
            'text': ' world',
            'cursorOffset': 0,
          },
          origin: 'keyboard',
          afterStateHash: hash,
        ),
      ];

      // 第一次重置并重放
      final (_, handler2) = _createEditor(kFixedBlockId);
      final replayer1 = CommandReplayer(handler: handler2, events: events);
      final r1 = replayer1.replay();

      // 第二次重置并重放
      final (_, handler3) = _createEditor(kFixedBlockId);
      final replayer2 = CommandReplayer(handler: handler3, events: events);
      final r2 = replayer2.replay();

      // 两次重放�?hash 一�?      expect(r1[0].actualHash, equals(r2[0].actualHash),
          reason: '两次重放应产生相同的 afterStateHash');
      expect(r1[0].actualHash, equals(hash),
          reason: '重放 hash 应与原始执行一�?);
    });

    test('相同�?seed + 相同的命令序�?= 相同�?fingerprint（确定性证明）', () {
      // 这是最严格的确定性测试：完全独立的两组执�?      // 同一�?seed、同一组命令、应产生完全相同�?fingerprint

      // --- 执行�?A ---
      const fixedId = 'determinism_test';
      final editorA = InMemoryDocumentEditor();
      editorA.insertBlock(
        0,
        ParagraphElement(children: [TextElement('hello')]),
        preserveId: BlockId(fixedId),
      );
      final handlerA = CommandHandler(
        editor: editorA,
        history: EditorHistory(),
      );

      handlerA.handle(InsertTextCommand(
        blockId: BlockId(fixedId),
        text: ' world',
        origin: CommandOrigin.keyboard,
      ));
      handlerA.handle(WrapSelectionCommand(
        blockId: BlockId(fixedId),
        prefix: '**',
        suffix: '**',
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        origin: CommandOrigin.menu,
      ));
      handlerA.handle(UpdateBlockSourceCommand(
        blockId: BlockId(fixedId),
        newSource: '**hello** world',
        origin: CommandOrigin.keyboard,
      ));

      final hashA = _computeFingerprint(editorA);

      // --- 执行�?B（完全独立）---
      final editorB = InMemoryDocumentEditor();
      editorB.insertBlock(
        0,
        ParagraphElement(children: [TextElement('hello')]),
        preserveId: BlockId(fixedId),
      );
      final handlerB = CommandHandler(
        editor: editorB,
        history: EditorHistory(),
      );

      handlerB.handle(InsertTextCommand(
        blockId: BlockId(fixedId),
        text: ' world',
        origin: CommandOrigin.keyboard,
      ));
      handlerB.handle(WrapSelectionCommand(
        blockId: BlockId(fixedId),
        prefix: '**',
        suffix: '**',
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        origin: CommandOrigin.menu,
      ));
      handlerB.handle(UpdateBlockSourceCommand(
        blockId: BlockId(fixedId),
        newSource: '**hello** world',
        origin: CommandOrigin.keyboard,
      ));

      final hashB = _computeFingerprint(editorB);

      // 验证 hash 一�?      expect(hashA, equals(hashB),
          reason: '两次独立执行应产生相同的 fingerprint');
    });

    test('ObservabilityService �?CommandReplayer 完整链路', () {
      // 这个测试验证�?ObservabilityService 记录 �?导出 �?Replay 的完整链�?      const fixedId = 'chain_test';

      // --- 第一次执行：�?Observability 记录 ---
      final editor1 = InMemoryDocumentEditor();
      editor1.insertBlock(
        0,
        ParagraphElement(children: [TextElement('hello')]),
        preserveId: BlockId(fixedId),
      );

      final obsSvc = ObservabilityService(
        config: const ObservabilityConfig(
          level: ObservabilityLevel.full,
          commandBufferSize: 100,
          transactionBufferSize: 50,
          interactionBufferSize: 100,
        ),
      );

      final handler1 = CommandHandler(
        editor: editor1,
        history: EditorHistory(),
        observability: obsSvc,
      );

      // 执行命令
      handler1.handle(InsertTextCommand(
        blockId: BlockId(fixedId),
        text: ' world',
        origin: CommandOrigin.keyboard,
      ));

      final originalHash = _computeFingerprint(editor1);

      // 导出 Command 事件�?      final events = obsSvc.exportCommandStream();
      expect(events, isNotEmpty,
          reason: 'Observability 应记�?Command 事件');

      // --- 重置到相�?seed ---
      final editor2 = InMemoryDocumentEditor();
      editor2.insertBlock(
        0,
        ParagraphElement(children: [TextElement('hello')]),
        preserveId: BlockId(fixedId),
      );
      final handler2 = CommandHandler(
        editor: editor2,
        history: EditorHistory(),
      );

      // 修正 blockId（如果第一次执行时 BlockId 是自动生成的，需要修正）
      final correctedEvents = events.map((e) {
        final params = Map<String, Object?>.from(e.params);
        final existingBlockId = params['blockId'];
        if (existingBlockId != null && existingBlockId != fixedId) {
          params['blockId'] = fixedId;
        }
        return ReplayCommandEvent(
          commandName: e.commandName,
          params: params,
          origin: e.origin,
          beforeStateHash: e.beforeStateHash,
          afterStateHash: e.afterStateHash,
        );
      }).toList();

      // --- Replay ---
      final replayer = CommandReplayer(handler: handler2, events: correctedEvents);
      final results = replayer.replay();

      expect(results, isNotEmpty);
      expect(results[0].success, isTrue);
      expect(results[0].hashMatch, isTrue,
          reason: '完整链路：Observability 记录 �?Replay hash 应匹�?);
      expect(results[0].actualHash, equals(originalHash),
          reason: 'Replay hash 应与原始执行 hash 一�?);
      expect(editor2.sourceOf(BlockId(fixedId)),
          equals('hello world'),
          reason: 'Replay �?source 应一�?);
    });
  });
}