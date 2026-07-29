/// TC-ARCH-MODEL-4：Block 编辑组件去边框守门（ADR-0020 D4）。
///
/// **铁律**：`lib/presentation/blocks/**` 内所有块编辑组件（`base_block_state`
/// 派生类）的 [InputDecoration] 必须为 [InputBorder.none]，禁止任何形式的
/// box border（`OutlineInputBorder` / `UnderlineInputBorder`）。
///
/// **动机**：ADR-0020 D4 冻结「去边框」——从「多个独立输入框」心智模型修正为
/// 「Document Surface」。块编辑态不再用 box border 区分，聚焦指示由 caret
/// 提供。本测试静态扫描 blocks 目录，阻止 box border 回归。
///
/// **扫描范围**：仅 `lib/presentation/blocks/**`（块编辑组件）。dialog / search /
/// 全局 [app_theme.dart] 的 [InputDecorationTheme] 不在本守门范围（非块编辑）。
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 禁止的 box border 构造式（块编辑组件一律不得出现）。
  final boxBorder = RegExp(r'(?:OutlineInputBorder|UnderlineInputBorder)\s*\(');

  // 仅扫描块编辑组件目录。
  const blockDir = 'lib/presentation/blocks';

  test('块编辑组件 decoration 必须为 InputBorder.none（TC-ARCH-MODEL-4）', () {
    final hits = <String>[];
    final directory = Directory(blockDir);
    if (!directory.existsSync()) {
      fail('扫描目录不存在：$blockDir');
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        // 跳过注释行（dartdoc / 行注释），避免文档提及边框字样误报。
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        if (boxBorder.hasMatch(line)) {
          hits.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'ADR-0020 D4：块编辑组件 decoration 必须 InputBorder.none，'
          '禁止 OutlineInputBorder / UnderlineInputBorder。\n'
          '命中（应改为 InputBorder.none）：\n${hits.join('\n')}',
    );
  });
}
