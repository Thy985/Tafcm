/// AutosaveService 单元测试（Phase 3.4 Slice2 / ADR-0013 验证计划）。
///
/// 覆盖 ADR-0013 §验证计划·单元：
/// - dirty 后 debounce 触发 save 恰好一次
/// - 连续编辑 debounce 合并只 save 一次
/// - markSaved 后定时器重置，不再重复 save
/// - save 失败不崩溃，指数退避自动重试直到成功
/// - 并发保存串行化（A 进行中 B 等待，不交错）
/// - 触发时刻快照隔离（A 不覆盖 B 进行中的实时 live）
/// - save 返回 false（跳过：无可写路径）时不 markSaved、不重试
/// - 真实 EditorCoordinator.dirtyChanges 冒烟（变脏发射 true / 保存发射 false）
/// - status 流序列（saving→saved / error→retrying）
/// - stop() 在 save 进行中不崩溃
/// - stop() 后可再次 start() 复用
///
/// 时序用**受控假定时器**（[FakeTimerFactory]）驱动，不依赖真实时钟，
/// 消除 CI 上因 debounce 等待过紧导致的 flake（ADR-0013 评审·测试 #4）。
/// 注意：脏状态/状态流均为 broadcast stream，事件异步投递，故每次 setDirty /
/// fire 后需 [ _pump] 冲刷 microtask，让定时器被创建/触发。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/presentation/editor/autosave_service.dart';
import 'package:formula_fix/presentation/editor/dirty_state_source.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/seed_documents.dart';

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

  /// 触发回调（仅当仍 active）。
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
/// fire 后需 pump 让其继续）。多次 zero-delay 足以排空整条 microtask 链。
Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future.delayed(Duration.zero);
  }
}

/// 测试用脏状态源：可控 isDirty / dirtyChanges / markSaved，并携带可变的 [content]
/// 以模拟「触发时刻快照 vs 写盘期间新编辑」的并发场景。
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

/// 构造 save 回调（与生产 [_saveDocument] 同语义）：
/// 在起始同步捕获 [FakeDirtySource.content] 作为快照写入，写盘后若 source 无新改动则 markSaved。
Future<bool> Function() makeSave({
  required FakeDirtySource src,
  required List<String> writes,
  List<Completer<void>>? gates,
}) {
  var gateIdx = 0;
  return () async {
    final snap = src.content; // 触发时刻快照（同步读取）
    writes.add(snap);
    if (gates != null && gateIdx < gates.length) {
      await gates[gateIdx++].future; // 受控完成（模拟写盘耗时）
    }
    // 写盘后：source 无新改动才 markSaved（否则保留 dirty，由 service 重调度）。
    if (src.content == snap) src.markSaved();
    return true;
  };
}

const _kDebounce = Duration(milliseconds: 10);

