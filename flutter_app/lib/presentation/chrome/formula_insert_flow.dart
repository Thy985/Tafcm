/// 公式插入流程（issue #358 遗留项）：工具栏「块级公式」项的异步插入流程。
///
/// chrome/ 组件经 [EditorCoordinator] 接收数据、经 [EditorIntentDispatcher]
/// 派发意图（ADR-0019），不直接构造命令。本文件承载
/// 「弹 [FormulaInsertDialog] → 校验 → 以 insert 模式插入 `$$...$$`」的
/// 异步流程，独立成文件以守 TC-ARCH-7（markdown_toolbar.dart 单文件 ≤ 400 行）。
library;

import 'package:flutter/material.dart';

import '../commands/commands.dart';
import '../editor/editor_coordinator.dart';
import '../editor/editor_intent.dart';
import '../widgets/formula_insert_dialog.dart';

/// 弹 [FormulaInsertDialog]（display 模式：12 预设 + 实时预览 + 语法错误提示），
/// 用户确认后以 [TemplateInsertMode.insert] 插入 `\$\$...\$\$`。
///
/// **为何 insert 而非 newBlock**（与图片插入同理）：newBlock 把模板包成单个
/// [TextElement] 再走 tryTransform，公式语法是 inline（无对应 BlockType），
/// 不会转换，导致 `$$` 以字面文本残留、渲染不出公式。insert 模式经
/// `updateSource → TextOperation → toElement → parseInline` 产出
/// [FormulaElement]（displayMode=true）。
///
/// 用户取消（null）/ 空输入时静默不插入。[coordinator] 由页面持有、寿命长于
/// 工具栏，`await` 期间工具栏被销毁仍安全。
Future<void> showFormulaInsertFlow(
  BuildContext context,
  EditorCoordinator coordinator,
) async {
  final blockId = coordinator.lastFocusedId;
  if (blockId == null) return;
  // §2.7.1 强一致：在弹模态前快照选区。await showDialog 期间用户可能经系统手势
  // / 外部交互切走焦点，届时 coordinator.focusedSelection 会返回 null，使
  // InsertTemplateIntent 退化为单光标 insert（落点非预期、静默偏离）。
  // 预先捕获规避该竞态——模态期间焦点不应改变插入目标的光标基准。
  final selection = coordinator.focusedSelection;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final latex = await showDialog<String>(
    context: context,
    builder: (_) => FormulaInsertDialog(displayMode: true, isDark: isDark),
  );
  if (latex == null || latex.isEmpty) return;
  // ADR-0019（PR #97 P0-1）：经 dispatcher 统一派发，flushLiveSource 由
  // dispatcher 在 insert 时机对齐 live→domain，避免绕过 Intent Layer。
  coordinator.intents.dispatch(InsertTemplateIntent(
    blockId,
    '\$\$$latex\$\$',
    mode: TemplateInsertMode.insert,
    selection: selection,
    // cursorOffset -2：光标落在 LaTeX 末尾、闭合 $$ 之前。
    cursorOffset: -2,
  ));
}
