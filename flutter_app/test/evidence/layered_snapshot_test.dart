/// U8 逐层对拍 evidence 测试（TEST-SYSTEM-UPGRADE-PLAN §4.3）。
///
/// 渲染链分层（与 render_debug_snapshot.dart 一致）：
/// - Layer 1 AST：`MarkdownParser.parse` 输出（[astSnapshot]）
/// - Layer 2 编辑器模型：生产加载 = 过滤 EmptyLineElement 后逐块
///   insertBlock，即过滤后 AST 本身（[editorModelSnapshot]）
/// - Layer 3 渲染层：widget 树中 [BlockRenderer] 实际收到的 element
///   （[renderModelSnapshot]，widget 测试内采集）
///
/// 三层共用同一签名语言（[elementSignature]），contentHash 逐层相等 =
/// 渲染链无信息丢失。出 golden diff 时先跑本测试定位断点层。
///
/// 另设 A4 守门 **编辑操作路径**（fromElement/toElement round-trip，
/// split/merge 序列化所用）：该路径存在已知缺口——嵌套列表项丢失
/// nested（block_serializer 的 ListElement 序列化不还原嵌套结构）。
/// A4 按当前真实行为断言并登记 TODO，修复后同步翻转断言。
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_serializer.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/observability/render_debug_snapshot.dart';
import 'package:tafcm/core/parser/markdown_parser.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/blocks/block_renderer.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';

import '../golden/golden_helpers.dart';

/// 覆盖全部 9 种 BlockType 的样本（保守行内集：粗/斜/行内码/链接）。
const _sampleMarkdown = '''
# 一级标题

普通段落，含 **加粗**、*斜体*、`行内代码` 和 [链接](https://example.com)。

- 无序项 A
- 无序项 B
  - 嵌套项 B1

1. 有序项一
2. 有序项二

- [x] 已完成任务
- [ ] 未完成任务

> 引用：引用一段话

```dart
void main() {}
```

| 列 A | 列 B |
| --- | --- |
| 1 | 2 |

---

```mermaid
graph TD; A-->B;
```
''';

/// 生产加载路径的块列表：过滤 EmptyLineElement（与 editor_page.dart
/// `_loadFromFile` 一致），**不过 round-trip**。
List<DocumentElement> _productionBlocks(String markdown) =>
    MarkdownParser.parse(markdown).where((e) => e is! EmptyLineElement).toList();

void main() {
  group('U8-A 纯 Dart 三层对拍（AST ↔ 编辑器模型 ↔ round-trip）', () {
    test('A1: 生产加载路径 AST 与编辑器模型 contentHash 恒等', () {
      final ast = astSnapshot(_sampleMarkdown);
      final editor = editorModelSnapshot(_productionBlocks(_sampleMarkdown));

      // ignore: avoid_print
      print('[U8] ast:       $ast');
      // ignore: avoid_print
      print('[U8] editor:    $editor');

      expect(
        editor.contentHash,
        ast.contentHash,
        reason: '生产加载对 AST 无变换（只滤块分隔符），签名必须逐块一致；'
            '不一致说明加载路径引入了过滤/变换（对照 blocks 找首个分歧块）',
      );
      expect(ast.blocks.length, editor.blocks.length);
    });

    test('A2: 行内载荷签名完整（b/i/c/l 计数与文本长度）', () {
      final ast = astSnapshot(_sampleMarkdown);
      final para = ast.blocks.firstWhere((s) => s.startsWith('para:'));
      expect(para, contains('b1'), reason: '加粗计数');
      expect(para, contains('i1'), reason: '斜体计数');
      expect(para, contains('c1'), reason: '行内码计数');
      expect(para, contains('l1'), reason: '链接计数');
      expect(para, isNot(contains('t0')), reason: '文本载荷不得为空');
    });

    test('A3: firstMismatch 对一致链返回 null，对注入扰动报告断点', () {
      final ast = astSnapshot(_sampleMarkdown);
      final editor = editorModelSnapshot(_productionBlocks(_sampleMarkdown));
      expect(firstMismatch(ast, editor, editor), isNull);

      // 注入扰动：渲染层签名与编辑器层不一致 → 报告断点在 render
      final corrupted = LayerSnapshot.fromSignatures(
        'render-model',
        [...editor.blocks.take(editor.blocks.length - 1), 'para:b0/i0/c0/l0/g0/t0'],
      );
      expect(firstMismatch(ast, editor, corrupted), 'editor-model vs render-model');
    });

    test('A4: round-trip（编辑操作路径）对非嵌套块恒等；嵌套列表为已登记缺口', () {
      final blocks = _productionBlocks(_sampleMarkdown);
      final nonNestedLosses = <int>[];
      for (var i = 0; i < blocks.length; i++) {
        final e = blocks[i];
        final before = elementSignature(e);
        final src = fromElement(e);
        final back = toElement(src, BlockType.fromElement(e));
        if (elementSignature(back) != before) nonNestedLosses.add(i);
      }
      // 唯一已知失真：嵌套列表（index 3，list:ul:0:n1 → n0）。
      // TODO(§4.2/编辑器侧): fromElement 对 ListElement.nested 的序列化
      // 不还原嵌套结构（flatten 丢失）。修复后翻转断言为 isEmpty。
      expect(
        nonNestedLosses.where((i) => blocks[i] is! ListElement),
        isEmpty,
        reason: '非列表块的 round-trip 必须恒等——出现失真即序列化回归',
      );
      expect(
        nonNestedLosses,
        isNotEmpty,
        reason: '嵌套列表 round-trip 失真是已登记缺口：若此断言失败（变为空），'
            '说明 nested 序列化已修复，请把本测试升级为「全量恒等」断言',
      );
    });
  });

  group('U8-B widget 树渲染层对拍（真实渲染路径）', () {
    testWidgets('B1: BlockRenderer 实际收到的元素签名与编辑器模型一致',
        (tester) async {
      // EditorViewport 用 ReorderableListView.builder（懒构建）：
      // 默认 800×600 surface 只装得下前 9 块，后 4 块（code/table/hr/
      // mermaid）不在 widget 树。拉高 surface 让全样本进视口（U10 同款）。
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final blocks = _productionBlocks(_sampleMarkdown);
      final editor = InMemoryDocumentEditor(title: 'u8-evidence');
      for (var i = 0; i < blocks.length; i++) {
        editor.insertBlock(i, blocks[i]);
      }
      final coordinator = EditorCoordinator(
        editor: editor,
        history: EditorHistory(maxHistorySize: 32),
      );

      await pumpEditorGolden(tester, coordinator);
      await tester.pumpAndSettle();

      // 采集渲染层证据：BlockRenderer 实际收到的 element（签名语言与上
      // 两层统一才能对拍）。
      final renderers = tester.widgetList<BlockRenderer>(
        find.byType(BlockRenderer),
      ).toList();
      // ignore: avoid_print
      print('[U8] render 层采集到 ${renderers.length} 个 BlockRenderer');

      final render = renderModelSnapshot(
        renderers.map((r) => elementSignature(r.element)).toList(),
      );
      final editorModel = editorModelSnapshot(blocks);
      final astLayer = astSnapshot(_sampleMarkdown);

      // ignore: avoid_print
      print('[U8] render:    $render');
      expect(
        firstMismatch(astLayer, editorModel, render),
        isNull,
        reason: '渲染链三层 contentHash 必须一致；不一致时 firstMismatch '
            '直接指出断点层（golden diff 定位的第一入口）',
      );
    });
  });
}
