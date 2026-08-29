/// EditorCoordinator 单元测试：Phase 3.3 PR #1 chrome 接线。
///
/// 落地 Phase 3.3 Task Contract §3.3.1 + §3.3.4 + §3.3.5 + ADR-0011 §4。
///
/// **覆盖范围**：
/// - title：默认值、构造注入、setter（透传 InMemoryDocumentEditor）
/// - wordCount：空文档、单块、多块（透传 allSources 求和）
/// - isDirty：初始 false、mutating 操作后 true、markSaved 后 false
/// - undo/redo：canUndo/canRedo 状态切换、undo 还原内容与 wordCount、redo 重放
///
/// **不在范围**：
/// - CommandHandler dispatch 路径细节（见 command_handler_dispatch_test.dart）
/// - InMemoryDocumentEditor CRUD（见 prototype/_shared/in_memory_document_editor_test.dart）
/// - UI Widget 渲染（见 test/architecture/ui_*_test.dart）
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/commands/commands.dart';
import 'package:tafcm/presentation/commands/editor_command.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';

void main() {
  late InMemoryDocumentEditor editor;
  late EditorHistory history;
  late EditorCoordinator coordinator;

  setUp(() {
    editor = InMemoryDocumentEditor();
    history = EditorHistory();
    coordinator = EditorCoordinator(editor: editor, history: history);
  });

  group('Phase 3.3 §3.3.1 title', () {
    test('默认值为 "未命名"', () {
      expect(coordinator.title, equals('未命名'));
    });

    test('构造时注入 custom title 并透传', () {
      final customEditor = InMemoryDocumentEditor(title: '我的笔记');
      final customCoordinator = EditorCoordinator(
        editor: customEditor,
        history: EditorHistory(),
      );
      expect(customCoordinator.title, equals('我的笔记'));
    });

    test('editor.title setter 修改后 coordinator.title 同步反映', () {
      editor.title = '新标题';
      expect(coordinator.title, equals('新标题'));
    });
  });

  group('Phase 3.3 §3.3.4 wordCount', () {
    test('空文档 wordCount == 0', () {
      expect(coordinator.wordCount, equals(0));
    });

    test('单块 paragraph wordCount 等于 source 长度', () {
      editor.addParagraph('hello');
      // 'hello' 长度 5
      expect(coordinator.wordCount, equals(5));
    });

    test('多块拼接 wordCount 等于各块 source 长度之和', () {
      editor.addParagraph('hello'); // 5
      editor.addBlock('# 标题', BlockType.heading); // '# 标题' = 4
      editor.addParagraph('世界'); // 2
      expect(coordinator.wordCount, equals(5 + 4 + 2));
    });

    test('删除块后 wordCount 同步递减', () {
      final id = editor.addParagraph('hello'); // 5
      expect(coordinator.wordCount, equals(5));
      editor.removeBlock(id);
      expect(coordinator.wordCount, equals(0));
    });
  });

  group('Phase 3.3 §3.3.1 + ADR-0011 §4 isDirty', () {
    test('初始构造 isDirty == false', () {
      expect(coordinator.isDirty, isFalse,
          reason: '空 editor 不应标记 dirty');
    });

    test('markSaved 后 isDirty == false', () {
      editor.addParagraph('hello');
      expect(coordinator.isDirty, isTrue);
      coordinator.markSaved();
      expect(coordinator.isDirty, isFalse);
    });

    test('insertBlock 后 isDirty == true', () {
      editor.insertBlock(0, const ParagraphElement(children: [TextElement('x')]));
      expect(coordinator.isDirty, isTrue);
    });

    test('removeBlock 后 isDirty == true', () {
      final id = editor.addParagraph('hello');
      coordinator.markSaved();
      expect(coordinator.isDirty, isFalse);
      editor.removeBlock(id);
      expect(coordinator.isDirty, isTrue);
    });

    test('replaceBlock 后 isDirty == true', () {
      final id = editor.addParagraph('old');
      coordinator.markSaved();
      expect(coordinator.isDirty, isFalse);
      editor.replaceBlock(
          id, const ParagraphElement(children: [TextElement('new')]));
      expect(coordinator.isDirty, isTrue);
    });

    test('updateBlockContent 后 isDirty == true', () {
      final id = editor.addParagraph('old');
      coordinator.markSaved();
      expect(coordinator.isDirty, isFalse);
      editor.updateBlockContent(
          id, const ParagraphElement(children: [TextElement('new')]));
      expect(coordinator.isDirty, isTrue);
    });

    test('SeedDocuments 初始化后 isDirty == false（markSaved 已调用）', () {
      // 模拟 SeedDocuments.createDemo1 流程
      final demoEditor = InMemoryDocumentEditor(title: 'Tafcm Demo');
      demoEditor.addBlock('# Tafcm Demo', BlockType.heading);
      demoEditor.addParagraph('Hello, Block Editor!');
      demoEditor.markSaved();
      final demoCoordinator = EditorCoordinator(
        editor: demoEditor,
        history: EditorHistory(),
      );
      expect(demoCoordinator.isDirty, isFalse,
          reason: '种子文档应视为已保存的初始状态');
    });
  });

  group('Phase 3.3 §3.3.5 undo/redo', () {
    test('初始 canUndo == false 且 canRedo == false', () {
      expect(coordinator.canUndo, isFalse);
      expect(coordinator.canRedo, isFalse);
    });

    test('handle 成功后 canUndo == true 且 canRedo == false', () {
      final id = editor.addParagraph('hello');
      // 注意：addParagraph 直接走 editor，未入栈 history
      expect(coordinator.canUndo, isFalse,
          reason: '直接 editor.addParagraph 不入 history 栈');

      final ok = coordinator.handle(InsertBlockAfterCommand(
        blockId: id,
        element: const ParagraphElement(children: [TextElement('new')]),
        origin: CommandOrigin.keyboard,
      ));
      expect(ok, isTrue);
      expect(coordinator.canUndo, isTrue,
          reason: 'handle 成功后应可撤销');
      expect(coordinator.canRedo, isFalse);
    });

    test('undo 还原内容并减少 wordCount', () {
      final id = editor.addParagraph('hello'); // wordCount=5
      coordinator.markSaved();
      expect(coordinator.wordCount, equals(5));

      // 通过 handle 插入新块（入栈 history）
      coordinator.handle(InsertBlockAfterCommand(
        blockId: id,
        element: const ParagraphElement(children: [TextElement(' world')]),
        origin: CommandOrigin.keyboard,
      ));
      expect(coordinator.blockCount, equals(2));
      expect(coordinator.wordCount, equals(5 + 6)); // 'hello' + ' world'

      final tx = coordinator.undo();
      expect(tx, isNotNull, reason: 'undo 应返回被撤销的 Transaction');
      expect(coordinator.blockCount, equals(1),
          reason: 'undo 后插入的块应被移除');
      expect(coordinator.wordCount, equals(5),
          reason: 'undo 后 wordCount 应回到 undo 前的值');
    });

    test('undo 后 canRedo == true（栈管理正确）', () {
      final id = editor.addParagraph('hello');
      coordinator.handle(InsertBlockAfterCommand(
        blockId: id,
        element: const ParagraphElement(children: [TextElement('x')]),
        origin: CommandOrigin.keyboard,
      ));
      expect(coordinator.blockCount, equals(2));

      coordinator.undo();
      expect(coordinator.canRedo, isTrue, reason: 'undo 后应可重做');
      expect(coordinator.blockCount, equals(1));
    });

    // Phase 3.3 修复（原 R2 Prototype 限制 tech debt）：
    // 旧实现 undo/redo 传入空占位 Transaction 作 currentState,导致 redo 栈中
    // 保存的是空 Transaction,redo() 返回非空但 ops 为空,不恢复 editor 状态。
    // 现改为把「将被撤销/重做的真实事务」作为 currentState 回环,redo 正确重放 ops。
    // 见 editor_coordinator.dart undo()/redo() + history_manager.dart redoLastOrNull。
    test('redo 重放真实事务 ops → 恢复 editor 状态（tech debt 已修复）', () {
      final id = editor.addParagraph('hello');
      coordinator.handle(InsertBlockAfterCommand(
        blockId: id,
        element: const ParagraphElement(children: [TextElement('x')]),
        origin: CommandOrigin.keyboard,
      ));
      final countAfterInsert = coordinator.blockCount; // 2
      coordinator.undo();
      expect(coordinator.blockCount, equals(countAfterInsert - 1),
          reason: 'undo 应移除插入的块');
      expect(coordinator.canRedo, isTrue);

      final redoneTx = coordinator.redo();
      // redo 返回被重做的真实事务（携带可重放的 ops）
      expect(redoneTx, isNotNull, reason: 'redo 栈非空应返回 Transaction');
      expect(redoneTx!.ops, isNotEmpty,
          reason: '修复后：redo 返回真实事务,ops 非空');
      // 关键验证：redo 实际恢复了 editor 状态（块数回到插入后的值）
      expect(coordinator.blockCount, equals(countAfterInsert),
          reason: '修复后：redo 重放 ops,块数恢复');
      // 栈管理：redo 后可再次 undo,不可再 redo
      expect(coordinator.canUndo, isTrue,
          reason: 'redo 后真实事务回到 undo 栈');
      expect(coordinator.canRedo, isFalse);
    });

    test('undo → redo → undo 往返：editor 状态一致', () {
      final id = editor.addParagraph('hello');
      coordinator.handle(InsertBlockAfterCommand(
        blockId: id,
        element: const ParagraphElement(children: [TextElement('x')]),
        origin: CommandOrigin.keyboard,
      ));
      expect(coordinator.blockCount, equals(2));

      coordinator.undo();
      expect(coordinator.blockCount, equals(1), reason: 'undo → 1 块');
      coordinator.redo();
      expect(coordinator.blockCount, equals(2), reason: 'redo → 2 块');
      coordinator.undo();
      expect(coordinator.blockCount, equals(1), reason: '再 undo → 1 块（往返一致）');
    });

    test('UpdateBlockSourceCommand 走 handle 后可 undo 还原 source', () {
      final id = editor.addParagraph('hello');
      coordinator.markSaved();
      final originalWordCount = coordinator.wordCount;

      coordinator.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'hello world',
        origin: CommandOrigin.keyboard,
      ));
      expect(coordinator.wordCount, equals(11),
          reason: '更新后 wordCount 应反映新 source');
      expect(coordinator.isDirty, isTrue);

      coordinator.undo();
      expect(coordinator.wordCount, equals(originalWordCount),
          reason: 'undo 后 wordCount 应回到原值');
    });

    test('handle 返回 false 时不入栈（canUndo 不变）', () {
      final id = editor.addParagraph('hello');
      // MergeWithPreviousCommand 在第一块时返回 false（currentIndex <= 0）
      final ok = coordinator.handle(MergeWithPreviousCommand(
        blockId: id,
        origin: CommandOrigin.keyboard,
      ));
      expect(ok, isFalse, reason: '第一块无法与前一块合并');
      expect(coordinator.canUndo, isFalse,
          reason: 'handle 失败不应入 history 栈');
    });
  });
}
