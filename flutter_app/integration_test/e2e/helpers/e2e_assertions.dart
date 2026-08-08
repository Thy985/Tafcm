/// E2E 测试自定义断言（Phase 3.6.1）。
///
/// 提供 E2E 测试中专用的可读性断言，将常见验证模式封装为具名方法。
/// 所有断言仅基于**用户可观察行为**（UI 控件渲染），不触碰内部状态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2e_editor.dart';

/// 验证编辑器状态栏显示的块数等于 [expected]。
///
/// 失败时输出友好的错误信息，包含实际块数。
void expectBlockCount(WidgetTester tester, int expected) {
  final actual = readBlockCount(tester);
  expect(actual, equals(expected),
      reason: '块数应为 $expected，实际为 $actual');
}

/// 验证编辑器状态栏显示的字数等于 [expected]。
///
/// 失败时输出友好的错误信息。
void expectWordCount(WidgetTester tester, int expected) {
  final actual = readWordCount(tester);
  expect(actual, equals(expected),
      reason: '字数应为 $expected，实际为 $actual');
}

/// 验证文本 [text] 在屏幕上可见（至少找到一个 widget）。
void expectTextVisible(WidgetTester tester, String text) {
  expect(find.text(text), findsWidgets,
      reason: '文本 "$text" 应在屏幕上可见');
}

/// 验证包含文本 [text] 的 widget 在屏幕上可见。
///
/// 使用 [find.textContaining] 搜索 Text widget。
void expectTextContaining(WidgetTester tester, String text) {
  expect(find.textContaining(text), findsWidgets,
      reason: '包含文本 "$text" 的 widget 应在屏幕上可见');
}

/// 验证文本 [text] 出现在任何 widget 类型中（包括 RichText、Text、EditableText）。
///
/// 适用于代码块（HighlightView 使用 RichText 渲染）等无法用 find.text 找到的场景。
void expectTextInAnyWidget(WidgetTester tester, String text) {
  final finder = find.byWidgetPredicate((widget) {
    if (widget is Text) return widget.data?.contains(text) ?? false;
    if (widget is EditableText) return widget.controller.text.contains(text);
    if (widget is RichText) return widget.text.toPlainText().contains(text);
    return false;
  });
  expect(finder, findsWidgets,
      reason: '文本 "$text" 应在屏幕上某个 widget 中可见');
}

/// 验证文本 [text] 不在屏幕上（没有任何 widget 显示它）。
void expectTextNotVisible(WidgetTester tester, String text) {
  expect(find.text(text), findsNothing,
      reason: '文本 "$text" 不应在屏幕上可见');
}

/// 验证 Undo 按钮可用（通过 find.ancestor 定位 Undo IconButton）。
void expectUndoEnabled(WidgetTester tester) {
  final undoButton = find.ancestor(
    of: find.byIcon(Icons.undo),
    matching: find.byType(IconButton),
  );
  expect(undoButton, findsOneWidget,
      reason: '撤销按钮（Icons.undo 的 IconButton）应存在');
  final button = tester.widget<IconButton>(undoButton);
  expect(button.onPressed, isNotNull,
      reason: '撤销按钮应可点击（canUndo = true）');
}

/// 验证 Undo 按钮禁用（onPressed 为 null）。
void expectUndoDisabled(WidgetTester tester) {
  final undoButton = find.ancestor(
    of: find.byIcon(Icons.undo),
    matching: find.byType(IconButton),
  );
  expect(undoButton, findsOneWidget,
      reason: '撤销按钮（Icons.undo 的 IconButton）应存在');
  final button = tester.widget<IconButton>(undoButton);
  expect(button.onPressed, isNull,
      reason: '撤销按钮应禁用（canUndo = false）');
}

/// 验证 Redo 按钮可用。
void expectRedoEnabled(WidgetTester tester) {
  final redoButton = find.ancestor(
    of: find.byIcon(Icons.redo),
    matching: find.byType(IconButton),
  );
  expect(redoButton, findsOneWidget,
      reason: '重做按钮（Icons.redo 的 IconButton）应存在');
  final button = tester.widget<IconButton>(redoButton);
  expect(button.onPressed, isNotNull,
      reason: '重做按钮应可点击（canRedo = true）');
}

/// 验证 Redo 按钮禁用。
void expectRedoDisabled(WidgetTester tester) {
  final redoButton = find.ancestor(
    of: find.byIcon(Icons.redo),
    matching: find.byType(IconButton),
  );
  expect(redoButton, findsOneWidget,
      reason: '重做按钮（Icons.redo 的 IconButton）应存在');
  final button = tester.widget<IconButton>(redoButton);
  expect(button.onPressed, isNull,
      reason: '重做按钮应禁用（canRedo = false）');
}