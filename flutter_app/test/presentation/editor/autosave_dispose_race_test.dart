/// 自动保存生命周期竞态回归测试（#341 E2E 定向验收发现的真实异常）。
///
/// **根因**：`EditorPage.dispose()` 中 `_autosave.stop()` 与
/// `_coordinator.dispose()` 之间存在时间窗口。若 save 回调正在
/// `await writeDocument` 间隙挂起，则：
///
/// 1. `_autosave.stop()` → `_running = false`，取消 timer / 关闭 status 流
/// 2. `_coordinator.dispose()` → `DirtyStateTracker._ctl.close()`
/// 3. 在飞的 save 回调继续执行 → `markSaved()` → `notifyListeners()`
///    → `DirtyStateTracker.sync()` → 对已关闭的 `_ctl` 调 `add`
///    → **StateError: Cannot add new events after calling close**
///
/// **数据影响**：无——`await writeDocument` 已成功返回，异常发生在写盘**之后**
/// 的脏标记簿记。但异常被 `_saveOnce` 的 catch 误分类为"持久化失败"，
/// 触发 `_scheduleRetry()` 在已 stopped 的服务上创建新 Timer（泄漏）。
///
/// **修复**：
/// - Fix 1 — `DirtyStateTracker.sync()`：`_ctl.isClosed` 守卫（防 `add` 抛异常）
/// - Fix 2 — `AutosaveService._running`：`_schedule` / `_scheduleRetry` 早退
///  （防 Timer 泄漏）
///
/// **验证**：用真实 `EditorCoordinator`（含真实 `DirtyStateTracker`）构造竞态，
/// 确认修复后无异常、无 Timer 泄漏、onError 不被误触发。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/presentation/editor/autosave_service.dart';
import 'package:tafcm/presentation/editor/dirty_state_source.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/seed_documents.dart';

import 'autosave_test_helpers.dart';

void main() {
  group('AutosaveService dispose 竞态（#341 E2E 发现的真实异常）', () {
    test('DirtyStateTracker.sync() 在 dispose 后调用：不抛异常', () {
      final tracker = DirtyStateTracker(() => false);
      tracker.sync(); // false → 无翻转，无事件
      tracker.dispose();
      // 模拟协调器在 dispose 后被调用（在飞 save 回调的 markSaved → sync）
      expect(() => tracker.sync(), returnsNormally);
    });

    test('DirtyStateTracker.sync() 在 dispose 后有翻转：不抛异常', () {
      var dirty = false;
      final tracker = DirtyStateTracker(() => dirty);
      tracker.sync();
      dirty = true;
      tracker.sync(); // true → 发射 true
      tracker.dispose();
      dirty = false;
      // 翻转发生但 ctl 已关闭：应被 isClosed 守卫吞掉
      expect(() => tracker.sync(), returnsNormally);
    });

    test(
        'stop() 在 save 进行中调用，save 回调经 markSaved 抵达已 dispose 的协调器：'
        '无异常、无 Timer 泄漏、onError 不被误触发',
        () async {
      // 用真实 EditorCoordinator（含真实 DirtyStateTracker），
      // 精确复现 EditorPage.dispose() 的时序。
      final editor = SeedDocuments.createDemo1();
      final coordinator =
          EditorCoordinator(editor: editor, history: EditorHistory());
      final writes = <String>[];
      final timers = FakeTimerFactory();
      final saveGate = Completer<void>();
      final errors = <Object>[];

      final service = AutosaveService(
        source: coordinator,
        save: () async {
          // 与 EditorPage._saveDocument 同语义：起始同步捕获快照，
          // 写盘后若 source 无新改动则 markSaved。
          final snap = editor.serializedContent;
          writes.add(snap);
          await saveGate.future; // 模拟写盘耗时，制造 dispose 竞态窗口
          if (editor.serializedContent == snap) coordinator.markSaved();
          return true;
        },
        debounce: kDebounce,
        timerFactory: timers.call,
        onError: (e, _) => errors.add(e),
      );

      final statuses = <AutosaveStatus>[];
      final sub = service.status.listen(statuses.add);

      service.start();
      // 变脏 → 调度 debounce
      coordinator.updateLiveSource(editor.allIds.first, 'typed text');
      await pump();
      // 触发保存（save 回调将在 await 间隙挂起）
      timers.fireLast();
      await pump();

      final timerCountBeforeDispose = timers.timers.length;

      // 模拟 EditorPage.dispose() 时序：stop() + coordinator.dispose()
      service.stop();
      coordinator.dispose();

      final timerCountAfterStop = timers.timers.length;

      // 放行 save 回调：继续执行 markSaved（协调器已 dispose）
      saveGate.complete();
      await pump();
      await pump(); // 多泵几轮，确保异步链完全展开

      // 验证 1：save 回调成功执行（数据已落盘）
      expect(writes, isNotEmpty, reason: 'save 回调应已成功执行');

      // 验证 2：无 Timer 泄漏（stop 后不再创建 Timer）
      expect(
        timerCountAfterStop,
        timerCountBeforeDispose,
        reason: 'stop() 瞬间不应创建新 Timer',
      );
      expect(
        timers.timers.length,
        timerCountAfterStop,
        reason: '在飞 save 回调完成后不应创建新 Timer（避免对已 stopped '
            '服务调度重试）',
      );

      // 验证 3：状态流已关闭，不再发射 saved
      expect(
        statuses,
        contains(AutosaveStatus.saving),
        reason: 'save 启动时应已发射 saving',
      );

      // 验证 4（关键）：onError 未被调用。
      // 当 Fix 1（isClosed 守卫）生效时：sync() 不抛异常 → markSaved 正常完成
      // → save 返回 true → _saveOnce 不进 catch → onError 不被调用。
      // 当 Fix 1 失效时：sync() 抛 StateError → save 抛出 → _saveOnce catch 吞掉
      // → onError 被调用（生产环境中表现为 "[EditorPage] autosave failed:
      // Bad state: Cannot add new events..."，即被误分类为"持久化失败"）。
      // 这个断言是区分"真正修复"与"异常被 catch 静默吞掉"的关键证据。
      expect(
        errors,
        isEmpty,
        reason: 'sync() 的 isClosed 守卫应防止 StateError 被 _saveOnce 的 '
            'catch 误分类为"持久化失败"并触发 onError',
      );

      await sub.cancel();
    });
  });
}
