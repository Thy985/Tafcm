/// AutosaveService 单元测试（Phase 3.4 Slice2 / ADR-0013 验证计划）。
///
/// 覆盖 ADR-0013 §验证计划·单元：
/// - dirty 后 1.5s（此处注入 10ms）触发 save 恰好一次
/// - 连续编辑 debounce 合并只 save 一次
/// - markSaved 后定时器重置，不再重复 save
/// - save 失败不崩溃，下次重试
/// - 并发保存串行化（A 进行中 B 等待，不交错）
/// - 触发时刻快照隔离（A 不覆盖 B 进行中的实时 live）
/// - save 返回 false（跳过：无可写路径）时不 markSaved、不重试
/// - 真实 EditorCoordinator.dirtyChanges 冒烟（变脏发射 true / 保存发射 false）
///
/// 时序用「小 debounce + 真实等待」驱动，避免引入额外时钟依赖。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/presentation/editor/autosave_service.dart';
import 'package:formula_fix/presentation/editor/dirty_state_source.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/seed_documents.dart';

/// 测试用脏状态源：可控 isDirty / dirtyChanges / markSaved，并携带可变的 [content]
/// 以模拟「触发时刻快照 vs 写盘期间新编辑」的并发场景。
class FakeDirtySource implements DirtyStateSource {
  bool _dirty = false;
  String content = '';
  final List<void Function()> markSavedCalls = [];
  final StreamController<bool> _ctl = StreamController<bool>.broadcast();

  @override
  bool get isDirty => _dirty;

  @override
  Stream<bool> get dirtyChanges => _ctl.stream;

  @override
  void markSaved() {
    markSavedCalls.add(() {});
    setDirty(false);
  }

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
const _kWait = Duration(milliseconds: 40);

void main() {
  group('AutosaveService（ADR-0013）', () {
    test('dirty 后 debounce 触发 save 恰好一次', () async {
      final src = FakeDirtySource()..content = 'x';
      final writes = <String>[];
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: _kDebounce,
      );
      service.start();
      src.setDirty(true);
      expect(writes, isEmpty);
      await Future.delayed(_kWait);
      expect(writes, ['x']); // 一次保存，快照 = 触发时刻内容
      expect(src.isDirty, isFalse); // save 回调已 markSaved
      await Future.delayed(_kWait);
      expect(writes, ['x']); // 不再重复
      service.stop();
    });

    test('连续编辑 debounce 合并只 save 一次（捕获最新内容）', () async {
      final src = FakeDirtySource()..content = 'a';
      final writes = <String>[];
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: _kDebounce,
      );
      service.start();
      src.setDirty(true); // 翻转 → 调度
      await Future.delayed(const Duration(milliseconds: 4));
      src.content = 'ab'; // 已 dirty，无翻转，但内容变了
      await Future.delayed(const Duration(milliseconds: 4));
      src.content = 'abc';
      await Future.delayed(_kWait);
      // 一次保存，快照 = 最后一次内容（debounce 合并窗口内的编辑）
      expect(writes, ['abc']);
      service.stop();
    });

    test('markSaved 后重置定时器，再次变脏才重新调度', () async {
      final src = FakeDirtySource()..content = 'x';
      final writes = <String>[];
      final service = AutosaveService(
        source: src,
        save: makeSave(src: src, writes: writes),
        debounce: _kDebounce,
      );
      service.start();
      src.setDirty(true);
      await Future.delayed(_kWait);
      expect(writes.length, 1);
      await Future.delayed(_kWait);
      expect(writes.length, 1); // 无新编辑 → 不重复
      src.setDirty(true); // 再次变脏
      await Future.delayed(_kWait);
      expect(writes.length, 2); // 重新调度保存
      service.stop();
    });

    test('save 失败不崩溃，自动重试直到成功', () async {
      final src = FakeDirtySource()..content = 'x';
      var attempts = 0;
      final service = AutosaveService(
        source: src,
        save: () async {
          attempts++;
          if (attempts < 3) throw Exception('boom'); // 前两次失败
          src.markSaved(); // 第三次成功
          return true;
        },
        debounce: _kDebounce,
      );
      service.start();
      src.setDirty(true);
      // 失败会立即重新调度（即使无新 dirty 事件），最终重试到成功。
      await Future.delayed(const Duration(milliseconds: 120));
      expect(attempts, 3); // 重试直到成功（证明失败不崩溃 + 自动重试）
      expect(src.isDirty, isFalse);
      service.stop();
    });

    test('并发保存串行化：A 进行中 B 等待，不交错', () async {
      final src = FakeDirtySource()..content = 'v1';
      final writes = <String>[];
      final order = <String>[];
      final gA = Completer<void>();
      final gB = Completer<void>();
      var idx = 0;
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
      );
      service.start();
      src.setDirty(true);
      await Future.delayed(_kWait); // A 开始并 await gA
      expect(order, ['start1']); // A 进行中

      // 模拟 A 写盘期间产生新编辑（content 变化，dirty 已为 true 无翻转事件）
      src.content = 'v2';
      gA.complete(); // 完成 A
      await Future.delayed(const Duration(milliseconds: 5)); // A 结束 + B 被调度
      expect(order, ['start1', 'end1']); // A 完整结束，B 尚未开始（串行）

      await Future.delayed(_kWait); // B 触发（start2，await gB）
      expect(order, ['start1', 'end1', 'start2']);
      gB.complete(); // 完成 B
      await Future.delayed(const Duration(milliseconds: 5)); // B 结束
      expect(order, ['start1', 'end1', 'start2', 'end2']);
      expect(writes, ['v1', 'v2']); // A 写 v1、B 写 v2，不交错
      service.stop();
    });

    test('触发时刻快照隔离：A 不覆盖 B 进行中的实时 live', () async {
      final src = FakeDirtySource()..content = 'v1';
      final writes = <String>[];
      final gA = Completer<void>();
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
      );
      service.start();
      src.setDirty(true);
      await Future.delayed(_kWait); // A 捕获 snap='v1' 并 await gA
      // A 进行中用户继续输入 → content 变为 v2（实时 live）
      src.content = 'v2';
      gA.complete();
      await Future.delayed(const Duration(milliseconds: 5));
      // A 写盘期间 content 已变 → 不 markSaved → service 重调度 B
      expect(src.isDirty, isTrue);
      await Future.delayed(_kWait); // B 触发，捕获 v2
      expect(writes, ['v1', 'v2']); // 最终落盘 = 最后一次成功 save 的 source（v2）
      expect(src.isDirty, isFalse); // B 写盘后 content 未变 → markSaved
      service.stop();
    });

    test('save 返回 false（跳过：无可写路径）时不 markSaved、不重试', () async {
      final src = FakeDirtySource()..content = 'x';
      var savedCalls = 0;
      final service = AutosaveService(
        source: src,
        save: () async {
          savedCalls++;
          return false; // 跳过
        },
        debounce: _kDebounce,
      );
      service.start();
      src.setDirty(true);
      await Future.delayed(_kWait);
      expect(savedCalls, 1);
      expect(src.isDirty, isTrue); // 保留 dirty（未误标已保存）
      await Future.delayed(_kWait);
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
      );
      service.start();
      c.updateLiveSource(editor.allIds.first, 'typed text');
      expect(c.isDirty, isTrue);
      await Future.delayed(_kWait);
      expect(saved, [true]);
      expect(c.isDirty, isFalse); // 被 save 回调 markSaved
      service.stop();
      c.dispose();
    });
  });
}
