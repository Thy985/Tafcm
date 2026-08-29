/// BlockRenderer 全类型覆盖守门测试（P0-1 UI/UX 修复后）。
///
/// P0-1（2026-08-29）：列表 / 任务 / 分隔线已有专用渲染器，
/// `FallbackBlockRenderer` 已删除。原 ADR-0022 fallback 守门（TC-FALLBACK-1/2）
/// 随之退役，本文件保留并更新为：
/// - **TC-BLOCK-RENDERER-1**：block_renderer.dart 中 10 种 DocumentElement 子类型
///   全部有专用渲染器，不抛 `UnimplementedError`，不引用已删除的 FallbackBlockRenderer
/// - **TC-SERIALIZE-1**：`fromElement` 对 3 种列表 / 任务 / 分隔线元素输出正确
///   markdown source（可读、不丢数据）
/// - **TC-SERIALIZE-2**：`EmptyLineElement` 仍抛 `ArgumentError`
///   （BlockEditor 范围外，不应到达 Renderer）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_serializer.dart';
import 'package:formula_fix/data/models/document.dart';

void main() {
  // ============ TC-BLOCK-RENDERER-1 全类型专用渲染器 ============

  group('TC-BLOCK-RENDERER-1 block_renderer.dart 全类型专用渲染器', () {
    final file = File('lib/presentation/blocks/block_renderer.dart');

    test('block_renderer.dart 不含 throw UnimplementedError', () {
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(
        content.contains('throw UnimplementedError'),
        isFalse,
        reason: 'ADR-0022 §2.1 延续：Renderer MUST NOT crash on unknown BlockElement。'
            'block_renderer.dart 不应再含 throw UnimplementedError 语句'
            '（注释中提及该词不算）',
      );
    });

    test('block_renderer.dart import 三个新渲染器（list / task / hr）', () {
      final content = file.readAsStringSync();

      expect(
        content.contains("import 'list/list_block.dart'"),
        isTrue,
        reason: 'P0-1：ListElement 必须有专用 ListBlock 渲染器',
      );
      expect(
        content.contains("import 'task/task_list_block.dart'"),
        isTrue,
        reason: 'P0-1：TaskListItemElement 必须有专用 TaskListBlock 渲染器',
      );
      expect(
        content.contains("import 'hr/hr_block.dart'"),
        isTrue,
        reason: 'P0-1：HorizontalRuleElement 必须有专用 HorizontalRuleBlock 渲染器',
      );
    });

    test('block_renderer.dart 3 种类型有专用 case 分支', () {
      final content = file.readAsStringSync();

      expect(
        content.contains('ListElement le => ListBlock'),
        isTrue,
        reason: 'P0-1：ListElement → ListBlock 专用 case',
      );
      expect(
        content.contains('TaskListItemElement tle => TaskListBlock'),
        isTrue,
        reason: 'P0-1：TaskListItemElement → TaskListBlock 专用 case',
      );
      expect(
        content.contains('HorizontalRuleElement hre => HorizontalRuleBlock'),
        isTrue,
        reason: 'P0-1：HorizontalRuleElement → HorizontalRuleBlock 专用 case',
      );
    });

    test('block_renderer.dart 不再引用已删除的 FallbackBlockRenderer', () {
      final content = file.readAsStringSync();

      expect(
        content.contains('FallbackBlockRenderer'),
        isFalse,
        reason: 'P0-1：FallbackBlockRenderer 已删除（switch 全量 exhaustive），'
            '不应再被引用',
      );
      expect(
        content.contains("import 'fallback_block_renderer.dart'"),
        isFalse,
        reason: 'P0-1：不再 import 已删除的 fallback_block_renderer.dart',
      );
    });

    test('block_renderer.dart 仍对 EmptyLineElement 抛 ArgumentError', () {
      final content = file.readAsStringSync();

      expect(
        content.contains('EmptyLineElement') && content.contains('ArgumentError'),
        isTrue,
        reason: 'ADR-0022 §2.3 延续：EmptyLineElement 是 BlockEditor 范围外的逻辑错误，'
            '保持 ArgumentError（不应到达 Renderer）',
      );
    });
  });

  // ============ TC-SERIALIZE-1 fromElement 序列化验证 ============

  group('TC-SERIALIZE-1 fromElement 对 3 种元素输出正确 markdown source', () {
    test('TaskListItemElement(checked: false) → "- [ ] task"', () {
      const element = TaskListItemElement(
        children: [TextElement('买牛奶')],
        checked: false,
      );
      expect(
        fromElement(element),
        equals('- [ ] 买牛奶'),
        reason: '序列化："- [ ] 买牛奶"（可读、不丢数据）',
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
        reason: '序列化："- [x] 完成"',
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
        reason: 'indent=2 → 4 空格前缀',
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
        reason: '无序列表 → "- 苹果"',
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
        reason: '有序列表 → "1. 第一"',
      );
    });

    test('HorizontalRuleElement() → "---"', () {
      const element = HorizontalRuleElement();
      expect(
        fromElement(element),
        equals('---'),
        reason: '水平分割线 → "---"',
      );
    });
  });

  // ============ TC-SERIALIZE-2 EmptyLineElement 仍抛 ArgumentError ============

  group('TC-SERIALIZE-2 EmptyLineElement 仍抛 ArgumentError（不应到达 Renderer）', () {
    test('fromElement(EmptyLineElement) 抛 ArgumentError', () {
      expect(
        () => fromElement(const EmptyLineElement()),
        throwsArgumentError,
        reason: 'EmptyLineElement 是 block separator，不在 BlockEditor 范围。'
            'fromElement 抛 ArgumentError。',
      );
    });
  });
}
