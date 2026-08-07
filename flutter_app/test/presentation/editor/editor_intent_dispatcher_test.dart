/// EditorIntentDispatcher 派发行为测试（PR #97 P0-1 / P0-3 验证）�?///
/// 验证模板 / 图片插入意图�?[EditorIntentDispatcher.dispatch] 统一派发�?/// 而非 UI 层直�?[coordinator.handle]。覆盖：
/// - InsertTemplateIntent(insert) �?当前块插入模板文�?/// - InsertTemplateIntent(newBlock) �?新建�?+ 焦点转移
/// - dispatcher 在派发前自动 flushLiveSource�?4 防文本复活）
library;

import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/presentation/commands/editor_command.dart'
    show TemplateInsertMode;
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_intent.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';

void main() {
  late InMemoryDocumentEditor editor;
  late EditorHistory history;
  late EditorCoordinator coordinator;

  setUp(() {
    editor = InMemoryDocumentEditor();
    history = EditorHistory();
    coordinator = EditorCoordinator(editor: editor, history: history);
  });

  group('EditorIntentDispatcher 模板/图片插入派发', () {
    test('InsertTemplateIntent(insert) 在当前块光标插入模板', () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);

      coordinator.intents.dispatch(InsertTemplateIntent(
        id,
        '> ',
        mode: TemplateInsertMode.insert,
        selection: const TextSelection.collapsed(offset: 0),
        cursorOffset: 0,
      ));

      expect(coordinator.sourceOf(id), contains('> '),
          reason: 'insert 模式应将模板文本插入当前�?);
    });

    test('InsertTemplateIntent(newBlock) 新建块并转移焦点', () {
      final id = editor.addParagraph('hello');
      coordinator.setFocus(id);

      coordinator.intents.dispatch(InsertTemplateIntent(
        id,
        '| �? | �? |',
        mode: TemplateInsertMode.newBlock,
      ));

      expect(coordinator.blockCount, equals(2), reason: 'newBlock 应新增一个块');
      final focusedId = coordinator.focusedId;
      expect(focusedId, isNot(equals(id)), reason: '焦点应转移到新块');
      expect(coordinator.sourceOf(focusedId!), contains('�?'),
          reason: '新块应包含模板内�?);
    });

    test('InsertTemplateIntent 派发前自�?flushLiveSource�?4 防文本复活）', () {
      final id = editor.addParagraph('draft');
      coordinator.setFocus(id);
      // 模拟实时打字（live 层领�?domain，未 commit�?      coordinator.updateLiveSource(id, 'draft with live edit');
      // 此时 domain source 仍为 'draft'，live �?'draft with live edit'

      coordinator.intents.dispatch(InsertTemplateIntent(
        id,
        '![](/assets/img_x.png)',
        mode: TemplateInsertMode.insert,
        selection: const TextSelection.collapsed(offset: 0),
        cursorOffset: 0,
      ));

      // flush �?domain 应与 live 对齐，再插入图片 �?source 同时�?live 文本与图�?      final src = coordinator.sourceOf(id);
      expect(src, contains('draft with live edit'),
          reason: 'dispatcher 应先�?live 对齐�?domain 再插�?);
      expect(src, contains('![](/assets/img_x.png)'),
          reason: '图片模板应已插入');
    });
  });
}
