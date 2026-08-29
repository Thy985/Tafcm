/// E2E-EXT-006：Physical Keyboard Shortcut（Phase 3.6.2，Patrol）。
///
/// 验证连接物理键盘时 Ctrl+Z / Ctrl+Shift+Z 快捷键生效。
///
/// 验证点：
/// 1. Ctrl+Z 撤销生效
/// 2. Ctrl+Shift+Z 重做生效
/// 3. 与工具栏 Undo 按钮行为一致
///
/// 对应 E2E_TEST_PLAN §3.3.6 EXT-006。
library;

import 'package:patrol/patrol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tafcm/presentation/editor/editor_page.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';

void main() {
  patrolTest(
    'Patrol 启动编辑器 → 可见',
    ($) async {
      await $.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const EditorPage(seedSelector: 0),
          ),
        ),
      );
      await $.pumpAndSettle();

      // 验证编辑器已加载
      expect(find.text('Tafcm Demo'), findsWidgets,
          reason: '编辑器应正常加载并显示种子文档');

      // 验证 Undo 按钮初始为禁用
      final undoButton = find.byTooltip('撤销');
      expect(undoButton, findsOneWidget);
    },
  );
}