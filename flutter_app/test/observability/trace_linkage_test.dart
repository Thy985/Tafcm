/// Test 1: Command Trace 链路验证（traceId 贯穿）。
///
/// 验证 Interaction → Command → Transaction 三层是否共享同一 traceId，
/// Command 是否正确关联 transactionId，确保可观测链路完整不中断。
///
/// 如果 Interaction.traceId = abc 而 Command.traceId = xyz，说明链路断了。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/models.dart';
import 'package:formula_fix/core/observability/models.dart' as obs;
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/core/observability/trace_context.dart';

void main() {
  late ObservabilityService service;
  late String sessionId;

  setUp(() {
    // 使用 FULL 模式确保所有记录生效
    service = ObservabilityService(
      config: const ObservabilityConfig(
        level: ObservabilityLevel.full,
        commandBufferSize: 100,
        transactionBufferSize: 50,
        interactionBufferSize: 100,
      ),
    );
    sessionId = service.sessionId;

    // 清空可能被之前测试污染的计数器
    TraceIdGenerator.reset();
  });

  tearDown(() {
    service.clear();
  });

  group('traceId 贯穿三层', () {
    test('Interaction → Command → Transaction 共享同一 traceId', () {
      // 1. 生成 traceId（模拟一次用户交互）
      final traceId = TraceIdGenerator.traceId();
      final interactionSpanId = 'interaction_001';

      // 2. 设置 Trace Context（模拟 EditorCoordinator.handle() 入口）
      final ctx = EditorTraceContext(
        sessionId: sessionId,
        traceId: traceId,
        spanId: interactionSpanId,
      );
      service.setTraceContext(ctx);

      // 3. 记录 Interaction
      // P1 修复：UserInput 改为脱敏元信息（length/hasNewline/isAscii）
      service.recordInteraction(obs.UserInput(
        length: 5,
        hasNewline: false,
        isAscii: true,
        timestamp: DateTime.now(),
      ));

      // 4. 记录 Command（使用同一 traceId）
      final commandSpanId = TraceIdGenerator.commandSpanId();
      final commandCtx = ctx.childSpan(commandSpanId);
      service.recordCommand(obs.CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {'blockId': 'b1', 'text': 'hello', 'cursorOffset': 0},
        origin: obs.CommandOrigin.keyboard,
        timestamp: DateTime.now(),
        transactionId: 'tx_001',
        succeeded: true,
        beforeStateHash: 'hash_before',
        afterStateHash: 'hash_after',
        traceId: commandCtx.traceId,
        spanId: commandCtx.spanId,
      ));

      // 5. 记录 Transaction（使用同一 traceId）
      final txSpanId = TraceIdGenerator.transactionSpanId();
      final txCtx = ctx.childSpan(txSpanId);
      service.recordTransaction(obs.TransactionTraceEntry(
        transactionId: 'tx_001',
        origin: obs.TransactionOrigin.keyboard,
        beforeSnapshot: 'snap_before',
        beforeHash: 'hash_before',
        operations: [
          const obs.OperationSummary(
            type: 'InsertText',
            blockId: 'b1',
            detail: 'hello',
          ),
        ],
        afterSnapshot: 'snap_after',
        afterHash: 'hash_after',
        result: obs.TransactionResult.commit,
        elapsed: const Duration(milliseconds: 5),
        traceId: txCtx.traceId,
        spanId: txCtx.spanId,
      ));

      // 6. 验证：导出 snapshot 检查 traceId 贯穿
      final snapshot = service.exportSnapshot();

      // 7. 验证 interaction 记录
      expect(snapshot['interactionCount'], equals(1),
          reason: '应记录 1 条 Interaction');
      expect(snapshot['commandCount'], equals(1),
          reason: '应记录 1 条 Command');
      expect(snapshot['transactionCount'], equals(1),
          reason: '应记录 1 条 Transaction');

      // 8. 验证 Command 的 traceId
      final commands = snapshot['commands'] as List;
      expect(commands, hasLength(1));
      final cmd = commands[0] as Map<String, Object?>;
      expect(cmd['commandName'], equals('InsertTextCommand'));
      expect(cmd['traceId'], equals(traceId),
          reason: 'Command traceId 应与 Interaction traceId 一致');
      expect(cmd['succeeded'], isTrue);
      expect(cmd['beforeStateHash'], equals('hash_before'));
      expect(cmd['afterStateHash'], equals('hash_after'));

      // 9. 验证 Transaction 的 traceId
      final transactions = snapshot['transactions'] as List;
      expect(transactions, hasLength(1));
      final tx = transactions[0] as Map<String, Object?>;
      expect(tx['transactionId'], equals('tx_001'));
      expect(tx['traceId'], equals(traceId),
          reason: 'Transaction traceId 应与 Interaction traceId 一致');
      expect(tx['result'], equals('commit'));
      expect(tx['beforeHash'], equals('hash_before'));
      expect(tx['afterHash'], equals('hash_after'));

      // 10. 验证 interaction 记录的类型
      // P1 修复：UserInput 改为脱敏元信息，不再含 'text' 字段
      final interactions = snapshot['interactions'] as List;
      expect(interactions, hasLength(1));
      final interaction = interactions[0] as Map<String, Object?>;
      expect(interaction['type'], equals('UserInput'));
      expect(interaction['length'], equals(5));
      expect(interaction['hasNewline'], isFalse);
      expect(interaction['isAscii'], isTrue);
      expect(interaction.containsKey('text'), isFalse,
          reason: 'P1 修复：UserInput 不应再含原始 text 字段');
    });

    test('traceId 贯穿：不同交互产生不同 traceId', () {
      // 模拟两次独立用户交互
      // --- 交互 1 ---
      final traceId1 = TraceIdGenerator.traceId();
      service.setTraceContext(EditorTraceContext(
        sessionId: sessionId,
        traceId: traceId1,
        spanId: 'span_1',
      ));
      service.recordInteraction(obs.UserInput(
          length: 5, hasNewline: false, isAscii: true, timestamp: DateTime.now()));
      service.recordCommand(obs.CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {'blockId': 'b1', 'text': 'first'},
        origin: obs.CommandOrigin.keyboard,
        timestamp: DateTime.now(),
        transactionId: 'tx_001',
        succeeded: true,
        traceId: traceId1,
        spanId: 'cmd_1',
      ));
      service.recordTransaction(obs.TransactionTraceEntry(
        transactionId: 'tx_001',
        origin: obs.TransactionOrigin.keyboard,
        beforeSnapshot: '',
        beforeHash: 'h1',
        operations: [],
        afterSnapshot: '',
        afterHash: 'h2',
        result: obs.TransactionResult.commit,
        elapsed: Duration.zero,
        traceId: traceId1,
        spanId: 'tx_1',
      ));

      // --- 交互 2 ---
      final traceId2 = TraceIdGenerator.traceId();
      service.setTraceContext(EditorTraceContext(
        sessionId: sessionId,
        traceId: traceId2,
        spanId: 'span_2',
      ));
      service.recordInteraction(obs.UserInput(
          length: 6, hasNewline: false, isAscii: true, timestamp: DateTime.now()));
      service.recordCommand(obs.CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {'blockId': 'b1', 'text': 'second'},
        origin: obs.CommandOrigin.keyboard,
        timestamp: DateTime.now(),
        transactionId: 'tx_002',
        succeeded: true,
        traceId: traceId2,
        spanId: 'cmd_2',
      ));
      service.recordTransaction(obs.TransactionTraceEntry(
        transactionId: 'tx_002',
        origin: obs.TransactionOrigin.keyboard,
        beforeSnapshot: '',
        beforeHash: 'h2',
        operations: [],
        afterSnapshot: '',
        afterHash: 'h3',
        result: obs.TransactionResult.commit,
        elapsed: Duration.zero,
        traceId: traceId2,
        spanId: 'tx_2',
      ));

      // 验证：两个交互的 traceId 不同
      final snapshot = service.exportSnapshot();
      final commands = snapshot['commands'] as List;
      final transactions = snapshot['transactions'] as List;

      expect(commands, hasLength(2));
      expect(transactions, hasLength(2));

      expect(commands[0]['traceId'], equals(traceId1));
      expect(commands[1]['traceId'], equals(traceId2));
      expect(transactions[0]['traceId'], equals(traceId1));
      expect(transactions[1]['traceId'], equals(traceId2));

      // 验证两个 traceId 不同
      expect(traceId1, isNot(equals(traceId2)),
          reason: '两次交互的 traceId 必须不同');
    });

    test('traceId 贯穿：未设置 TraceContext 时 traceId 为 null', () {
      // 不设置 TraceContext，直接记录
      service.recordCommand(obs.CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {},
        origin: obs.CommandOrigin.keyboard,
        timestamp: DateTime.now(),
        transactionId: 'tx_001',
        succeeded: true,
        traceId: null, // 没有上下文
        spanId: null,
      ));

      final snapshot = service.exportSnapshot();
      final commands = snapshot['commands'] as List;
      expect(commands, hasLength(1));
      final cmd = commands[0] as Map<String, Object?>;
      expect(cmd.containsKey('traceId'), isFalse,
          reason: '未设置 TraceContext 时不应有 traceId');
    });

    test('Command 和 Transaction 的 transactionId 关联', () {
      final traceId = TraceIdGenerator.traceId();
      service.setTraceContext(EditorTraceContext(
        sessionId: sessionId,
        traceId: traceId,
        spanId: 'span_main',
      ));

      // 记录 Command 和 Transaction，使用相同的 transactionId
      service.recordCommand(obs.CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {'blockId': 'b1', 'text': 'hello'},
        origin: obs.CommandOrigin.keyboard,
        timestamp: DateTime.now(),
        transactionId: 'tx_007', // 关联 ID
        succeeded: true,
        traceId: traceId,
        spanId: 'cmd_007',
      ));

      service.recordTransaction(obs.TransactionTraceEntry(
        transactionId: 'tx_007', // 同一 ID
        origin: obs.TransactionOrigin.keyboard,
        beforeSnapshot: 'snap_before',
        beforeHash: 'hash_before',
        operations: [
          const obs.OperationSummary(
            type: 'InsertText', blockId: 'b1', detail: 'hello',
          ),
        ],
        afterSnapshot: 'snap_after',
        afterHash: 'hash_after',
        result: obs.TransactionResult.commit,
        elapsed: const Duration(milliseconds: 3),
        traceId: traceId,
        spanId: 'tx_007',
      ));

      // 验证 transactionId 关联
      final cmdEntry = service.commandTracer.entries.first;
      expect(cmdEntry.transactionId, equals('tx_007'),
          reason: 'Command 应关联 correct transactionId');

      final txEntry = service.transactionTracer.entries.first;
      expect(txEntry.transactionId, equals('tx_007'),
          reason: 'Transaction 应包含自身 ID');
    });
  });
}