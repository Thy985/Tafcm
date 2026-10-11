/// issue #340-C：加载后自动聚焦首块回归测试。
///
/// 覆盖 [autoFocusFirstBlockIfPending] 的纯函数语义（widget 侧接线由
/// editor_page_missing_file_test.dart 的 EditorPage 冒烟覆盖）：
/// - 挂起 + 无焦点 → 聚焦首块并收口标志
/// - 挂起 + 已有焦点 → 不覆盖用户焦点，仍收口标志
/// - 未挂起 → 不动作、不收口
/// - 空文档（无块）→ 不动作、不收口（待下次重试）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/presentation/editor/editor_autofocus.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
void main() {
  EditorCoordinator buildCoordinator(int paragraphs) {
    final editor = InMemoryDocumentEditor();
    for (var i = 0; i < paragraphs; i++) {
      editor.addParagraph('段 $i');
    }
    return EditorCoordinator(editor: editor, history: EditorHistory());
  }

  group('issue #340-C autoFocusFirstBlockIfPending', () {
    test('挂起 + 无焦点 → 聚焦首块并收口 pending', () {
      final coordinator = buildCoordinator(3);
      final firstId = coordinator.allIds.first;
      bool pending = true;
      bool done = false;

      final result = autoFocusFirstBlockIfPending(
        coordinator: coordinator,
        pending: pending,
        setPending: (v) {
          pending = v;
          done = true;
        },
      );

      expect(result, isTrue, reason: '应执行聚焦');
      expect(coordinator.focusedId, equals(firstId),
          reason: '#340-C：加载后应自动聚焦首个可编辑块');
      expect(pending, isFalse, reason: '触发后必须收口，避免重复聚焦');
      expect(done, isTrue);
    });

    test('挂起 + 已有焦点 → 不覆盖用户焦点，仍收口', () {
      final coordinator = buildCoordinator(3);
      final ids = coordinator.allIds;
      coordinator.setFocus(ids.last); // 用户已有焦点（导航返回场景）
      bool pending = true;

      autoFocusFirstBlockIfPending(
        coordinator: coordinator,
        pending: pending,
        setPending: (v) => pending = v,
      );

      expect(coordinator.focusedId, equals(ids.last),
          reason: '不覆盖用户已有焦点');
      expect(pending, isFalse, reason: '无动作时也应收口，避免反复进入');
    });

    test('未挂起 → 不动作、不收口', () {
      final coordinator = buildCoordinator(3);
      bool pending = false;
      bool called = false;

      final result = autoFocusFirstBlockIfPending(
        coordinator: coordinator,
        pending: pending,
        setPending: (v) {
          called = true;
          pending = v;
        },
      );

      expect(result, isFalse);
      expect(called, isFalse, reason: '未挂起时不应触碰 pending');
      expect(coordinator.focusedId, isNull);
    });

    test('空文档（无块）→ 不动作、不收口', () {
      final coordinator = buildCoordinator(0);
      bool pending = true;
      bool called = false;

      final result = autoFocusFirstBlockIfPending(
        coordinator: coordinator,
        pending: pending,
        setPending: (v) {
          called = true;
          pending = v;
        },
      );

      expect(result, isFalse);
      expect(called, isFalse,
          reason: '无块时不收口——保留 pending 供加载完成后重试');
      expect(coordinator.focusedId, isNull);
    });
  });
}
