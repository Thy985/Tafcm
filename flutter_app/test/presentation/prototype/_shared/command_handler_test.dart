/// R3 _shared 层单元测试：CommandHandler �?BlockEditorFacade 上下文中的行为�?///
/// 落地 PR 评审 R3（Phase 2.9 PR review�? Phase 2.9 Task Contract §5.1�?///
/// **覆盖范围**（补�?[command_handler_dispatch_test.dart] �?R4 自省测试）：
/// - [CommandOrigin] �?[TransactionOrigin] 映射正确�?/// - `handle()` 成功�?Transaction �?commit �?push �?[EditorHistory]
/// - [BlockEditorFacade] 聚合层的 undo / redo 行为（已�?Prototype 限制，见 R2�?///
/// **不在范围**�?/// - _dispatch 是否覆盖所�?EditorCommand 子类 �?�?[command_handler_dispatch_test.dart]
/// - _handle* 守卫逻辑 �?�?[command_handler_dispatch_test.dart]
/// - InMemoryDocumentEditor CRUD �?�?[in_memory_document_editor_test.dart]
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/transaction.dart';
import 'package:formula_fix/presentation/commands/commands.dart';
import 'package:formula_fix/presentation/commands/editor_command.dart';
import 'package:formula_fix/presentation/prototype/_shared/block_editor_facade.dart';

