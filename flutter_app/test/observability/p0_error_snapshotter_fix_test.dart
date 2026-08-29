/// P0 修复（2026-08-04）验证测试：ObservabilityService 自动创建 ErrorSnapshotter。
///
/// 验证三项 P0 修复：
/// - B-1: `ObservabilityService()` 无参构造在 LIGHT/FULL 模式自动创建 ErrorSnapshotter
/// - B-2: `captureError()` 在 LIGHT 模式下返回非 null（不再空操作）
/// - B-3: `lastErrorSnapshot` 在 captureError 后可读取（不再永远 null）
///
/// 修复前：`observabilityProvider` 用 `ObservabilityService()` 无参构造，
/// errorSnapshotter 永远为 null，captureError 空操作，snapshot.json 永远缺失。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/observability/models.dart';
import 'package:tafcm/core/observability/observability_service.dart';
import 'package:tafcm/core/observability/trace_context.dart';

void main() {
  setUp(() {
    TraceIdGenerator.reset();
  });

  group('P0 B-1: ObservabilityService 自动创建 ErrorSnapshotter', () {
    test('LIGHT 模式（默认）无参构造 → errorSnapshotter 非 null', () {
      final svc = ObservabilityService();
      expect(svc.errorSnapshotter, isNotNull,
          reason: 'P0 修复前： ObservabilityService() 无参构造时 '
              'errorSnapshotter 永远为 null，导致 captureError 空操作。'
              'P0 修复后： LIGHT 模式自动创建 ErrorSnapshotter。');
    });

    test('FULL 模式无参构造 → errorSnapshotter 非 null', () {
      final svc = ObservabilityService(
        config: const ObservabilityConfig(
          level: ObservabilityLevel.full,
        ),
      );
      expect(svc.errorSnapshotter, isNotNull,
          reason: 'FULL 模式同样应自动创建 ErrorSnapshotter。');
    });

    test('OFF 模式无参构造 → errorSnapshotter 为 null', () {
      final svc = ObservabilityService(
        config: const ObservabilityConfig(level: ObservabilityLevel.off),
      );
      expect(svc.errorSnapshotter, isNull,
          reason: 'OFF 模式不应创建 ErrorSnapshotter（tree-shaking）。');
    });

    test('外部注入 mock 时优先用 mock（不被自动创建覆盖）', () {
      final svc = ObservabilityService();
      final mockSnapshotter = svc.errorSnapshotter!;
      // 用已自动创建的 snapshotter 重新构造
      final svc2 = ObservabilityService(
        errorSnapshotter: mockSnapshotter,
      );
      expect(identical(svc2.errorSnapshotter, mockSnapshotter), isTrue,
          reason: '外部注入的 errorSnapshotter 应优先于自动创建。');
    });
  });

  group('P0 B-2: captureError 在 LIGHT 模式下返回非 null', () {
    test('captureError 返回完整 ErrorSnapshot', () {
      final svc = ObservabilityService();
      final snapshot = svc.captureError(
        type: 'GlobalError',
        message: 'Test error for P0 verification',
      );
      expect(snapshot, isNotNull,
          reason: 'P0 修复前： captureError 永远返回 null（errorSnapshotter 为 null）。'
              'P0 修复后： 返回完整 ErrorSnapshot。');
      expect(snapshot!.type, equals('GlobalError'));
      expect(snapshot.message, contains('Test error for P0 verification'));
      expect(snapshot.sessionId, equals(svc.sessionId),
          reason: 'snapshot 应携带当前会话 ID');
    });

    test('captureError 携带 trace context（若已设置）', () {
      final svc = ObservabilityService();
      final traceId = TraceIdGenerator.traceId();
      svc.setTraceContext(EditorTraceContext(
        sessionId: svc.sessionId,
        traceId: traceId,
        spanId: 'span_p0_test',
      ));
      final snapshot = svc.captureError(
        type: 'CommandExecutionError',
        message: 'cmd failed',
        commandName: 'InsertTextCommand',
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.traceId, equals(traceId),
          reason: 'snapshot 应携带当前 traceId');
      expect(snapshot.commandName, equals('InsertTextCommand'));
    });

    test('OFF 模式下 captureError 仍返回 null', () {
      final svc = ObservabilityService(
        config: const ObservabilityConfig(level: ObservabilityLevel.off),
      );
      final snapshot = svc.captureError(
        type: 'GlobalError',
        message: 'should be null',
      );
      expect(snapshot, isNull,
          reason: 'OFF 模式应短路返回 null，不创建 ErrorSnapshotter。');
    });
  });

  group('P0 B-3: lastErrorSnapshot 可读取（snapshot.json 不再缺失）', () {
    test('captureError 后 lastErrorSnapshot 非 null', () {
      final svc = ObservabilityService();
      expect(svc.lastErrorSnapshot, isNull,
          reason: '初始状态应为 null');

      final snapshot = svc.captureError(
        type: 'TransactionRollback',
        message: 'unexpected rollback',
      );
      expect(snapshot, isNotNull);

      expect(svc.lastErrorSnapshot, isNotNull,
          reason: 'P0 修复前： lastErrorSnapshot 永远为 null（因 errorSnapshotter 为 null，'
              'getter 短路返回 null），导致诊断 zip 中 snapshot.json 永远缺失。'
              'P0 修复后： lastErrorSnapshot 返回最近一次捕获的 ErrorSnapshot。');
      expect(svc.lastErrorSnapshot!.id, equals(snapshot!.id),
          reason: 'lastErrorSnapshot 应与最近一次 captureError 返回值一致');
    });

    test('多次 captureError 后 lastErrorSnapshot 为最近一次', () {
      final svc = ObservabilityService();
      svc.captureError(type: 'GlobalError', message: 'first');
      // 验证第一次已记录
      expect(svc.lastErrorSnapshot!.message, contains('first'));

      svc.captureError(type: 'GlobalError', message: 'second');
      // 注意：ErrorSnapshotter 的 ID 基于秒级时间戳（_generateId），
      // 同一秒内多次 capture 会生成相同 ID。这是既有设计，不是 P0 修复范围。
      // 此处只验证 lastErrorSnapshot 指向最近一次（message 为 second）。
      expect(svc.lastErrorSnapshot!.message, contains('second'),
          reason: 'lastErrorSnapshot 应为最近一次（second）');
    });

    test('ErrorSnapshot 含 appVersion / device / os 字段（默认空）', () {
      // 注意：setAppInfo 在 main.dart 调用，单元测试不调用时字段为空。
      // 此测试验证字段存在且可序列化，不验证具体值。
      final svc = ObservabilityService();
      final snapshot = svc.captureError(
        type: 'GlobalError',
        message: 'test',
      );
      expect(snapshot, isNotNull);
      final json = snapshot!.toJson();
      expect(json.containsKey('app'), isTrue,
          reason: 'JSON 应包含 app 字段（version/device/os）');
      final app = json['app'] as Map<String, Object?>;
      expect(app.containsKey('version'), isTrue);
      expect(app.containsKey('device'), isTrue);
      expect(app.containsKey('os'), isTrue);
    });
  });

  group('P0 B-1 回归守门：observabilityProvider 无参构造不再丢失 ErrorSnapshotter', () {
    test('模拟 observabilityProvider 的生产构造方式', () {
      // 生产代码（editor_providers.dart）：
      //   final observabilityProvider = Provider<ObservabilityService>((ref) {
      //     return ObservabilityService();
      //   });
      // 此测试模拟该构造，确保 P0 修复后 errorSnapshotter 非 null。
      final svc = ObservabilityService();
      expect(svc.errorSnapshotter, isNotNull,
          reason: 'observabilityProvider 用 ObservabilityService() 无参构造，'
              'P0 修复前 errorSnapshotter 永远为 null。'
              '此测试为回归守门：若未来误改回 final 字段 + 无自动创建，此测试会失败。');
      expect(svc.captureError(type: 'GlobalError', message: 'regression'), isNotNull,
          reason: 'captureError 应返回非 null');
    });
  });
}
