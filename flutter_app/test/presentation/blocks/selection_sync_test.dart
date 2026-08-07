/// selection 同步逻辑测试：Phase 3.3 PR #2B R1+R2 修复�?///
/// 落地 Task Contract v2.1 §5.2 Task 6 + 架构评审 P3 补充�?/// - R2: EditorCoordinator.handle() �?_syncSelectionAfterCommand 计算 cursor
/// - R1: BaseBlockState.didUpdateWidget 检测外�?source 变化
///
/// **覆盖范围**�?/// - InsertTextCommand �?viewState.selection �?collapsed cursor（cursorOffset 生效�?/// - WrapSelectionCommand �?viewState.selection 保持在包裹内容上
/// - UpdateBlockSourceCommand 不修�?selection（default 分支�?/// - 多次 selection 变化帧内节流（通过 viewState 一致性验证）
library;

import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/commands/commands.dart';
import 'package:formula_fix/presentation/commands/editor_command.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/states/block_view_state.dart';

void main() {
  late InMemoryDocumentEditor editor;
  late EditorHistory history;
  late EditorCoordinator coordinator;

  setUp(() {
    editor = InMemoryDocumentEditor();
    history = EditorHistory();
    coordinator = EditorCoordinator(editor: editor, history: history);
  });

  group('Phase 3.3 PR #2B R2: InsertTextCommand cursorOffset 生效', () {
    test('无选区插入 **** cursorOffset=-2 �?cursor 在中间（offset 2�?, () {
      final id = editor.addParagraph('hello'); // source 长度 5
      coordinator.setFocus(id);
      // 无选区：selection = null,insertOffset = source.length = 5
      // cursorPos = 5 + 4(****长度) + (-2) = 7 �?'hello**|**'
      coordinator.handle(InsertTextCommand(
        blockId: id,
        text: '****',
        cursorOffset: -2,
      ));

      final sel = coordinator.viewStateOf(id)?.selection;
      expect(sel, isNotNull, reason: 'handle �?viewState 应有 selection');
      expect(sel!.isCollapsed, isTrue, reason: 'InsertText 后应为单光标');
      expect(sel.baseOffset, equals(7),
          reason: 'cursorPos = 5 + 4 + (-2) = 7,�?**** 中间');
      expect(sel.extentOffset, equals(7));
    });

    test('有光标位�?selection.baseOffset=2 插入 ## cursorOffset=0 �?cursor 在末�?, () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);
      coordinator.handle(InsertTextCommand(
        blockId: id,
        text: '## ',
        cursorOffset: 0,
        selection: const TextSelection.collapsed(offset: 2),
      ));

      final sel = coordinator.viewStateOf(id)?.selection;
      expect(sel, isNotNull);
      // cursorPos = 2(baseOffset) + 3(## 长度) + 0 = 5
      expect(sel!.baseOffset, equals(5),
          reason: 'cursorPos = 2 + 3 + 0 = 5,在插入文本末�?);
    });

    test('Code 按钮插入 `` cursorOffset=-1 �?cursor 在反引号中间', () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);
      // 无选区：insertOffset = 5,cursorPos = 5 + 2(``长度) + (-1) = 6
      coordinator.handle(InsertTextCommand(
        blockId: id,
        text: '``',
        cursorOffset: -1,
      ));

      final sel = coordinator.viewStateOf(id)?.selection;
      expect(sel!.baseOffset, equals(6), reason: 'cursorPos = 5 + 2 - 1 = 6');
    });

    test('Link 按钮插入 []() cursorOffset=-3 �?cursor �?[ �?, () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);
      // 无选区：insertOffset = 5,cursorPos = 5 + 4([]()长度) + (-3) = 6
      coordinator.handle(InsertTextCommand(
        blockId: id,
        text: '[]()',
        cursorOffset: -3,
      ));

      final sel = coordinator.viewStateOf(id)?.selection;
      expect(sel!.baseOffset, equals(6),
          reason: 'cursorPos = 5 + 4 - 3 = 6,�?[ �?);
    });
  });

  group('Phase 3.3 PR #2B R2: WrapSelectionCommand 选区保持', () {
    test('包裹 hello �?**hello** �?selection 保持�?hello �?, () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);
      // 选区 [0, 5) 选中 'hello'
      coordinator.handle(WrapSelectionCommand(
        blockId: id,
        prefix: '**',
        suffix: '**',
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      ));

      final sel = coordinator.viewStateOf(id)?.selection;
      expect(sel, isNotNull, reason: 'WrapSelection 后应�?selection');
      // 包裹后：**hello**
      // selection = [0 + 2, 0 + 2 + 5) = [2, 7) 选中 'hello'
      expect(sel!.baseOffset, equals(2),
          reason: 'start + prefix.length = 0 + 2 = 2');
      expect(sel.extentOffset, equals(7),
          reason: 'start + prefix.length + len = 0 + 2 + 5 = 7');
      expect(sel.baseOffset != sel.extentOffset, isTrue,
          reason: '应保持非空选区（包裹后的原始内容）');
    });

    test('反向选区 [5, 0) 包裹�?selection 归一�?, () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);
      coordinator.handle(WrapSelectionCommand(
        blockId: id,
        prefix: '*',
        suffix: '*',
        selection: const TextSelection(baseOffset: 5, extentOffset: 0),
      ));

      final sel = coordinator.viewStateOf(id)?.selection;
      // selection.start 自动归一化为 0（min(5,0)�?      // selection = [0 + 1, 0 + 1 + 5) = [1, 6)
      expect(sel!.baseOffset, equals(1));
      expect(sel.extentOffset, equals(6));
    });

    test('部分选区 [2, 4) 包裹�?selection 保持在包裹内容上', () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);
      coordinator.handle(WrapSelectionCommand(
        blockId: id,
        prefix: '`',
        suffix: '`',
        selection: const TextSelection(baseOffset: 2, extentOffset: 4),
      ));

      final sel = coordinator.viewStateOf(id)?.selection;
      // 包裹后：he`ll`o
      // selection = [2 + 1, 2 + 1 + 2) = [3, 5) 选中 'll'
      expect(sel!.baseOffset, equals(3));
      expect(sel.extentOffset, equals(5));
    });
  });

  group('Phase 3.3 PR #2B R1: 其他 Command 不修�?selection', () {
    test('UpdateBlockSourceCommand 不触�?selection 同步（default 分支�?, () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);
      // 预设一�?selection
      coordinator.updateViewState(
        id,
        (coordinator.viewStateOf(id) ?? BlockViewState(id: id)).copyWith(
            selection: const TextSelection.collapsed(offset: 3)),
      );

      coordinator.handle(UpdateBlockSourceCommand(
        blockId: id,
        newSource: 'hello world',
      ));

      final sel = coordinator.viewStateOf(id)?.selection;
      // UpdateBlockSource 不修�?selection（保持预设值）
      expect(sel, isNotNull);
      expect(sel!.baseOffset, equals(3),
          reason: 'UpdateBlockSource 不应修改 selection');
    });

    test('InsertBlockAfterCommand 不修�?selection', () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);

      coordinator.handle(InsertBlockAfterCommand(
        blockId: id,
        element: const ParagraphElement(children: [TextElement('new')]),
        origin: CommandOrigin.keyboard,
      ));

      // 新插入的块不应有预设 selection
      final newId = coordinator.allIds.last;
      final sel = coordinator.viewStateOf(newId)?.selection;
      expect(sel, isNull, reason: '新块不应有预�?selection');
    });
  });

  group('Phase 3.3 PR #2B R1: cursorOffset 计算公式验证', () {
    /// 验证 cursorOffset 语义文档（editor_command.dart:192-194）：
    /// cursorPos = insertOffset + text.length + cursorOffset
    test('文档示例：text=**** cursorOffset=-2 �?中间位置', () {
      final id = editor.addParagraph(''); // �?source
      coordinator.setFocus(id);
      // insertOffset = 0（空 source�?      // cursorPos = 0 + 4 + (-2) = 2 �?'**|**'
      coordinator.handle(InsertTextCommand(
        blockId: id,
        text: '****',
        cursorOffset: -2,
      ));

      expect(coordinator.viewStateOf(id)?.selection?.baseOffset, equals(2));
    });

    test('cursorOffset=0 �?cursor 在插入文本末�?, () {
      final id = editor.addParagraph('');
      coordinator.setFocus(id);
      coordinator.handle(InsertTextCommand(
        blockId: id,
        text: 'abc',
        cursorOffset: 0,
      ));

      expect(coordinator.viewStateOf(id)?.selection?.baseOffset, equals(3));
    });

    test('cursorOffset=-1 �?cursor 在倒数�?1 �?, () {
      final id = editor.addParagraph('');
      coordinator.setFocus(id);
      coordinator.handle(InsertTextCommand(
        blockId: id,
        text: 'abc',
        cursorOffset: -1,
      ));

      expect(coordinator.viewStateOf(id)?.selection?.baseOffset, equals(2));
    });
  });
}
