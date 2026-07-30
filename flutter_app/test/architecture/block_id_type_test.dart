/// TC-ARCH-MODEL-2：D2（ADR-0020）守门。
///
/// 扫描 `lib/core` + `lib/presentation`，禁止 `BlockId(` 接 int 字面量。
/// 新块身份必须走 [BlockId.generate]；preserveId 用显式 `BlockId(String)`。
///
/// 背景：D2 将 `BlockId.value` 由 int 自增改为 String UUID v4（in-memory identity，
/// 不持久化，见 ADR-0008 §9）。任何硬编码 int 字面量都会绕过 UUID 分配、破坏
/// 会话内唯一性约束，故以静态扫描守门。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TC-ARCH-MODEL-2: lib 中禁止 BlockId 接 int 字面量（须用 generate/preserveId）',
      () {
    final dirs = ['lib/core', 'lib/presentation'];
    final intLiteral = RegExp(r'BlockId\(\s*\d+\s*\)');
    final violations = <String>[];
    for (final dir in dirs) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          // 跳过注释行（如文档中引用的 block_types.dart:23 文件路径）
          if (trimmed.startsWith('///') || trimmed.startsWith('//')) continue;
          if (intLiteral.hasMatch(line)) {
            violations.add('${entity.path}:${i + 1}: $trimmed');
          }
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: '发现 BlockId(int) 字面量，违反 ADR-0020 D2（应 BlockId.generate() 或 '
          'BlockId(preserveId)）。\n${violations.join('\n')}',
    );
  });
}
