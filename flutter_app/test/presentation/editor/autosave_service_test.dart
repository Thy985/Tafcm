/// AutosaveService 单元测试（Phase 3.4 Slice2 / ADR-0013 验证计划）。
///
/// 覆盖：debounce 触发一次 / 连续编辑合并 / markSaved 重置 / 失败退避重试 /
/// 并发串行化 / 触发时刻快照隔离 / save=false 跳过 / 真实 Coordinator 冒烟 /
/// status 流序列 / stop 进行中不崩溃 / stop 后复用。
///
/// 用 [autosave_test_helpers] 的受控假定时器驱动，不依赖真实时钟（消除 CI flake）。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/presentation/editor/autosave_service.dart';
import 'package:formula_fix/presentation/editor/dirty_state_source.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/seed_documents.dart';

import 'autosave_test_helpers.dart';

void main() {
  group('AutosaveService（ADR-0013）', () {
    test('dirty 后 debounce 触发 save 恰好一次', () async {
      final src = FakeDirtySource()..content = 'x';
      final writes = <String>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await pump();
      expect(writes, isEmpty);
      timers.fireLast();
      await pump();
      expect(writes, ['x']);
      expect(src.isDirty, isFalse);
      await pump();
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
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      src.content = 'ab';
      src.content = 'abc';
      await pump();
      timers.fireLast();
      await pump();
      expect(writes, ['abc']);
      service.stop();
    });

    test('markSaved 后重置定时器，再次变脏才重新调度', () async {
      final src = FakeDirtySource()..content = 'x';
      final writes = <String>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await pump();
      timers.fireLast();
      await pump();
      expect(writes.length, 1);
      await pump();
      expect(writes.length, 1);
      src.setDirty(true);
      await pump();
      timers.fireLast();
      await pump();
      expect(writes.length, 2);
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
          if (attempts < 3) throw Exception('boom');
          src.markSaved();
          return true;
        },
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await pump();
      timers.fireLast();
      await pump();
      timers.fireLast();
      await pump();
      timers.fireLast();
      await pump();
      expect(attempts, 3);
      expect(src.isDirty, isFalse);
      // 退避增长：首次 = debounce，之后 ×2（10 → 10 → 20）
      expect(timers.durations, [kDebounce, kDebounce, kDebounce * 2]);
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
          if (i == 1) await gA.future;
          if (i == 2) await gB.future;
          if (src.content == snap) src.markSaved();
          order.add('end$i');
          return true;
        },
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await pump();
      timers.fireLast();
      await pump();
      expect(order, ['start1']);
      src.content = 'v2';
      gA.complete();
      await pump();
      await pump();
      expect(order, ['start1', 'end1']);
      timers.fireLast();
      await pump();
      expect(order, ['start1', 'end1', 'start2']);
      gB.complete();
      await pump();
      await pump();
      expect(order, ['start1', 'end1', 'start2', 'end2']);
      expect(writes, ['v1', 'v2']);
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
          final snap = src.content;
          writes.add(snap);
          await gA.future;
          if (src.content == snap) src.markSaved();
          return true;
        },
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await pump();
      timers.fireLast();
      await pump();
      src.content = 'v2';
      gA.complete();
      await pump();
      await pump();
      expect(src.isDirty, isTrue);
      timers.fireLast();
      await pump();
      expect(writes, ['v1', 'v2']);
      expect(src.isDirty, isFalse);
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
          return false;
        },
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      src.setDirty(true);
      await pump();
      timers.fireLast();
      await pump();
      expect(savedCalls, 1);
      expect(src.isDirty, isTrue);
      await pump();
      expect(savedCalls, 1);
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
      expect(events, [true]);

      c.markSaved();
      expect(c.isDirty, isFalse);
      expect(events, [true, false]);

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
          final snap = c.editor.allSources.join('\n');
          if (c.editor.allSources.join('\n') == snap) c.markSaved();
          saved.add(true);
          return true;
        },
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      c.updateLiveSource(editor.allIds.first, 'typed text');
      expect(c.isDirty, isTrue);
      await pump();
      timers.fireLast();
      await pump();
      expect(saved, [true]);
      expect(c.isDirty, isFalse);
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
          debounce: kDebounce,
          timerFactory: timers.call,
        );
        final sub = service.status.listen(statuses.add);
        service.start();
        src.setDirty(true);
        await pump();
        timers.fireLast();
        await pump();
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
          debounce: kDebounce,
          timerFactory: timers.call,
        );
        final sub = service.status.listen(statuses.add);
        service.start();
        src.setDirty(true);
        await pump();
        timers.fireLast();
        await pump();
        expect(
          statuses,
          containsAllInOrder([
            AutosaveStatus.saving,
            AutosaveStatus.error,
            AutosaveStatus.retrying,
          ]),
        );
        expect(statuses, isNot(contains(AutosaveStatus.idle)));
        timers.fireLast();
        await pump();
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
          await g.future;
          if (src.content == snap) src.markSaved();
          return true;
        },
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      final sub = service.status.listen(statuses.add);
      service.start();
      src.setDirty(true);
      await pump();
      timers.fireLast();
      await pump();
      expect(statuses, [AutosaveStatus.saving]);
      service.stop();
      g.complete();
      await pump();
      expect(statuses, [AutosaveStatus.saving]); // 已停止：不再发射，无异常
      await sub.cancel();
    });

    test('stop() 后可再次 start() 复用（不重建实例）', () async {
      final src = FakeDirtySource()..content = 'x';
      final writes = <String>[];
      final timers = FakeTimerFactory();
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: kDebounce,
        timerFactory: timers.call,
      );
      service.start();
      service.stop();
      final statuses = <AutosaveStatus>[];
      final sub = service.status.listen(statuses.add);
      service.start();
      src.setDirty(true);
      await pump();
      timers.fireLast();
      await pump();
      expect(writes, ['x']);
      expect(statuses, contains(AutosaveStatus.saved));
      await sub.cancel();
      service.stop();
    });
  });
}
