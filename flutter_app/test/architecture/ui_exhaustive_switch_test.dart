/// TC-ARCH-UI-8: Phase 3.0 exhaustive switch 守门测试。
///
/// 落地 Phase 3.0 Task Contract §3.3（BlockRenderer 抽象）+ §6（Exit Gate）+
/// ADR-0009 Hard Rule 3（BlockRenderer 抽象）+ ADR-0022 Renderer Failure Policy。
///
/// 守门内容：
/// - `BlockRenderer` 必须使用 `switch (element)` exhaustive 语法
/// - `BlockRenderer` 不允许 `_ =>` fallback 分支
/// - `BlockRenderer` 必须显式支持 6 种 BlockType
///   （Phase 3.0: paragraph / heading / code
///    Phase 3.2 PR #2: quote / table
///    Phase 3.2 PR #3: mermaid）
/// - 未实现的 3 种类型必须经 `FallbackBlockRenderer` 降级渲染
///   （listItem / taskListItem / horizontalRule）
///   MathBlock 留 Phase 3.5+（依赖 FormulaSvgService 集成）
///
/// ADR-0022 变更（2026-08-06）：
/// 原 Phase 3.2 PR #3 要求未实现类型抛 `UnimplementedError`，但生产用户
/// 触发 `TaskListItemElement` 时崩溃（snapshot.json 实证）。ADR-0022 改为
/// 经 `FallbackBlockRenderer` 降级渲染（不 crash + 不丢数据 + 可编辑）。
/// 未实现类型检测责任转移到 observability `UnsupportedBlockFallback` 事件。
///
/// P0-1 变更（2026-08-29）：list / task / hr 已有专用渲染器，fallback 已删除，
/// switch 全量 exhaustive（10 种 DocumentElement 子类型全覆盖）。
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ============ TC-ARCH-UI-8 exhaustive switch 守门 ============

  group('TC-ARCH-UI-8 exhaustive switch 守门：BlockRenderer 不允许 _ => fallback', () {
    test('block_renderer.dart 包含 switch (element) 语法', () {
      final file = File('lib/presentation/blocks/block_renderer.dart');
      expect(file.existsSync(), isTrue,
          reason: 'block_renderer.dart 必须存在');
      final content = file.readAsStringSync();
      expect(
        content.contains('switch (element)'),
        isTrue,
        reason: 'Phase 3.0 Task Contract §3.3：BlockRenderer 必须使用 '
            'switch (element) exhaustive 语法。',
      );
    });

    test('block_renderer.dart 不含 _ => fallback 分支', () {
      final file = File('lib/presentation/blocks/block_renderer.dart');
      final lines = file.readAsLinesSync();
      final hits = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        // 匹配 _ => 或 _ =>（允许空格）的 fallback 分支
        if (RegExp(r'^_\s*=>').hasMatch(trimmed) ||
            RegExp(r'\|\|\s*_\s*=>').hasMatch(trimmed)) {
          hits.add('${i + 1}: ${line.trim()}');
        }
      }
      expect(
        hits,
        isEmpty,
        reason: 'Phase 3.0 Task Contract §3.3：BlockRenderer 必须使用 exhaustive '
            'switch，不允许 _ => fallback 到 GenericBlock。\n'
            '命中：\n${hits.join('\n')}',
      );
    });

    test('block_renderer.dart 显式支持 6 种 BlockType（Phase 3.0 + PR #2 + PR #3）', () {
      final file = File('lib/presentation/blocks/block_renderer.dart');
      final content = file.readAsStringSync();
      // Phase 3.0：3 种基础 BlockType
      expect(
        content.contains('ParagraphElement'),
        isTrue,
        reason: 'BlockRenderer 必须支持 ParagraphElement',
      );
      expect(
        content.contains('HeadingElement'),
        isTrue,
        reason: 'BlockRenderer 必须支持 HeadingElement',
      );
      expect(
        content.contains('CodeElement'),
        isTrue,
        reason: 'BlockRenderer 必须支持 CodeElement',
      );
      // Phase 3.2 PR #2：2 种新增 BlockType
      expect(
        content.contains('BlockquoteElement'),
        isTrue,
        reason: 'Phase 3.2 PR #2：BlockRenderer 必须支持 BlockquoteElement',
      );
      expect(
        content.contains('TableElement'),
        isTrue,
        reason: 'Phase 3.2 PR #2：BlockRenderer 必须支持 TableElement',
      );
      // Phase 3.2 PR #3：1 种新增 BlockType（Mermaid）
      expect(
        content.contains('MermaidElement'),
        isTrue,
        reason: 'Phase 3.2 PR #3：BlockRenderer 必须支持 MermaidElement',
      );
      // P0-1（2026-08-29）：3 种类型已有专用渲染器，fallback 已删除
      // 不允许 throw UnimplementedError（用户路径不能 crash）
      expect(
        content.contains('throw UnimplementedError'),
        isFalse,
        reason: 'ADR-0022 §2.1：block_renderer.dart 不应含 throw UnimplementedError '
            '语句。所有 DocumentElement 子类型均有专用渲染器。',
      );
      expect(
        content.contains('ListElement le => ListBlock'),
        isTrue,
        reason: 'P0-1：ListElement → ListBlock 专用渲染器（WYSIWYG）',
      );
      expect(
        content.contains('TaskListItemElement tle => TaskListBlock'),
        isTrue,
        reason: 'P0-1：TaskListItemElement → TaskListBlock 专用渲染器（WYSIWYG）',
      );
      expect(
        content.contains('HorizontalRuleElement hre => HorizontalRuleBlock'),
        isTrue,
        reason: 'P0-1：HorizontalRuleElement → HorizontalRuleBlock 专用渲染器（WYSIWYG）',
      );
      expect(
        content.contains('FallbackBlockRenderer'),
        isFalse,
        reason: 'P0-1：FallbackBlockRenderer 已删除（switch 全量 exhaustive）',
      );
    });
  });
}
