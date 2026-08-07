/// 编辑器交互操作封装（Phase 3.6.1 E2E 测试辅助）。
///
/// 提供 E2E 测试中常用的编辑器操作，避免各测试重复 find / tap / enter 模式。
/// 所有操作均基于**用户可观察行为**（UI 控件），不触碰内部状态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 根据文本内容点击块（tap 进行聚焦）。
///
/// 查找包含 [text] 的 Text widget 并 tap 其所在位置。
/// 适用于段落、标题等渲染态块。
Future<void> tapBlockByText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

/// 在聚焦的 TextField 中输入文本。
///
/// 查找当前可见的 [TextField] 并输入 [text]。
/// 通常先 [tapBlockByText] 聚焦后再调用本方法。
Future<void> enterTextInFocusedBlock(
    WidgetTester tester, String text) async {
  final textField = find.byType(TextField).first;
  await tester.enterText(textField, text);
  await tester.pumpAndSettle();
}

/// 点击 AppBar 的撤销（Undo）按钮。
///
/// tooltip 为 '撤销'（对应 [EditorAppBar] 的 IconButton）。
Future<void> tapUndo(WidgetTester tester) async {
  await tester.tap(find.byTooltip('撤销'));
  await tester.pumpAndSettle();
}

/// 点击 AppBar 的重做（Redo）按钮。
///
/// tooltip 为 '重做'（对应 [EditorAppBar] 的 IconButton）。
Future<void> tapRedo(WidgetTester tester) async {
  await tester.tap(find.byTooltip('重做'));
  await tester.pumpAndSettle();
}

/// 点击工具栏（MarkdownToolbar）的格式按钮。
///
/// [tooltip] 为按钮的 tooltip 文本，如 '加粗'、'斜体'、'一级标题' 等。
/// 对应 [EditorStrings] 中的 tooltip 常量。
Future<void> tapToolbarButton(WidgetTester tester, String tooltip) async {
  // 先确保工具栏按钮可见（可能需滚动）
  final button = find.byTooltip(tooltip);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// 从状态栏读取当前块数。
///
/// 编辑器底部 StatusBar 显示 "块数: N" 格式。
/// 返回解析后的整数 N。
int? readBlockCount(WidgetTester tester) {
  final statusBar = find.textContaining('块数:');
  if (statusBar.evaluate().isEmpty) return null;
  final text = tester.widget<Text>(statusBar.first).data;
  if (text == null) return null;
  final match = RegExp(r'块数:\s*(\d+)').firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// 从状态栏读取当前字数。
///
/// 编辑器底部 StatusBar 显示 "字数: N" 格式。
/// 返回解析后的整数 N。
int? readWordCount(WidgetTester tester) {
  final statusBar = find.textContaining('字数:');
  if (statusBar.evaluate().isEmpty) return null;
  final text = tester.widget<Text>(statusBar.first).data;
  if (text == null) return null;
  final match = RegExp(r'字数:\s*(\d+)').firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// 点击代码块（通过 HighlightView 定位，代码块渲染为 RichText）。
///
/// 代码块在 render 态使用 [HighlightView]（flutter_highlight）渲染，
/// 不产生 Text widget，因此不能用 [tapBlockByText] 定位。
/// 此方法通过查找 HighlightView 运行时类型来定位代码块。
Future<void> tapCodeBlock(WidgetTester tester) async {
  final codeBlock = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == 'HighlightView',
  );
  await tester.tap(codeBlock);
  await tester.pumpAndSettle();
}