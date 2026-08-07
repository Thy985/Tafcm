/// ADR-0022 Renderer Failure Policy 守门测试。
///
/// 验证：
/// - **TC-FALLBACK-1**：`block_renderer.dart` 中 3 种未实现类型经
///   `FallbackBlockRenderer` 降级渲染，不抛 `UnimplementedError`
/// - **TC-FALLBACK-2**：`FallbackBlockRenderer` 文件存在且结构正确
/// - **TC-FALLBACK-3**：`fromElement` 对 3 种元素输出正确 markdown source
///   （验证用户看到的内容：可读、不丢数据）
/// - **TC-FALLBACK-4**：`EmptyLineElement` 仍抛 `ArgumentError`
///   （BlockEditor 范围外，不应到达 Renderer）
///
/// 落地 [ADR-0022] §5.2 + §6.2。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_serializer.dart';
import 'package:formula_fix/data/models/document.dart';

void main() {
  // ============ TC-FALLBACK-1 block_renderer.dart 不抛 UnimplementedError ============

  group('TC-FALLBACK-1 block_renderer.dart 3 种类型经 FallbackBlockRenderer', () {
    final file = File('lib/presentation/blocks/block_renderer.dart');

    test('block_renderer.dart 不含 throw UnimplementedError', () {
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(
        content.contains('throw UnimplementedError'),
        isFalse,
        reason: 'ADR-0022 §2.1：Renderer MUST NOT crash on unknown BlockElement。'
            'block_renderer.dart 不应再含 throw UnimplementedError 语句'
            '（注释中提及该词不算）',
      );
    });

    test('block_renderer.dart import fallback_block_renderer.dart', () {
      final content = file.readAsStringSync();

      expect(
        content.contains("import 'fallback_block_renderer.dart'"),
        isTrue,
        reason: 'ADR-0022 §2.2：block_renderer.dart 必须 import FallbackBlockRenderer',
      );
    });

    test('block_renderer.dart 3 种类型经 FallbackBlockRenderer 分支', () {
      final content = file.readAsStringSync();

      // 3 种未实现类型必须在同一 case 分支，指向 FallbackBlockRenderer
      expect(
        content.contains('ListElement()') &&
            content.contains('TaskListItemElement()') &&
            content.contains('HorizontalRuleElement()'),
        isTrue,
        reason: 'ADR-0022 §2.2：ListElement / TaskListItemElement / '
            'HorizontalRuleElement 必须有显式 case 分支',
      );
      expect(
        content.contains('FallbackBlockRenderer('),
        isTrue,
        reason: 'ADR-0022 §2.2：未实现类型必须经 FallbackBlockRenderer 降级渲染',
      );
    });

    test('block_renderer.dart 仍对 EmptyLineElement 抛 ArgumentError', () {
      final content = file.readAsStringSync();

      expect(
        content.contains('EmptyLineElement') && content.contains('ArgumentError'),
        isTrue,
        reason: 'ADR-0022 §2.3：EmptyLineElement 是 BlockEditor 范围外的逻辑错误，'
            '保持 ArgumentError（不应到达 Renderer）',
      );
    });
  });

  // ============ TC-FALLBACK-2 FallbackBlockRenderer 文件结构 ============

  group('TC-FALLBACK-2 FallbackBlockRenderer 文件结构', () {
    final file = File('lib/presentation/blocks/fallback_block_renderer.dart');

    test('fallback_block_renderer.dart 存在', () {
      expect(
        file.existsSync(),
        isTrue,
        reason: 'ADR-0022 §5.1：fallback_block_renderer.dart 必须存在',
      );
    });

    test('FallbackBlockRenderer 类存在且为 StatefulWidget', () {
      final content = file.readAsStringSync();

      expect(
        content.contains('class FallbackBlockRenderer extends StatefulWidget'),
        isTrue,
        reason: 'ADR-0022 §2.2：FallbackBlockRenderer 必须是 StatefulWidget'
            '（initState 中调用 captureError 去重）',
      );
    });

    test('FallbackBlockRenderer 调用 fromElement 反向序列化', () {
      final content = file.readAsStringSync();

      expect(
        content.contains('fromElement('),
        isTrue,
        reason: 'ADR-0022 §2.2：FallbackBlockRenderer 必须用 fromElement '
            '反向序列化为 markdown source',
      );
    });

    test('FallbackBlockRenderer 委托给 ParagraphBlock', () {
      final content = file.readAsStringSync();

      expect(
        content.contains('ParagraphBlock('),
        isTrue,
        reason: 'ADR-0022 §2.2：FallbackBlockRenderer 必须委托给 ParagraphBlock '
            '（复用 render + edit 双态逻辑）',
      );
    });

    test('FallbackBlockRenderer 调用 observability.captureError', () {
      final content = file.readAsStringSync();

      expect(
        content.contains("captureError("),
        isTrue,
        reason: 'ADR-0022 §2.4：FallbackBlockRenderer 必须 captureError '
            '记录降级事件（type: UnsupportedBlockFallback）',
      );
      expect(
        content.contains("'UnsupportedBlockFallback'"),
        isTrue,
        reason: 'ADR-0022 §2.4：captureError 的 type 必须为 '
            "'UnsupportedBlockFallback'",
      );
    });

    test('FallbackBlockRenderer 有去重机制（避免污染 lastErrorSnapshot）', () {
      final content = file.readAsStringSync();

      expect(
        content.contains('_reportedTypes'),
        isTrue,
        reason: 'ADR-0022 §2.4：FallbackBlockRenderer 必须有去重机制，'
            '每个元素类型在 App 生命周期内只报告一次',
      );
    });
  });

  // ============ TC-FALLBACK-3 fromElement 序列化验证 ============

  group('TC-FALLBACK-3 fromElement 对 3 种元素输出正确 markdown source', () {
    test('TaskListItemElement(checked: false) → "- [ ] task"', () {
      const element = TaskListItemElement(
        children: [TextElement('买牛奶')],
        checked: false,
      );
      expect(
        fromElement(element),
        equals('- [ ] 买牛奶'),
        reason: 'ADR-0022 §2.2：用户看到 "- [ ] 买牛奶"（可读、可编辑）',
      );
    });

    test('TaskListItemElement(checked: true) → "- [x] done"', () {
      const element = TaskListItemElement(
        children: [TextElement('完成')],
        checked: true,
      );
      expect(
        fromElement(element),
        equals('- [x] 完成'),
        reason: 'ADR-0022 §2.2：用户看到 "- [x] 完成"',
      );
    });

    test('TaskListItemElement(indent: 2) → "  - [ ] nested"', () {
      const element = TaskListItemElement(
        children: [TextElement('嵌套')],
        checked: false,
        indent: 2,
      );
      expect(
        fromElement(element),
        equals('    - [ ] 嵌套'),
        reason: 'ADR-0022 §2.2：indent=2 → 4 空格前缀',
      );
    });

    test('ListElement(ordered: false) → "- item"', () {
      const element = ListElement(
        children: [TextElement('苹果')],
        ordered: false,
      );
      expect(
        fromElement(element),
        equals('- 苹果'),
        reason: 'ADR-0022 §2.2：无序列表 → "- 苹果"',
      );
    });

    test('ListElement(ordered: true) → "1. first"', () {
      const element = ListElement(
        children: [TextElement('第一')],
        ordered: true,
      );
      expect(
        fromElement(element),
        equals('1. 第一'),
        reason: 'ADR-0022 §2.2：有序列表 → "1. 第一"',
      );
    });

    test('HorizontalRuleElement() → "---"', () {
      const element = HorizontalRuleElement();
      expect(
        fromElement(element),
        equals('---'),
        reason: 'ADR-0022 §2.2：水平分割线 → "---"',
      );
    });
  });

  // ============ TC-FALLBACK-4 EmptyLineElement 仍抛 ArgumentError ============

  group('TC-FALLBACK-4 EmptyLineElement 仍抛 ArgumentError（不应到达 Renderer）', () {
    test('fromElement(EmptyLineElement) 抛 ArgumentError', () {
      expect(
        () => fromElement(const EmptyLineElement()),
        throwsArgumentError,
        reason: 'ADR-0022 §2.3：EmptyLineElement 是 block separator，'
            '不在 BlockEditor 范围。fromElement 抛 ArgumentError。',
      );
    });
  });
}
