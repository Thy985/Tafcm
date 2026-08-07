/// TC-ARCH-MODEL-3：编辑操作必须经 TransactionBuilder 单入口（CommandHandler），
/// 禁止�?command_handler.dart 之外直接实例�?BlockOperations�?///
/// 落地 ADR-0020 D3 + §4 守门�?///
/// 扫描策略：在 lib/** 中查�?`BlockOperations(` 字面量，其合法出现位置仅两类�?/// 1. core/editing/block_operations.dart —�?类定义（构造函数）�?/// 2. presentation/commands/command_handler.dart —�?唯一 Transaction 入口�?/// 其余任何文件出现 `BlockOperations(` 即视为越界（�?UI/Widget/Coordinator �?/// 绕过 TransactionBuilder 直调内核原语，破�?D3 原子性边界）�?library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TC-ARCH-MODEL-3: BlockOperations 仅允许在定义文件�?CommandHandler 实例�?, () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: '必须�?flutter_app 根目录运行（relative path lib/�?);

    // 合法位置（normalized 后缀�?    const allowedSuffixes = <String>[
      'lib/core/editing/block_operations.dart', // 类定�?      'lib/presentation/commands/command_handler.dart', // 唯一 Transaction 入口
    ];

    final violations = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (!content.contains('BlockOperations(')) continue;

      final normalized = entity.path.replaceAll(r'\', '/');
      final isAllowed =
          allowedSuffixes.any((suffix) => normalized.endsWith(suffix));
      if (!isAllowed) violations.add(normalized);
    }

    expect(violations, isEmpty,
        reason: 'BlockOperations 直调点越界（须经 CommandHandler�? $violations');
  });

  test('TC-ARCH-MODEL-3: CommandHandler 失败路径已接原子回滚（revertBuilder�?, () {
    final file = File('lib/presentation/commands/command_handler.dart');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();

    // 失败路径必须调用 revertBuilder（逆序 revert �?apply �?op），
    // 而非�?builder.rollback()（纯清空，会残留部分变异态）�?    expect(content, contains('revertBuilder('),
        reason: 'CommandHandler 失败�?revert �?apply �?op 以恢�?editor 状�?);
    // 确认 import 了原子回�?helper（项目用相对路径，故只校验文件名�?    expect(content, contains('transaction_rollback.dart'),
        reason: 'command_handler �?import revertBuilder helper');
  });
}