void main() {
  group('AutosaveService（ADR-0013）', () {
    test('dirty 后 debounce 触发 save 恰好一次', () async {
      final src = FakeDirtySource()..content = 'x';
      final writes = <String>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await _pump(); // 脏事件异步投递 → _schedule 创建定时器
      expect(writes, isEmpty);
      timers.fireLast(); // debounce 到期
      await _pump();
      expect(writes, ['x']); // 一次保存，快照 = 触发时刻内容
      expect(src.isDirty, isFalse); // save 回调已 markSaved
      await _pump();
      expect(writes, ['x']); // 不再重复
      service.stop();
    });

    test('连续编辑 debounce 合并只 save 一次（捕获最新内容）', () async {
      final src = FakeDirtySource()..content = 'a';
      final writes = <String>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true); // 翻转 → 调度
      src.content = 'ab'; // 已 dirty，无翻转，但内容变了
      src.content = 'abc';
      await _pump(); // 脏事件投递 → 定时器已创建
      timers.fireLast(); // 单一 debounce 窗口后触发
      await _pump();
      expect(writes, ['abc']); // 捕获合并窗口内最后一次内容
      service.stop();
    });

    test('markSaved 后重置定时器，再次变脏才重新调度', () async {
      final src = FakeDirtySource()..content = 'x';
      final writes = <String>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await _pump();
      timers.fireLast();
      await _pump();
      expect(writes.length, 1);
      await _pump();
      expect(writes.length, 1); // 无新编辑 → 不重复
      src.setDirty(true); // 再次变脏
      await _pump();
      timers.fireLast();
      await _pump();
      expect(writes.length, 2); // 重新调度保存
      service.stop();
    });

    test('save 失败不崩溃，指数退避自动重试直到成功', () async {
      final src = FakeDirtySource()..content = 'x';
      var attempts = 0;
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: () async {
          attempts++;
          if (attempts < 3) throw Exception('boom'); // 前两次失败
          src.markSaved(); // 第三次成功
          return true;
        },
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await _pump();
      timers.fireLast();
      await _pump(); // 失败 1 → 退避重试（创建重试定时器）
      timers.fireLast();
      await _pump(); // 失败 2 → 退避重试
      timers.fireLast();
      await _pump(); // 成功
      expect(attempts, 3); // 重试直到成功（失败不崩溃）
      expect(src.isDirty, isFalse);
      // 退避增长：首次 = debounce，之后 ×2（10 → 10 → 20）
      expect(timers.durations, [_kDebounce, _kDebounce, _kDebounce * 2]);
      service.stop();
    });

    test('并发保存串行化：A 进行中 B 等待，不交错', () async {
      final src = FakeDirtySource()..content = 'v1';
      final writes = <String>[];
      final order = <String>[];
      final gA = Completer<void>();
      final gB = Completer<void>();
      var idx = 0;
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: () async {
          final i = ++idx;
          order.add('start$i');
          final snap = src.content;
          writes.add(snap);
          if (i == 1) await gA.future; // A 受控
          if (i == 2) await gB.future; // B 受控
          if (src.content == snap) src.markSaved();
          order.add('end$i');
          return true;
        },
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await _pump();
      timers.fireLast(); // A 开始并 await gA
      await _pump();
      expect(order, ['start1']); // A 进行中

      // 模拟 A 写盘期间产生新编辑（content 变化，dirty 已为 true 无翻转事件）
      src.content = 'v2';
      gA.complete(); // 完成 A
      await _pump();
      await _pump();
      expect(order, ['start1', 'end1']); // A 完整结束，B 尚未开始（串行）

      timers.fireLast(); // B 触发（start2，await gB）
      await _pump();
      expect(order, ['start1', 'end1', 'start2']);
      gB.complete(); // 完成 B
      await _pump();
      await _pump();
      expect(order, ['start1', 'end1', 'start2', 'end2']);
      expect(writes, ['v1', 'v2']); // A 写 v1、B 写 v2，不交错
      service.stop();
    });

    test('触发时刻快照隔离：A 不覆盖 B 进行中的实时 live', () async {
      final src = FakeDirtySource()..content = 'v1';
      final writes = <String>[];
      final gA = Completer<void>();
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: () async {
          final snap = src.content; // 触发时刻快照
          writes.add(snap);
          await gA.future; // 受控完成
          // 写盘期间 content 可能已变；回调按「写盘后是否仍为同一快照」决定是否 markSaved
          if (src.content == snap) src.markSaved();
          return true;
        },
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await _pump();
      timers.fireLast(); // A 捕获 snap='v1' 并 await gA
      await _pump();
      // A 进行中用户继续输入 → content 变为 v2（实时 live）
      src.content = 'v2';
      gA.complete();
      await _pump();
      await _pump();
      // A 写盘期间 content 已变 → 不 markSaved → service 重调度 B
      expect(src.isDirty, isTrue);
      timers.fireLast(); // B 触发，捕获 v2
      await _pump();
      expect(writes, ['v1', 'v2']); // 最终落盘 = 最后一次成功 save 的 source（v2）
      expect(src.isDirty, isFalse); // B 写盘后 content 未变 → markSaved
      service.stop();
    });

    test('save 返回 false（跳过：无可写路径）时不 markSaved、不重试', () async {
      final src = FakeDirtySource()..content = 'x';
      var savedCalls = 0;
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: () async {
          savedCalls++;
          return false; // 跳过
        },
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await _pump();
      timers.fireLast();
      await _pump();
      expect(savedCalls, 1);
      expect(src.isDirty, isTrue); // 保留 dirty（未误标已保存）
      await _pump();
      expect(savedCalls, 1); // 不空转重试
      service.stop();
    });

    test('真实 EditorCoordinator.dirtyChanges 随变脏/保存发射', () async {
      final editor = SeedDocuments.createDemo1();
      final c = EditorCoordinator(editor: editor, history: EditorHistory());
      final events = <bool>[];
      final sub = c.dirtyChanges.listen(events.add);

      expect(c.isDirty, isFalse);
      c.updateLiveSource(editor.allIds.first, '与已提交不同的实时文本');
      expect(c.isDirty, isTrue);
      expect(events, [true]); // 一次翻转发射

      c.markSaved();
      expect(c.isDirty, isFalse);
      expect(events, [true, false]); // 保存后发射 false

      await sub.cancel();
      c.dispose();
    });

    test('AutosaveService + 真实 Coordinator：变脏→保存→markSaved', () async {
      final editor = SeedDocuments.createDemo1();
      final c = EditorCoordinator(editor: editor, history: EditorHistory());
      final saved = <bool>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: c,
        save: () async {
          // 模仿生产 _saveDocument：写盘后若 source 无新改动则 markSaved
          final snap = c.editor.allSources.join('\n');
          if (c.editor.allSources.join('\n') == snap) c.markSaved();
          saved.add(true);
          return true;
        },
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      c.updateLiveSource(editor.allIds.first, 'typed text');
      expect(c.isDirty, isTrue);
      await _pump();
      timers.fireLast();
      await _pump();
      expect(saved, [true]);
      expect(c.isDirty, isFalse); // 被 save 回调 markSaved
      service.stop();
      c.dispose();
    });

    group('status 流（chrome 轻提示）', () {
      test('变脏→保存：发射 saving → saved', () async {
        final src = FakeDirtySource()..content = 'x';
        final statuses = <AutosaveStatus>[];
        final timers = FakeTimerFactory();
        final service = AutosaveService(
          source: src,
          save: makeSave(src: src, writes: []),
          debounce: _kDebounce,
          timerFactory: timers.call,
        );
        final sub = service.status.listen(statuses.add);
        service.start();
        src.setDirty(true);
        await _pump();
        timers.fireLast();
        await _pump();
        expect(
          statuses,
          containsAllInOrder([AutosaveStatus.saving, AutosaveStatus.saved]),
        );
        await sub.cancel();
        service.stop();
      });

      test('保存失败：发射 error → retrying，且不误发 idle', () async {
        final src = FakeDirtySource()..content = 'x';
        final statuses = <AutosaveStatus>[];
        final timers = FakeTimerFactory();
        var attempts = 0;
        final service = AutosaveService(
          source: src,
          save: () async {
            attempts++;
            if (attempts == 1) throw Exception('boom');
            src.markSaved();
            return true;
          },
          debounce: _kDebounce,
          timerFactory: timers.call,
        );
        final sub = service.status.listen(statuses.add);
        service.start();
        src.setDirty(true);
        await _pump();
        timers.fireLast(); // 失败 → error, retrying
        await _pump();
        expect(
          statuses,
          containsAllInOrder([
            AutosaveStatus.saving,
            AutosaveStatus.error,
            AutosaveStatus.retrying,
          ]),
        );
        expect(statuses, isNot(contains(AutosaveStatus.idle))); // 重试中不误发 idle
        timers.fireLast(); // 重试成功
        await _pump();
        expect(attempts, 2);
        expect(statuses, contains(AutosaveStatus.saved));
        await sub.cancel();
        service.stop();
      });
    });

    test('stop() 在 save 进行中调用：不崩溃，状态流已关闭', () async {
      final src = FakeDirtySource()..content = 'x';
      final g = Completer<void>();
      final statuses = <AutosaveStatus>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: () async {
          final snap = src.content;
          await g.future; // 受控进行中
          if (src.content == snap) src.markSaved();
          return true;
        },
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      final sub = service.status.listen(statuses.add);
      service.start();
      src.setDirty(true);
      await _pump();
      timers.fireLast(); // save 进入 await g
      await _pump();
      expect(statuses, [AutosaveStatus.saving]);
      service.stop(); // 关闭 status controller（save 仍在 await g）
      g.complete(); // 唤醒 save 继续 → _emit 守卫 isClosed 不崩溃
      await _pump();
      // 已停止：不再发射，且未发生异常
      expect(statuses, [AutosaveStatus.saving]);
      await sub.cancel();
    });

    test('stop() 后可再次 start() 复用（不重建实例）', () async {
      final src = FakeDirtySource()..content = 'x';
      final writes = <String>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: _kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      service.stop();
      // 再次 start：应重新订阅且 status 流可再订阅
      final statuses = <AutosaveStatus>[];
      final sub = service.status.listen(statuses.add);
      service.start();
      src.setDirty(true);
      await _pump();
      timers.fireLast();
      await _pump();
      expect(writes, ['x']);
      expect(statuses, contains(AutosaveStatus.saved));
      await sub.cancel();
      service.stop();
    });
  });
}
