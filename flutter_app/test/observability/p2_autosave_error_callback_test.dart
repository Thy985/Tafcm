/// P2-1 测试：AutosaveService 错误回调注入。
///
/// 验证：
/// - save 回调抛异常时 onError 被调用，携带 error + stack
/// - onError 为 null 时向后兼容（不崩溃，仍走退避重试）
/// - 退避重试行为不受 onError 注入影响
/// - onError 携带的 stack 非空（可用于诊断）
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/presentation/editor/autosave_service.dart';
import 'package:tafcm/presentation/editor/dirty_state_source.dart';

import '../presentation/editor/autosave_test_helpers.dart';

void main() {
  group('P2-1: AutosaveService 错误回调注入', () {
    test('save 抛异常时 onError 被调用，携带 error + stack', () async {
      final source = _DummyDirtySource();
      final timerFactory = FakeTimerFactory();
      Object? capturedError;
      StackTrace? capturedStack;

      final svc = AutosaveService(
        source: source,
        save: () async => throw Exception('disk full'),
        timerFactory: timerFactory.call,
        onError: (error, stack) {
          capturedError = error;
          capturedStack = stack;
        },
      );
      svc.start();

      // 关键顺序：markDirty → pump（让 stream 事件送达，创建 timer）→ fireLast → pump（让 async save 完成）
      source.markDirty();
      await pump();
      timerFactory.fireLast();
      await pump();

      expect(capturedError, isNotNull);
      expect(capturedError.toString(), contains('disk full'));
      expect(capturedStack, isNotNull,
          reason: 'stack 应非空，用于诊断 zip 还原失败现场');
      svc.stop();
    });

    test('onError 为 null 时向后兼容（不崩溃，仍退避重试）', () async {
      final source = _DummyDirtySource();
      final timerFactory = FakeTimerFactory();

      final svc = AutosaveService(
        source: source,
        save: () async => throw Exception('permission denied'),
        timerFactory: timerFactory.call,
        // 不注入 onError，验证向后兼容
      );
      svc.start();

      source.markDirty();
      await pump();
      // 应该不抛异常
      timerFactory.fireLast();
      await pump();

      // 应该排入重试（第 2 个 timer 是退避 timer）
      expect(timerFactory.timers.length, greaterThanOrEqualTo(2),
          reason: '失败后应排入退避重试 timer');
      svc.stop();
    });

    test('退避重试行为不受 onError 注入影响', () async {
      final source = _DummyDirtySource();
      final timerFactory = FakeTimerFactory();
      var saveCallCount = 0;
      var errorCallCount = 0;

      final svc = AutosaveService(
        source: source,
        save: () async {
          saveCallCount++;
          throw Exception('persistent failure');
        },
        timerFactory: timerFactory.call,
        onError: (error, stack) {
          errorCallCount++;
        },
      );
      svc.start();

      // 第一次 save 失败
      source.markDirty();
      await pump();
      timerFactory.fireLast();
      await pump();
      expect(saveCallCount, equals(1));
      expect(errorCallCount, equals(1));

      // 退避 timer 触发第二次 save（仍失败）
      timerFactory.fireLast();
      await pump();
      expect(saveCallCount, equals(2));
      expect(errorCallCount, equals(2),
          reason: '每次失败都应触发 onError');

      svc.stop();
    });

    test('onError 携带的 error 类型保留原始异常', () async {
      final source = _DummyDirtySource();
      final timerFactory = FakeTimerFactory();
      Object? captured;

      final svc = AutosaveService(
        source: source,
        save: () async => throw StateError('specific error type'),
        timerFactory: timerFactory.call,
        onError: (error, stack) {
          captured = error;
        },
      );
      svc.start();

      source.markDirty();
      await pump();
      timerFactory.fireLast();
      await pump();

      expect(captured, isA<StateError>(),
          reason: '应保留原始异常类型，便于 observability 分类');
      expect((captured as StateError).message, equals('specific error type'));
      svc.stop();
    });

    test('save 成功时不触发 onError', () async {
      final source = _DummyDirtySource();
      final timerFactory = FakeTimerFactory();
      var errorCallCount = 0;

      final svc = AutosaveService(
        source: source,
        save: () async => true, // 成功
        timerFactory: timerFactory.call,
        onError: (error, stack) {
          errorCallCount++;
        },
      );
      svc.start();

      source.markDirty();
      await pump();
      timerFactory.fireLast();
      await pump();

      expect(errorCallCount, equals(0),
          reason: 'save 成功时不应触发 onError');
      svc.stop();
    });
  });
}

/// 最小化 DirtyStateSource 实现，用于测试。
class _DummyDirtySource implements DirtyStateSource {
  final _dirtyCtl = StreamController<bool>.broadcast();
  bool _dirty = false;

  @override
  bool get isDirty => _dirty;

  @override
  Stream<bool> get dirtyChanges => _dirtyCtl.stream;

  void markDirty() {
    _dirty = true;
    _dirtyCtl.add(true);
  }

  @override
  void markSaved() {
    _dirty = false;
    _dirtyCtl.add(false);
  }

  void dispose() => _dirtyCtl.close();
}
