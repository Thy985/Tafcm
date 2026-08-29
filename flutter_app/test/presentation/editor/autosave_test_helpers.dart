/// AutosaveService 测试辅助：受控定时器 + 假脏源 + save 工厂。
///
/// 抽离以使主测试文件（[autosave_service_test.dart]）满足 TC-ARCH-7（test/ ≤ 400 行），
/// 并为后续 autosave 相关测试复用。
library;

import 'dart:async';

import 'package:tafcm/presentation/editor/dirty_state_source.dart';

/// 受控定时器：创建即登记，由测试显式 [fire] 触发，不占用真实时钟。
class FakeTimer implements Timer {
  bool _active = true;
  final void Function() _cb;
  FakeTimer(this._cb);

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  @override
  int get tick => 0;

  void fire() {
    if (_active) _cb();
  }
}

/// 可注入的定时器工厂（测试用）：记录每次创建的 [Duration]，并允许手动触发。
class FakeTimerFactory {
  final List<FakeTimer> timers = [];
  final List<Duration> durations = [];

  Timer call(Duration duration, void Function() callback) {
    durations.add(duration);
    final t = FakeTimer(callback);
    timers.add(t);
    return t;
  }

  /// 触发最近一个仍 active 的定时器（模拟 debounce / 退避到期）。
  void fireLast() {
    for (var i = timers.length - 1; i >= 0; i--) {
      if (timers[i].isActive) {
        timers[i].fire();
        return;
      }
    }
  }
}

/// 冲刷全部 microtask（broadcast stream 异步投递 + save 回调为 async，
/// fire 后需 pump 让其继续）。
Future<void> pump() async {
  for (var i = 0; i < 5; i++) {
    await Future.delayed(Duration.zero);
  }
}

/// 测试用脏状态源：可控 isDirty / dirtyChanges / markSaved，携带可变 [content]
/// 以模拟「触发时刻快照 vs 写盘期间新编辑」并发场景。
class FakeDirtySource implements DirtyStateSource {
  bool _dirty = false;
  String content = '';
  final StreamController<bool> _ctl = StreamController<bool>.broadcast();

  @override
  bool get isDirty => _dirty;

  @override
  Stream<bool> get dirtyChanges => _ctl.stream;

  @override
  void markSaved() => setDirty(false);

  void setDirty(bool v) {
    if (_dirty != v) {
      _dirty = v;
      _ctl.add(v);
    }
  }
}

/// 构造 save 回调（与生产 _saveDocument 同语义）：起始同步捕获快照，
/// 写盘后若 source 无新改动则 markSaved。
Future<bool> Function() makeSave({
  required FakeDirtySource src,
  required List<String> writes,
  List<Completer<void>>? gates,
}) {
  var gateIdx = 0;
  return () async {
    final snap = src.content;
    writes.add(snap);
    if (gates != null && gateIdx < gates.length) {
      await gates[gateIdx++].future;
    }
    if (src.content == snap) src.markSaved();
    return true;
  };
}

const kDebounce = Duration(milliseconds: 10);