void main() {
  group('R3 CommandHandler Transaction 生命周期', () {
    test('handle 成功�?Transaction �?history �?, () {
      final facade = BlockEditorFacade.empty();
      final id = facade.editor.addParagraph('hello');

      final ok = facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'updated',
        origin: CommandOrigin.keyboard,
      ));

      expect(ok, isTrue);
      expect(facade.canUndo, isTrue,
          reason: 'handle 成功�?Transaction �?push �?history');
      expect(facade.history.undoCount, equals(1));
    });

    test('handle 失败（守卫触发）�?push Transaction �?history', () {
      final facade = BlockEditorFacade.empty();
      // 只有一块，merge 应被守卫拦截
      final id = facade.editor.allIds.first;

      final ok = facade.handler.handle(MergeWithPreviousCommand(
        blockId: id,
        origin: CommandOrigin.keyboard,
      ));

      expect(ok, isFalse);
      expect(facade.canUndo, isFalse,
          reason: '守卫失败时不�?push Transaction �?history');
      expect(facade.history.undoCount, equals(0));
    });

    test('handle 成功�?Undo 可恢�?editor 状�?, () {
      final facade = BlockEditorFacade.empty();
      final id = facade.editor.allIds.first;
      // 初始 source 是空字符�?''
      expect(facade.sourceOf(id), equals(''));

      // 更新 source
      final ok = facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'hello',
        origin: CommandOrigin.keyboard,
      ));
      expect(ok, isTrue);
      expect(facade.sourceOf(id), equals('hello'));

      // Undo 应恢复到�?source
      final undoneTx = facade.undo();
      expect(undoneTx, isNotNull);
      expect(facade.sourceOf(id), equals(''),
          reason: 'Undo �?source 应恢复为初始空字符串');
    });
  });

  group('R3 CommandOrigin �?TransactionOrigin 映射', () {
    /// 验证映射规则的辅助函数：执行 command 后检查栈�?Transaction.origin�?    ///
    /// 使用 [UpdateBlockSourceCommand]（始终成功，便于隔离 origin 验证）�?    TransactionOrigin originAfterHandle(
        BlockEditorFacade facade, CommandOrigin origin, String newSource) {
      final id = facade.editor.allIds.first;
      final ok = facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: newSource,
        origin: origin,
      ));
      expect(ok, isTrue, reason: 'UpdateBlockSourceCommand 应成�?);
      final lastTx = facade.history.lastOrNull;
      expect(lastTx, isNotNull, reason: 'Transaction 应已 push');
      return lastTx!.origin;
    }

    test('keyboard �?TransactionOrigin.keyboard', () {
      final facade = BlockEditorFacade.empty();
      // 先添加一个非�?source（避免空 source �?'a' 类型相同时被判定无变化）
      final id = facade.editor.allIds.first;
      facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'init',
        origin: CommandOrigin.menu,
      ));
      // 第二次：keyboard origin（source 变化，会生成�?Transaction�?      final origin = originAfterHandle(facade, CommandOrigin.keyboard, 'a');
      expect(origin, equals(TransactionOrigin.keyboard));
    });

    test('ime �?TransactionOrigin.ime', () {
      final facade = BlockEditorFacade.empty();
      final id = facade.editor.allIds.first;
      facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'init',
        origin: CommandOrigin.menu,
      ));
      final origin = originAfterHandle(facade, CommandOrigin.ime, '你好');
      expect(origin, equals(TransactionOrigin.ime));
    });

    test('ai �?TransactionOrigin.programmatic', () {
      final facade = BlockEditorFacade.empty();
      final id = facade.editor.allIds.first;
      facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'init',
        origin: CommandOrigin.menu,
      ));
      final origin = originAfterHandle(facade, CommandOrigin.ai, 'ai-gen');
      expect(origin, equals(TransactionOrigin.programmatic));
    });

    test('voice �?TransactionOrigin.programmatic', () {
      final facade = BlockEditorFacade.empty();
      final id = facade.editor.allIds.first;
      facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'init',
        origin: CommandOrigin.menu,
      ));
      final origin = originAfterHandle(facade, CommandOrigin.voice, 'voice');
      expect(origin, equals(TransactionOrigin.programmatic));
    });

    test('menu �?TransactionOrigin.programmatic', () {
      final facade = BlockEditorFacade.empty();
      // 第一�?menu origin（source 变化触发 push�?      final origin = originAfterHandle(facade, CommandOrigin.menu, 'menu');
      expect(origin, equals(TransactionOrigin.programmatic));
    });

    test('gesture �?TransactionOrigin.programmatic', () {
      final facade = BlockEditorFacade.empty();
      final id = facade.editor.allIds.first;
      facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'init',
        origin: CommandOrigin.menu,
      ));
      final origin = originAfterHandle(facade, CommandOrigin.gesture, 'gesture');
      expect(origin, equals(TransactionOrigin.programmatic));
    });
  });

  group('R3 BlockEditorFacade undo/redo Prototype 限制（R2 已标注）', () {
    test('undo �?canRedo 应为 true', () {
      final facade = BlockEditorFacade.empty();
      final id = facade.editor.allIds.first;
      facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'changed',
        origin: CommandOrigin.keyboard,
      ));
      expect(facade.canUndo, isTrue);

      final undoneTx = facade.undo();
      expect(undoneTx, isNotNull);
      expect(facade.canRedo, isTrue,
          reason: 'Undo 后应�?Redo（redo 栈非空）');
      expect(facade.canUndo, isFalse);
    });

    test('undo 实际恢复 editor 状�?, () {
      final facade = BlockEditorFacade.empty();
      final id = facade.editor.allIds.first;
      facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'changed',
        origin: CommandOrigin.keyboard,
      ));
      expect(facade.sourceOf(id), equals('changed'));

      facade.undo();

      expect(facade.sourceOf(id), equals(''),
          reason: 'Undo 应恢�?editor 状态到 source=""');
    });

    test('R2 Prototype 限制：redo 不实际恢�?editor 状态（已知 tech debt�?, () {
      // 这个测试验证 R2 文档化的限制�?      // `BlockEditorFacade.undo/redo` �?currentState 使用�?Transaction�?      // 导致 redo 栈中保存的是�?Transaction，redo 时无法恢�?editor 状态�?      //
      // 详细分析�?      // 1. Initial: source=''
      // 2. handle(UpdateSource('changed')) �?source='changed', undoStack=[T1]
      // 3. undo(): currentState=空Tx, history.undo 推空Tx �?redo �?
      //            pop T1, revert T1.ops �?source=''
      // 4. redo(): currentState=空Tx, history.redo pop 空Tx (不是 T1�?,
      //            apply 空Tx.ops (�?op) �?source 保持 ''
      //
      // �?redo �?undo 链在�?2 步会丢失状态记录�?      // Phase 3.0 需实现完整 state snapshot 机制（capture + restore）�?      final facade = BlockEditorFacade.empty();
      final id = facade.editor.allIds.first;
      facade.handler.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'changed',
        origin: CommandOrigin.keyboard,
      ));
      facade.undo();
      expect(facade.sourceOf(id), equals(''));
      expect(facade.canRedo, isTrue);

      final redoneTx = facade.redo();
      // Redo 返回�?null（栈非空），但实际是�?Transaction
      expect(redoneTx, isNotNull);
      expect(redoneTx!.ops, isEmpty,
          reason: 'R2 限制：redo 栈中是空 Transaction（currentState 被推入）');
      // 关键验证：redo 没有实际恢复 editor 状态（source 仍是空）
      expect(facade.sourceOf(id), equals(''),
          reason: 'R2 限制：redo 未恢�?source（已�?tech debt，Phase 3.0 修复�?);
      // �?canUndo/canRedo 标志本身正确（栈管理无误�?      expect(facade.canUndo, isTrue,
          reason: '�?Tx 已被推入 undo 栈（栈管理正确）');
      expect(facade.canRedo, isFalse);
    });
  });
}
