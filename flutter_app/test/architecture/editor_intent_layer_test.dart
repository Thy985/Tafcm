/// TC-ARCH-EDITOR-1：Editing Intent Layer 守门（ADR-0019 + PR #97 P0-3）。
///
/// **铁律**：UI 层（[lib/presentation/{blocks,panels,chrome}]）禁止直接
/// `coordinator.handle(<Intent-Layer 命令>)`，所有输入意图必须先构造成
/// [EditorIntent] 子类，再经 [EditorIntentDispatcher.dispatch] 统一派发
/// （flush → resolve → handle）。dispatcher 自身（[lib/presentation/editor]）
/// 是唯一允许调用 `coordinator.handle` 的派发终点。
///
/// **动机**：PR #97 评审 P0-1 发现 `markdown_toolbar.dart` 的模板 / 图片插入
/// 直接 `coordinator.handle(InsertTemplateCommand(...))` 绕过了 Intent Layer，
/// 且手动 `flushLiveSource` 脆弱。本测试静态扫描 UI 层，阻止此类绕过回归。
///
/// **目标命令族**（Intent Layer 拥有、必须经 dispatch 的命令）：
/// - [SplitBlockCommand]（回车分块）
/// - [MergeWithPreviousCommand]（块首退格合并）
/// - [WrapSelectionCommand]（工具栏包裹）
/// - [InsertTemplateCommand]（模板 / 图片插入）
/// - [InsertTextCommand]（工具栏前缀 / 代码块内换行）
///
/// **已知豁免**（非 Intent-Layer 命令，不在扫描范围）：
/// - [UpdateBlockSourceCommand]：焦点生命周期提交（失焦 / 自动配对 / 转换类型），
///   dispatcher 不拥有该命令，UI 直接提交是既有设计。
/// - [MoveBlockUpCommand] / [MoveBlockDownCommand] / [DeleteBlockCommand]：
///   块结构操作（BlockToolbar 移动 / 删除），Intent Layer 当前未覆盖，
///   仍走 `coordinator.handle`（后续 Phase 可纳入 Intent Layer）。
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 匹配「某 coordinator 直接 .handle( 构造 Intent-Layer 命令)」的写法。
  // 注意：dispatcher 内的 `coordinator.handle(cmd)` 用变量 `cmd`，不匹配
  // `<CommandName>(` 构造式，故即便扫描 editor/ 也不会误报 dispatcher。
  final intentLayerHandle = RegExp(
    r'\.handle\(\s*(?:'
    r'SplitBlockCommand|MergeWithPreviousCommand|WrapSelectionCommand|'
    r'InsertTemplateCommand|InsertTextCommand'
    r')\s*\(',
  );

  // UI 层目录（不含 editor/，dispatcher 的派发终点合法）。
  const uiDirs = ['blocks', 'panels', 'chrome'];

  test('UI 层禁止直接 .handle( 构造 Intent-Layer 命令（TC-ARCH-EDITOR-1）', () {
    final hits = <String>[];
    for (final dir in uiDirs) {
      final directory = Directory('lib/presentation/$dir');
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (intentLayerHandle.hasMatch(line)) {
            hits.add('$path:${i + 1}: ${line.trim()}');
          }
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'ADR-0019 + PR #97 P0-1：UI 层必须经 '
          'coordinator.intents.dispatch(Intent) 派发，禁止直接 '
          'coordinator.handle(<Intent-Layer 命令>)。\n'
          '命中（应改为 dispatch 对应 EditorIntent）：\n${hits.join('\n')}',
    );
  });
}
