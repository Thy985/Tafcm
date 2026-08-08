/// Test 2: Error Snapshot 注入测试。
///
/// 主动制造错误场景，验证 Observability 系统能否正确捕获异常现场。
///
/// 预期：
/// - exception 被捕获
/// - snapshot 完整（含 type, message, traceId, commandName, commandParams）
/// - traceId 存在于 snapshot 中
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/error_snapshot.dart';
import 'package:formula_fix/core/observability/error_snapshotter.dart';
import 'package:formula_fix/core/observability/models.dart';
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/core/observability/trace_context.dart';

/// 创建正确关联的 ObservabilityService + ErrorSnapshotter 对。
///
/// ErrorSnapshotter 直接引用 ObservabilityService，确保
/// currentContext 读取一致。测试通过 snap.capture() 直接调用。
(ObservabilityService, ErrorSnapshotter) _createService() {
  final svc = ObservabilityService(
    config: const ObservabilityConfig(
      level: ObservabilityLevel.full,
      commandBufferSize: 100,
      transactionBufferSize: 50,
      interactionBufferSize: 100,
    ),
  );
  final snap = ErrorSnapshotter(observability: svc);
  return (svc, snap);
}

void main() {
  setUp(() {
    TraceIdGenerator.reset();
  });

  group('Error Snapshot 注入测试', () {
    test('注入非法 Command 参数：blockId fake, offset 999999', () {
      final (svc, snap) = _createService();
      final sid = svc.sessionId;

      // 设置 Trace Context
      final traceId = TraceIdGenerator.traceId();
      svc.setTraceContext(EditorTraceContext(
        sessionId: sid,
        traceId: traceId,
        spanId: 'span_error',
      ));

      // 模拟 Command 执行异常：InsertTextCommand 指向不存在的 blockId
      final snapshot = snap.capture(
        type: 'CommandExecutionError',
        message: 'BlockId not found: fake',
        commandName: 'InsertTextCommand',
        commandParams: {
          'blockId': 'fake',
          'text': 'hello',
          'cursorOffset': 999999,
        },
        cursorBlockId: 'fake',
        cursorOffset: 999999,
      );

      // 验证：snapshot 不为 null
      expect(snapshot, isNotNull, reason: 'FULL 模式下应生成 ErrorSnapshot');

      // 验证：type
      expect(snapshot.type, equals('CommandExecutionError'),
          reason: '错误类型应匹配');

      // 验证：message
      expect(snapshot.message, contains('BlockId not found'),
          reason: '错误消息应包含根因');

      // 验证：traceId 存在
      expect(snapshot.traceId, equals(traceId),
          reason: 'ErrorSnapshot 应包含 traceId');

      // 验证：sessionId 存在
      expect(snapshot.sessionId, equals(sid),
          reason: 'ErrorSnapshot 应包含 sessionId');

      // 验证：commandName
      expect(snapshot.commandName, equals('InsertTextCommand'),
          reason: '应记录出错的 Command 名称');

      // 验证：commandParams 包含非法参数
      expect(snapshot.commandParams, isNotNull);
      expect(snapshot.commandParams!['blockId'], equals('fake'));
      expect(snapshot.commandParams!['cursorOffset'], equals(999999));

      // 验证：cursorBlockId
      expect(snapshot.cursorBlockId, equals('fake'));

      // 验证：captureMode 为 light
      expect(snapshot.captureMode, equals(CaptureMode.light),
          reason: '默认应为 LIGHT 模式');

      // 验证：toJson 序列化
      final json = snapshot.toJson();
      expect(json['type'], equals('CommandExecutionError'));
      expect(json['traceId'], equals(traceId));
      expect(json['captureMode'], equals('light'));

      // 验证：lastErrorSnapshot
      expect(snap.lastSnapshot, isNotNull);
      expect(snap.lastSnapshot!.id, equals(snapshot.id));
    });

    test('OFF 模式下不生成 ErrorSnapshot', () {
      final offSvc = ObservabilityService(
        config: const ObservabilityConfig(level: ObservabilityLevel.off),
      );

      final snapshot = offSvc.captureError(
        type: 'CommandExecutionError',
        message: 'test error',
        commandName: 'InsertTextCommand',
      );

      expect(snapshot, isNull,
          reason: 'OFF 模式下 captureError 应返回 null');
    });

    test('多次错误捕获，仅保留最近一次', () {
      final (svc, snap) = _createService();
      final traceId = TraceIdGenerator.traceId();
      svc.setTraceContext(EditorTraceContext(
        sessionId: svc.sessionId,
        traceId: traceId,
        spanId: 'span_1',
      ));

      // 第一次错误
      snap.capture(
        type: 'CommandExecutionError',
        message: 'first error',
        commandName: 'InsertTextCommand',
      );

      // 第二次错误
      final traceId2 = TraceIdGenerator.traceId();
      svc.setTraceContext(EditorTraceContext(
        sessionId: svc.sessionId,
        traceId: traceId2,
        spanId: 'span_2',
      ));
      final snapshot2 = snap.capture(
        type: 'TransactionRollback',
        message: 'rollback: unexpected state',
        commandName: 'UpdateBlockSourceCommand',
      );

      // 验证：lastSnapshot 为最近一次
      expect(snap.lastSnapshot, isNotNull);
      expect(snap.lastSnapshot!.type, equals('TransactionRollback'));
      expect(snap.lastSnapshot!.traceId, equals(traceId2));
      expect(snapshot2.traceId, equals(traceId2));
    });

    test('ErrorSnapshot 序列化 JSON 包含所有必需字段', () {
      final (svc, _) = _createService();
      final traceId = TraceIdGenerator.traceId();
      svc.setTraceContext(EditorTraceContext(
        sessionId: svc.sessionId,
        traceId: traceId,
        spanId: 'span_json',
      ));

      final svc2 = ObservabilityService(
        config: const ObservabilityConfig(
          level: ObservabilityLevel.full,
        ),
      );
      svc2.setTraceContext(EditorTraceContext(
        sessionId: svc2.sessionId,
        traceId: traceId,
        spanId: 'span_json',
      ));
      final snap2 = ErrorSnapshotter(observability: svc2);
      final snapshot = snap2.capture(
        type: 'CommandExecutionError',
        message: 'RangeError: offset 999999 exceeds source length 5',
        commandName: 'InsertTextCommand',
        commandParams: {
          'blockId': 'fake_block',
          'text': 'hello',
          'cursorOffset': 999999,
        },
        cursorBlockId: 'fake_block',
        cursorOffset: 999999,
      );

      final json = snapshot.toJson();

      // 验证 JSON 结构
      expect(json.containsKey('id'), isTrue,
          reason: 'JSON 应包含 id');
      expect(json.containsKey('timestamp'), isTrue);
      expect(json.containsKey('type'), isTrue);
      expect(json.containsKey('message'), isTrue);
      expect(json.containsKey('traceId'), isTrue);
      expect(json.containsKey('sessionId'), isTrue);
      expect(json.containsKey('captureMode'), isTrue);
      expect(json.containsKey('app'), isTrue,
          reason: 'JSON 应包含 app 信息');

      // 验证 command 子对象
      final command = json['command'] as Map<String, Object?>?;
      expect(command, isNotNull);
      expect(command!['name'], equals('InsertTextCommand'));
      expect(command['params'], isNotNull);

      // 验证 cursor 子对象
      final cursor = json['cursor'] as Map<String, Object?>?;
      expect(cursor, isNotNull);
      expect(cursor!['blockId'], equals('fake_block'));
      expect(cursor['offset'], equals(999999));
    });
  });
}