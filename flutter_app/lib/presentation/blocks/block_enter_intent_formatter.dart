/// 回车意图拦截器 + 块首退格合并检测（Phase A：Editing Intent Layer 输入侧）。
///
/// 从 [BaseBlockState] 抽离，避免基类膨胀（AGENTS.md §1.2 ≤ 400 行）。
/// 拦截器捕获软键盘在多行 [TextField] 插入的 `\n`（真机回车键路径，
/// `onSubmitted` 不触发），移除换行并回调光标处 offset，由 state 派发
/// [EnterPressedIntent]。`detectBackspaceMerge` 为 §4.1 块首合并的纯函数判定。
library;

import 'package:flutter/painting.dart' show TextSelection, TextRange;
import 'package:flutter/services.dart' show TextInputFormatter, TextEditingValue;

/// 捕获软键盘插入的 `\n` 并回调其 offset（随后由调用方派发 [EnterPressedIntent]）。
class EnterIntentFormatter extends TextInputFormatter {
  final void Function(int offset) onEnter;

  const EnterIntentFormatter({required this.onEnter});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // IME 组合态不拦截（避免中文输入 commit 阶段误触发分块）。
    if (newValue.composing != TextRange.empty) return newValue;
    if (!newValue.text.contains('\n')) return newValue;

    // 首个 `\n` 位置即回车光标处；移除所有换行，光标置于移除点。
    // **单 `\n` 假设（PR #97 P2）**：本 formatter 仅处理软键盘单次回车插入的
    // 单个 `\n`。若某 [TextInputUpdate] 含多个 `\n`（极端 IME 或粘贴），仅按
    // 首个 offset 报告并打平所有换行——属已知边界，多 `\n` 的拆分（粘贴多块）
    // 由 Phase C 的 [PasteIntent] 在 dispatcher 层处理，此处不展开。
    final offset = newValue.text.indexOf('\n');
    final cleaned = newValue.text.replaceAll('\n', '');
    onEnter(offset);
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: offset.clamp(0, cleaned.length)),
    );
  }
}

/// 块首退格合并判定（规范 §4.1）：光标在块首且本帧文本变短。
///
/// **PR #97 P0-2 修复**：不再依赖 [prev].selection.baseOffset == 0。
/// 原因：[_previousTextValue] 仅在文本变化（[_onTextChanged]）/ 模式切换
/// （[didUpdateWidget]）时更新；若用户通过触摸 / 方向键把光标移到块首
/// （selection 改变但文本未变），[_previousTextValue].selection 仍是旧位置，
/// 导致 `prev.selection.baseOffset == 0` 为 false、合并条件不满足、退格不触发
/// 合并（产生异常空行）。改为仅依据当前光标在块首（cur）＋文本变短判定，
/// 触摸 / 方向键移动光标后按退格也能正确合并。
bool detectBackspaceMerge(TextEditingValue? prev, TextEditingValue cur) {
  if (prev == null) return false;
  return cur.selection.isCollapsed &&
      cur.selection.baseOffset == 0 &&
      prev.text.length > cur.text.length;
}
