/// T2-0 试点 golden（TEST_GAP_PLAN）：单段 Latin 正文排版（light 主题）。
///
/// 目的：验证 golden 基础设施在固定环境下可确定性渲染——这是 T2-0 硬性
/// 前置「试点 1 张」的载体。该测试通过 [golden_helpers] 固定 locale /
/// textScaleFactor / viewport 并显式加载打包字体，基线应在 Windows 本地与
/// Linux CI 上像素一致。
///
/// 防什么：正文排版（serif 15px / blockSpacing 20 / 段间距）回归——token
/// 或字体一动，基线即 diff。
///
/// 注：基线 PNG 由 `flutter test --tags golden --update-goldens` 生成；
/// 按 GOLDEN-CI-001 解封条件，CI 基线须在 Linux 内生成（见 ci.yml golden job
/// bootstrap 命令），本机产物仅本地开发参考。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/editor_shell.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'golden_helpers.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenFonts();
  });

  testWidgets('paragraph light：单段 Latin 正文排版', (tester) async {
    final editor = InMemoryDocumentEditor(title: 'golden-pilot');
    editor.insertBlock(
      editor.blockCount,
      ParagraphElement(children: [
        TextElement(
          'The quick brown fox jumps over the lazy dog. Flutter golden '
          'tests must be deterministic across platforms, so this baseline '
          'locks the paragraph typography (serif body, 15px, block spacing).',
        ),
      ]),
    );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(maxHistorySize: 200),
    );

    await pumpGoldenApp(
      tester,
      EditorScope(
        coordinator: coordinator,
        child: AnimatedBuilder(
          animation: coordinator,
          builder: (context, _) => EditorViewport(
            coordinator: coordinator,
            blockKeys: <BlockId, GlobalKey>{},
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/paragraph_light.png'),
    );
  });
}
