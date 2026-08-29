/// P0 回归测试：真机问题 1+5 — focusOn viewState 缺失修复。
///
/// **背景**（phase3.5-realdevice-issues.md 问题 1+5）：
/// 新块由 InsertBlockAfterCommand / SplitBlockCommand 创建后，
/// 其 BlockViewState 尚未注入 CoordinatorState.viewStates。
/// 原代码 focusOn 中 curState == null 时跳过，导致：
/// - focusedId 指向新块但 viewState 缺失
/// - UI 兜底为 rendered 态
/// - setFocus 幂等守卫使点击无效
/// - IME 收起（didUpdateWidget 不触发 requestFocus）
///
/// **修复**：focusOn 在 curState == null 时创建默认 editing 态 viewState。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/presentation/states/block_view_state.dart';
import 'package:tafcm/presentation/states/coordinator_state.dart';

void main() {
  group('P0 真机问题 1+5: focusOn viewState 缺失', () {
    test('focusOn 对 viewState 不存在的 id 仍创建 editing 态 viewState', () {
      const state = CoordinatorState.empty();
      const newId = BlockId('new-block');

      final next = state.focusOn(newId);

      expect(next.focusedId, equals(newId));
      final vs = next.viewStateOf(newId);
      expect(vs, isNotNull, reason: 'focusOn 必须为缺失的 id 创建 viewState');
      expect(vs!.isFocused, isTrue);
      expect(vs.mode, equals(RenderMode.editing));
    });

    test('focusOn 从空状态聚焦后，新块可被 viewStateOf 查询到 editing 态', () {
      const state = CoordinatorState.empty();
      const id = BlockId('a');

      final next = state.focusOn(id);

      expect(next.viewStateOf(id)?.mode, equals(RenderMode.editing));
      expect(next.viewStateOf(id)?.isFocused, isTrue);
    });

    test('focusOn 切换焦点时，旧块切回 rendered，新块（无 viewState）创建 editing', () {
      const oldId = BlockId('old');
      const newId = BlockId('new');
      final state = CoordinatorState(
        viewStates: Map.unmodifiable({
          oldId: const BlockViewState(
            id: oldId,
            isFocused: true,
            mode: RenderMode.editing,
          ),
        }),
        focusedId: oldId,
      );

      final next = state.focusOn(newId);

      // 旧块切回 rendered
      expect(next.viewStateOf(oldId)?.mode, equals(RenderMode.rendered));
      expect(next.viewStateOf(oldId)?.isFocused, isFalse);
      // 新块创建 editing 态（P0 修复核心）
      expect(next.viewStateOf(newId)?.mode, equals(RenderMode.editing));
      expect(next.viewStateOf(newId)?.isFocused, isTrue);
      expect(next.focusedId, equals(newId));
    });

    test('focusOn 幂等：对已聚焦的 id 再次调用不产生变化', () {
      const id = BlockId('a');
      final state = CoordinatorState(
        viewStates: Map.unmodifiable({
          id: const BlockViewState(
            id: id,
            isFocused: true,
            mode: RenderMode.editing,
          ),
        }),
        focusedId: id,
      );

      final next = state.focusOn(id);

      expect(identical(next, state), isTrue,
          reason: '已聚焦的 id 再次 focusOn 应返回同一对象');
    });

    test('clearFocusOf 对 focusOn 创建的新块正常工作', () {
      const state = CoordinatorState.empty();
      const id = BlockId('a');

      final focused = state.focusOn(id);
      expect(focused.viewStateOf(id)?.mode, equals(RenderMode.editing));

      final cleared = focused.clearFocusOf(id);
      expect(cleared.viewStateOf(id)?.mode, equals(RenderMode.rendered));
      expect(cleared.viewStateOf(id)?.isFocused, isFalse);
      expect(cleared.focusedId, isNull);
    });
  });
}