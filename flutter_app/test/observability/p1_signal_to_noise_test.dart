/// P1 修复（2026-08-06）验证测试：Observability 信噪比优化。
///
/// 验证 4 项 P1 修复：
/// - A: debugPrint 分级 — LIGHT 模式仅失败/rollback 事件输出 debugPrint
///      （此测试不验证 debugPrint，只验证 record* 方法仍正常入 RingBuffer）
/// - B: Rollback 分类 — `rollback(unexpected: false)` 不触发 ErrorSnapshot，
///      `rollback(unexpected: true)` 触发 ErrorSnapshot
/// - C: UserInput 隐私脱敏 — 不再含原始 text 字段，改为 length/hasNewline/isAscii
/// - D: 空 Transaction 跳过 trace — 顶层 commit 空 ops 不触发 onChange / 不入 trace
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_types.dart' show BlockId;
import 'package:tafcm/core/editing/edit_operation.dart';
import 'package:tafcm/core/editing/transaction.dart' as edit
    show TransactionOrigin;
import 'package:tafcm/core/editing/transaction_builder.dart';
import 'package:tafcm/core/observability/models.dart' as obs;
import 'package:tafcm/core/observability/observability_service.dart';
import 'package:tafcm/core/observability/trace_context.dart';

void main() {
  setUp(() {
    TraceIdGenerator.reset();
  });

  group('P1-B: Rollback 分类（unexpected 标志）', () {
    test('rollback(unexpected: false) 记录 trace 但不触发 ErrorSnapshot', () {
      final svc = ObservabilityService();
      final builder = TransactionBuilder(
        origin: edit.TransactionOrigin.keyboard,
        observability: svc,
      );

      // 初始无 snapshot
      expect(svc.lastErrorSnapshot, isNull);

      builder.rollback(unexpected: false);

      // trace 已记录（rollback 入 RingBuffer）
      expect(svc.transactionTracer.count, equals(1),
          reason: 'rollback 应记录一条 TransactionTraceEntry');
      final entry = svc.transactionTracer.entries.last;
      expect(entry.result, equals(obs.TransactionResult.rollback));
      expect(entry.rollbackReason, contains('benign'),
          reason: '良性 rollback 的 reason 应含 "benign"');

      // 不触发 ErrorSnapshot（关键修复点）
      expect(svc.lastErrorSnapshot, isNull,
          reason: 'P1 修复前：所有 rollback 都触发 ErrorSnapshot，'
              '导致良性 guard 拒绝也产生"错误"快照淹没真正异常。'
              'P1 修复后：unexpected=false 不触发 ErrorSnapshot。');
    });

    test('rollback(unexpected: true) 触发 ErrorSnapshot', () {
      final svc = ObservabilityService();
      final builder = TransactionBuilder(
        origin: edit.TransactionOrigin.keyboard,
        observability: svc,
      );

      builder.rollback(unexpected: true);

      // trace 已记录，rollbackReason 含 "unexpected"
      expect(svc.transactionTracer.count, equals(1));
      final entry = svc.transactionTracer.entries.last;
      expect(entry.rollbackReason, contains('unexpected'),
          reason: '异常 rollback 的 reason 应含 "unexpected"');

      // 触发 ErrorSnapshot（保留 P0 前的行为）
      expect(svc.lastErrorSnapshot, isNotNull,
          reason: 'unexpected=true 应触发 ErrorSnapshot（保留 ADR-0021 §3.7.2 行为）');
      expect(svc.lastErrorSnapshot!.type, equals('TransactionRollback'));
    });

    test('rollback() 默认 unexpected=false（向后兼容）', () {
      final svc = ObservabilityService();
      final builder = TransactionBuilder(
        origin: edit.TransactionOrigin.keyboard,
        observability: svc,
      );

      // 不传 unexpected 参数（默认行为）
      builder.rollback();

      // 默认良性，不触发 ErrorSnapshot
      expect(svc.lastErrorSnapshot, isNull,
          reason: 'rollback() 默认 unexpected=false，应不触发 ErrorSnapshot');
      expect(svc.transactionTracer.entries.last.rollbackReason,
          contains('benign'));
    });
  });

  group('P1-C: UserInput 隐私脱敏', () {
    test('UserInput 不含原始 text 字段', () {
      final event =
          obs.UserInput.fromText('sensitive password 123', DateTime.now());

      // 不应有 text 字段
      expect(event, isA<obs.UserInput>());
      // 验证脱敏元信息（'sensitive password 123' = 22 chars）
      expect(event.length, equals(22));
      expect(event.hasNewline, isFalse);
      expect(event.isAscii, isTrue);
    });

    test('UserInput.fromText 含换行符 → hasNewline=true', () {
      final event = obs.UserInput.fromText('line1\nline2', DateTime.now());
      expect(event.length, equals(11));
      expect(event.hasNewline, isTrue);
      expect(event.isAscii, isTrue);
    });

    test('UserInput.fromText 含中文 → isAscii=false', () {
      final event = obs.UserInput.fromText('你好', DateTime.now());
      expect(event.length, equals(2));
      expect(event.isAscii, isFalse,
          reason: '中文字符非 ASCII，isAscii 应为 false');
    });

    test('exportSnapshot 不含原始 text 字段', () {
      final svc = ObservabilityService();
      svc.recordInteraction(
          obs.UserInput.fromText('secret content', DateTime.now()));

      final snapshot = svc.exportSnapshot();
      final interactions = snapshot['interactions'] as List;
      expect(interactions, hasLength(1));

      final interaction = interactions[0] as Map<String, Object?>;
      expect(interaction.containsKey('text'), isFalse,
          reason: 'P1 修复：exportSnapshot 不应暴露原始 text 字段（隐私保护）');
      expect(interaction['length'], equals(14));
      expect(interaction['hasNewline'], isFalse);
      expect(interaction['isAscii'], isTrue);
    });

    test('UserInput fromText 空字符串安全', () {
      final event = obs.UserInput.fromText('', DateTime.now());
      expect(event.length, equals(0));
      expect(event.hasNewline, isFalse);
      expect(event.isAscii, isTrue,
          reason: '空字符串 every() 返回 true（无元素不满足）');
    });
  });

  group('P1-D: 空 Transaction 跳过 trace', () {
    test('顶层 commit 空 ops 不触发 onChange', () {
      var onChangeCalled = false;
      final builder = TransactionBuilder(
        origin: edit.TransactionOrigin.keyboard,
        onChange: (_) => onChangeCalled = true,
      );

      builder.commit(label: 'empty');

      expect(onChangeCalled, isFalse,
          reason: 'P1 修复：空 ops 顶层 commit 是 no-op，不应触发 onChange '
              '（避免污染 undo 栈）');
    });

    test('顶层 commit 空 ops 不记录 trace', () {
      final svc = ObservabilityService();
      final builder = TransactionBuilder(
        origin: edit.TransactionOrigin.keyboard,
        observability: svc,
      );

      builder.commit(label: 'empty');

      expect(svc.transactionTracer.count, equals(0),
          reason: 'P1 修复：空 ops 顶层 commit 不入 RingBuffer '
              '（与 BaseBlockState._commitSource 的 no-op guard 对齐）');
    });

    test('顶层 commit 有 ops → 正常触发 onChange + trace', () {
      var onChangeCalled = false;
      final svc = ObservabilityService();
      final builder = TransactionBuilder(
        origin: edit.TransactionOrigin.keyboard,
        onChange: (_) => onChangeCalled = true,
        observability: svc,
      );

      // 添加一个 TextOperation（不 apply，只为了非空 ops）
      builder.add(TextOperation(
        blockId: const BlockId('b1'),
        offset: 0,
        inserted: 'x',
      ));

      builder.commit(label: 'non-empty');

      expect(onChangeCalled, isTrue,
          reason: '有 ops 的 commit 应正常触发 onChange');
      expect(svc.transactionTracer.count, equals(1),
          reason: '有 ops 的 commit 应正常记录 trace');
    });

    test('嵌套 builder commit 空 ops 仍合并到 parent', () {
      // 嵌套 builder 即使 ops 为空，commit 也不应短路（合并语义保持）
      final parent = TransactionBuilder(
        origin: edit.TransactionOrigin.programmatic,
      );
      final child = TransactionBuilder(
        origin: edit.TransactionOrigin.programmatic,
        parent: parent,
      );

      // 不抛异常即可（嵌套空 commit 仍是合法操作）
      child.commit();
      expect(child.isCompleted, isTrue);
      expect(parent.isCompleted, isFalse,
          reason: '子 builder commit 不应影响 parent 的 completed 状态');
    });
  });

  group('P1-A: debugPrint 分级（RingBuffer 行为不变）', () {
    test('LIGHT 模式 recordCommand 成功事件仍入 RingBuffer', () {
      final svc = ObservabilityService(); // 默认 LIGHT
      svc.recordCommand(obs.CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {'blockId': 'b1'},
        origin: obs.CommandOrigin.keyboard,
        timestamp: DateTime.now(),
        transactionId: 'tx_001',
        succeeded: true,
      ));

      // 虽然 LIGHT 模式成功事件不打 debugPrint，但应入 RingBuffer
      expect(svc.commandTracer.count, equals(1),
          reason: 'P1 修复：debugPrint 静默不影响 RingBuffer 记录');
    });

    test('LIGHT 模式 recordTransaction commit 仍入 RingBuffer', () {
      final svc = ObservabilityService(); // 默认 LIGHT
      svc.recordTransaction(obs.TransactionTraceEntry(
        transactionId: 'tx_001',
        origin: obs.TransactionOrigin.keyboard,
        beforeSnapshot: '',
        beforeHash: 'h1',
        operations: const [],
        afterSnapshot: '',
        afterHash: 'h2',
        result: obs.TransactionResult.commit,
        elapsed: Duration.zero,
      ));

      expect(svc.transactionTracer.count, equals(1),
          reason: 'P1 修复：commit 仍入 RingBuffer（debugPrint 静默 ≠ 不记录）');
    });

    test('LIGHT 模式 recordInteraction UserInput 仍入 RingBuffer', () {
      final svc = ObservabilityService(); // 默认 LIGHT
      svc.recordInteraction(obs.UserInput.fromText('hello', DateTime.now()));

      expect(svc.interactionTracer.count, equals(1),
          reason: 'P1 修复：UserInput 仍入 RingBuffer（debugPrint 静默 ≠ 不记录）');
    });
  });
}
