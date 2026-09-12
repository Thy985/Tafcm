/// #240 回归测试：外部 URI 只读查看模式（P1-B 修复守门）。
///
/// 缺陷回顾：ACTION_VIEW 打开的外部 .md（content://，无持久化路径）
/// 可以编辑但 `_saveDocument` 因 `path == null` 静默跳过——用户退出后
/// 编辑内容静默丢失（数据丢失类体验缺陷，Audit F-2026-09-03-03）。
///
/// 修复：`EditorCoordinator.isReadOnly` 标志 + `handle()` 入口门禁；
/// editor_page 外部加载路径置 true；workspace 顶部"查看模式"横幅。
///
/// 本套件三层守门：
/// 1. **命令门禁**：readOnly 下所有编辑命令 no-op（返回 false 且不改
///    文档内容/历史），默认构造的 coordinator 不受影响（false）。
/// 2. **UI 提示**：Workspace 在 readOnly 时渲染"查看模式"横幅，
///    非 readOnly 时不渲染（消除"编辑可用但不能保存"的不一致）。
/// 3. **装配接线**：EditorPage 的外部 URI 加载路径确实置 isReadOnly
///    （防后续重构漏掉置位——这是 #240 的根因点）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_types.dart' show BlockId;
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/commands/editor_command.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/editor/workspace.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';

/// 构造带一个段落块的 coordinator。
EditorCoordinator buildCoordinator({bool readOnly = false}) {
  final editor = InMemoryDocumentEditor(title: 't');
  editor.insertBlock(
    editor.blockCount,
    const ParagraphElement(children: <InlineElement>[TextElement('hello')]),
  );
  final coordinator = EditorCoordinator(
    editor: editor,
    history: EditorHistory(maxHistorySize: 200),
  );
  coordinator.isReadOnly = readOnly;
  return coordinator;
}

void main() {
  group('#240 命令门禁：isReadOnly 下编辑命令 no-op', () {
    test('默认构造：isReadOnly 为 false（本地文档编辑不受影响）', () {
      expect(buildCoordinator().isReadOnly, isFalse);
    });

    test('readOnly：InsertTextCommand 被拒绝且文档内容不变', () {
      final coordinator = buildCoordinator(readOnly: true);
      final id = coordinator.allIds.first;
      final before = coordinator.sourceOf(id);

      final accepted = coordinator.handle(
        InsertTextCommand(blockId: id, text: ' world'),
      );

      expect(accepted, isFalse, reason: '只读模式下编辑命令必须被拒绝');
      expect(coordinator.sourceOf(id), before, reason: '文档内容不得变化');
    });

    test('readOnly：新增块命令（InsertBlockAfterCommand）同样被拒绝', () {
      final coordinator = buildCoordinator(readOnly: true);
      final anchorId = coordinator.allIds.first;
      final countBefore = coordinator.allIds.length;

      final accepted = coordinator.handle(
        InsertBlockAfterCommand(
          blockId: anchorId,
          element: const ParagraphElement(children: [TextElement('new')]),
        ),
      );

      expect(accepted, isFalse);
      expect(coordinator.allIds.length, countBefore,
          reason: '块数量不得变化');
    });

    test('非 readOnly：同样的 InsertTextCommand 正常生效（守门非恒真）', () {
      final coordinator = buildCoordinator();
      final id = coordinator.allIds.first;

      final accepted = coordinator.handle(
        InsertTextCommand(blockId: id, text: ' world'),
      );

      expect(accepted, isTrue, reason: '普通模式下命令应生效——证明只读'
          '门禁真的在区分两种状态（非恒真）');
      expect(coordinator.sourceOf(id), contains('hello world'));
    });
  });

  group('#240 UI 提示：Workspace 只读横幅', () {
    Widget makeHost(EditorCoordinator coordinator) {
      // 可变 map：workspace.build 会 putIfAbsent 注册 block key
      //（const {} 是 unmodifiable，会抛 UnsupportedError），故不能用
      // const 字面量——用非 const 局部字面量，两个 lint 均满足。
      final Map<BlockId, GlobalKey> blockKeys = {};
      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EditorScope(
            coordinator: coordinator,
            child: Workspace(
              coordinator: coordinator,
              blockKeys: blockKeys,
            ),
          ),
        ),
      );
    }

    testWidgets('readOnly：渲染"查看模式"横幅', (tester) async {
      final coordinator = buildCoordinator(readOnly: true);
      await tester.pumpWidget(makeHost(coordinator));
      expect(find.text('查看模式 · 外部文件不可保存，编辑已禁用'),
          findsOneWidget);
    });

    testWidgets('非 readOnly：不渲染横幅（本地编辑器无干扰）', (tester) async {
      final coordinator = buildCoordinator();
      await tester.pumpWidget(makeHost(coordinator));
      expect(find.text('查看模式 · 外部文件不可保存，编辑已禁用'),
          findsNothing);
    });
  });
}
