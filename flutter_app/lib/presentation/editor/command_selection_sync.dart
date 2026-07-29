/// CommandSelectionSync：命令执行后的 selection / focus / 受影响块 计算（纯函数式）。
///
/// 从 [EditorCoordinator] 抽出「命令后光标定位 + 受影响块」这一独立职责，避免协调器
/// 膨胀（Phase 3.0 §2.4 God Object 守门）。落地 R1 + R2 + PR #2C 模板 selection 规则。
///
/// **纯函数式**：输入旧 [CoordinatorState] + 命令 + 上下文，返回新 state、新聚焦块 id
/// 与受影响块集合，不产生副作用，便于单测。
library;

import 'package:flutter/painting.dart' show TextSelection;

import '../../core/editing/block_types.dart';
import '../commands/editor_command.dart';
import '../states/block_view_state.dart';
import '../states/coordinator_state.dart';
import 'in_memory_document_editor.dart';

/// 命令后 selection / focus / 受影响块 计算结果。
typedef SelectionSyncResult = ({
  CoordinatorState state,
  BlockId? newFocus,
  Set<BlockId> affectedIds,
});

/// 命令后 selection / focus 计算器（无状态，静态方法）。
class CommandSelectionSync {
  const CommandSelectionSync._();

  /// 根据 [command] 计算 selection / focus / 受影响块集合，返回更新后的 [state]。
  ///
  /// [oldSource]：插入前的 source（cursorOffset 计算需要，tryTransform 可能改变序列化）。
  /// [oldIds]：newBlock 模式下命令前的块 id 集合（用于识别新块）。
  /// [SelectionSyncResult.affectedIds] 供 coordinator 把受影响的 live 块对齐到 committed。
  /// [SelectionSyncResult.newFocus] 非空时表示焦点转移到了新块。
  static SelectionSyncResult apply(
    CoordinatorState state,
    EditorCommand command, {
    required InMemoryDocumentEditor editor,
    String? oldSource,
    Set<BlockId>? oldIds,
  }) {
    switch (command) {
      case InsertTextCommand c:
        return (
          state: _collapsedCursor(state, c.blockId, c.selection, oldSource,
              c.text.length, c.cursorOffset),
          newFocus: null,
          affectedIds: {c.blockId},
        );
      case WrapSelectionCommand c:
        final start = c.selection.start;
        final len = c.selection.end - start;
        return (
          state: _setSelection(
              state,
              c.blockId,
              TextSelection(
                baseOffset: start + c.prefix.length,
                extentOffset: start + c.prefix.length + len,
              )),
          newFocus: null,
          affectedIds: {c.blockId},
        );
      case InsertTemplateCommand c when c.mode == TemplateInsertMode.insert:
        return (
          state: _collapsedCursor(state, c.blockId, c.selection, oldSource,
              c.template.length, c.cursorOffset),
          newFocus: null,
          affectedIds: {c.blockId},
        );
      case InsertTemplateCommand c when c.mode == TemplateInsertMode.newBlock:
        // newBlock 模式：焦点转移到新块，光标在 offset 0；受影响块为全部块。
        final newId = editor.allIds.firstWhere(
            (id) => !(oldIds?.contains(id) ?? false),
            orElse: () => editor.allIds.last);
        final next =
            _setSelection(state.focusOn(newId), newId, const TextSelection.collapsed(offset: 0));
        return (state: next, newFocus: newId, affectedIds: editor.allIds.toSet());
      case PairInsertCommand c:
        return (
          state: _collapsedCursor(state, c.blockId,
              TextSelection.collapsed(offset: c.insertOffset), null, c.suffixChar.length, c.cursorOffset),
          newFocus: null,
          affectedIds: {c.blockId},
        );
      case InsertNewLineWithPrefixCommand c:
        return (
          state: _setSelection(state, c.blockId,
              TextSelection.collapsed(offset: editor.sourceOf(c.blockId).length)),
          newFocus: null,
          affectedIds: {c.blockId},
        );
      case SplitBlockCommand c:
        // 拆分后新块插在原块之后（editor.allIds[index+1]）。
        final idx = editor.allIds.indexOf(c.blockId);
        final newId = (idx >= 0 && idx + 1 < editor.allIds.length)
            ? editor.allIds[idx + 1]
            : null;
        if (newId == null) {
          return (state: state, newFocus: null, affectedIds: {c.blockId});
        }
        final next = _setSelection(
          state.focusOn(newId),
          newId,
          const TextSelection.collapsed(offset: 0),
        );
        return (
          state: next,
          newFocus: newId,
          affectedIds: {c.blockId, newId},
        );
      case MergeWithPreviousCommand c:
        // 合并后当前块被移除；用 oldIds 找上一块，焦点移到连接点。
        final ids = oldIds?.toList();
        if (ids == null || ids.indexOf(c.blockId) <= 0) {
          return (state: state, newFocus: null, affectedIds: {c.blockId});
        }
        final idx = ids.indexOf(c.blockId);
        final prevId = ids[idx - 1];
        final prevLen = editor.sourceOf(prevId).length;
        final next = _setSelection(
          state.focusOn(prevId),
          prevId,
          TextSelection.collapsed(offset: prevLen),
        );
        // 仅对齐存活的上一块；被合并块已移除，reconcile 不应再读其 source。
        return (state: next, newFocus: prevId, affectedIds: {prevId});
      default:
        return (state: state, newFocus: null, affectedIds: const {});
    }
  }

  /// 计算单光标位置并更新 viewState（InsertText / InsertTemplate(insert) 共用）。
  static CoordinatorState _collapsedCursor(CoordinatorState state, BlockId id,
      TextSelection? sel, String? oldSource, int textLen, int cursorOffset) {
    final insertOffset = sel?.baseOffset ?? (oldSource?.length ?? 0);
    return _setSelection(
        state, id, TextSelection.collapsed(offset: insertOffset + textLen + cursorOffset));
  }

  static CoordinatorState _setSelection(
      CoordinatorState state, BlockId id, TextSelection selection) {
    final cur = state.viewStateOf(id) ?? BlockViewState(id: id);
    return state.updateViewState(id, cur.copyWith(selection: selection));
  }
}
