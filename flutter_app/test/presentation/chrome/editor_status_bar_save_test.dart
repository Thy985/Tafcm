/// issue #340-B：底栏保存状态指示回归测试。
///
/// 覆盖 [EditorStatusBar] 注入 [AutosaveService] 后显示真实保存状态：
/// - 初始 idle + clean → 「已保存」
/// - dirty + idle → 「未保存」
/// - dirty + saving → 「保存中…」
/// - saved → 「已保存」
/// - 未注入 autosave → 不渲染保存项（保持 golden / 测试场景渲染不变）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/presentation/chrome/editor_status_bar.dart';
import 'package:tafcm/presentation/editor/autosave_service.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';

import '../editor/autosave_test_helpers.dart';

void main() {
  /// 干净编辑器的 coordinator（dirtyNotifier 初始 false）。
  EditorCoordinator cleanCoordinator() =>
      EditorCoordinator(
        editor: InMemoryDocumentEditor(),
        history: EditorHistory(),
      );

  /// 已编辑（dirty）的 coordinator（dirtyNotifier 初始 true）。
  EditorCoordinator dirtyCoordinator() => EditorCoordinator(
        editor: InMemoryDocumentEditor()..addParagraph('正文'),
        history: EditorHistory(),
      );

  /// 带 gate 的 AutosaveService（save 中途暂停，可观测 saving 中间态）。
  (AutosaveService, FakeDirtySource, FakeTimerFactory, Completer<void>)
      buildAutosave() {
    final source = FakeDirtySource()..content = 'x';
    final timers = FakeTimerFactory();
    final gate = Completer<void>();
    final autosave = AutosaveService(
      source: source,
      save: makeSave(src: source, writes: [], gates: [gate]),
      debounce: kDebounce,
      timerFactory: timers.call,
    );
    autosave.start();
    return (autosave, source, timers, gate);
  }

  Widget statusBarWidget(EditorCoordinator coordinator, AutosaveService? a) =>
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          bottomNavigationBar: EditorStatusBar(
            coordinator: coordinator,
            autosave: a,
          ),
          body: const SizedBox.shrink(),
        ),
      );

  group('issue #340-B 保存状态指示', () {
    testWidgets('idle + clean → 「已保存」', (tester) async {
      final (autosave, _, _, _) = buildAutosave();
      addTearDown(autosave.stop);
      await tester.pumpWidget(statusBarWidget(cleanCoordinator(), autosave));
      await tester.pumpAndSettle();
      expect(find.text('已保存'), findsOneWidget);
    });

    testWidgets('idle + dirty → 「未保存」', (tester) async {
      final (autosave, _, _, _) = buildAutosave();
      addTearDown(autosave.stop);
      await tester.pumpWidget(statusBarWidget(dirtyCoordinator(), autosave));
      await tester.pumpAndSettle();
      expect(find.text('未保存'), findsOneWidget);
    });

    testWidgets('saving → saved，状态文字随之翻转', (tester) async {
      final (autosave, source, timers, gate) = buildAutosave();
      addTearDown(autosave.stop);
      await tester.pumpWidget(statusBarWidget(cleanCoordinator(), autosave));
      await tester.pumpAndSettle();

      // 触发 dirty → debounce 定时器创建（fake timer，需手动 fire）。
      source.setDirty(true);
      await tester.pumpAndSettle();
      expect(timers.timers, isNotEmpty, reason: 'debounce 定时器应已创建');

      // fire debounce → AutosaveService 进入 saving，调用 save()（gate 暂停）。
      timers.fireLast();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('保存中…'), findsOneWidget,
          reason: 'save 执行中应显示「保存中…」');

      // 放行 gate → save 完成 → AutosaveService 进入 saved。
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('已保存'), findsOneWidget,
          reason: 'save 完成后应显示「已保存」');
      expect(source.isDirty, isFalse);
    });

    testWidgets('未注入 autosave → 不渲染保存项（golden 兼容）',
        (tester) async {
      await tester.pumpWidget(statusBarWidget(cleanCoordinator(), null));
      await tester.pumpAndSettle();
      expect(find.text('已保存'), findsNothing);
      expect(find.text('未保存'), findsNothing);
      expect(find.text('保存中…'), findsNothing);
      expect(find.text('保存失败'), findsNothing);
    });
  });
}
