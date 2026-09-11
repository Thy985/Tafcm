/// U8 Layered Debug Snapshot：渲染链各层可导出的机器可读证据
///（TEST-SYSTEM-UPGRADE-PLAN §4.3 U8，学 vgpu "内部状态→可断言证据"）。
///
/// 渲染链：`Markdown → Parser → AST → BlockModel(toElement) → Widget`。
/// 出问题时 golden 只说"截图不像"（pixel diff 7.3%，不知为何），本库
/// 让每层都能导出 JSON snapshot（含 contentHash），逐层 diff 直接定位
/// 断点层：AST ✅ / BlockModel ✅ / Render ❌。
///
/// 三层：
/// - [astSnapshot]：Parser 输出（AST 层证据）
/// - [blockModelSnapshot]：BlockSerializer.toElement 输出（Block 模型层）
/// - [renderModelSnapshot]：Widget 树逐块 runtimeType（渲染层，测试内采集）
///
/// 消费方：
/// - `test/evidence/layered_snapshot_test.dart`（逐层对拍）
/// - ADI render_tracer（后续接入：失败报告附 snapshot）
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../parser/markdown_parser.dart';
import '../editing/block_serializer.dart';
import '../editing/block_types.dart';
import '../../data/models/document.dart';

/// 单层 snapshot：签名行 + 内容哈希。
class LayerSnapshot {
  const LayerSnapshot({
    required this.layer,
    required this.blocks,
    required this.contentHash,
  });

  factory LayerSnapshot.fromSignatures(String layer, List<String> signatures) {
    final normalized =
        JsonEncoder.withIndent('', (Object? o) => o).convert(signatures);
    return LayerSnapshot(
      layer: layer,
      blocks: signatures,
      contentHash: sha256.convert(utf8.encode(normalized)).toString(),
    );
  }

  final String layer;

  /// 逐块签名（blockTypes.dart 顺序）。
  final List<String> blocks;

  /// 签名数组的 SHA-256（归一化后），层间对拍的主键。
  final String contentHash;

  Map<String, dynamic> toJson() => {
        'layer': layer,
        'blocks': blocks,
        'contentHash': contentHash,
      };

  @override
  String toString() =>
      '$layer[${blocks.length} blocks, hash=${contentHash.substring(0, 8)}]';
}

// ---- 签名提取（三层共用同一签名语言，保证可对拍） ----

/// 把单个 [DocumentElement] 转为签名行。
///
/// 签名语法：`type[:detail]`，detail 只含**语义载荷**（level/language/
/// ordered/行列数等），不含 UI 属性。三层输出同一种签名才能逐层 diff。
String elementSignature(DocumentElement e) {
  switch (e) {
    case HeadingElement(:final level):
      return 'heading:$level';
    case CodeElement(:final code, :final language):
      return 'code:${language ?? ''}:${_hash(code)}';
    case MermaidElement(:final code):
      return 'mermaid:${_hash(code)}';
    case FormulaElement(:final latex, :final displayMode):
      return 'formula:${displayMode ? 'block' : 'inline'}:${_hash(latex)}';
    case BlockquoteElement():
      return 'quote';
    case HorizontalRuleElement():
      return 'hr';
    case ListElement(:final ordered, :final indent, :final nested):
      return 'list:${ordered ? 'ol' : 'ul'}:$indent:n${nested.length}';
    case TaskListItemElement(:final checked):
      return 'task:$checked';
    case TableElement(:final headers, :final rows):
      return 'table:${headers.length}x${rows.length}';
    case ParagraphElement(:final children):
      final bolds = children.whereType<BoldElement>().length;
      final italics = children.whereType<ItalicElement>().length;
      final codes = children.whereType<InlineCodeElement>().length;
      final links = children.whereType<LinkElement>().length;
      final images = children.whereType<ImageElement>().length;
      final textLen = _inlineTextLength(children);
      return 'para:b$bolds/i$italics/c$codes/l$links/g$images/t$textLen';
    case EmptyLineElement():
      return 'empty';
  }
}

/// 行内载荷文本总长（含嵌套 Bold/Italic 内容——样式标记丢弃时内容仍在）。
int _inlineTextLength(Iterable<InlineElement> children) {
  var len = 0;
  for (final c in children) {
    if (c is TextElement) len += c.text.length;
    if (c is BoldElement) len += _inlineTextLength(c.children);
    if (c is ItalicElement) len += _inlineTextLength(c.children);
    if (c is StrikethroughElement) len += _inlineTextLength(c.children);
  }
  return len;
}

String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

// ---- 三层导出入口 ----

/// Layer 1：Parser 输出（AST 层）。
///
/// 过滤 [EmptyLineElement]（块分隔符，无渲染语义，Block 层不含它）。
LayerSnapshot astSnapshot(String markdown) {
  final blocks = MarkdownParser.parse(markdown);
  return LayerSnapshot.fromSignatures(
    'ast',
    blocks
        .where((e) => e is! EmptyLineElement)
        .map(elementSignature)
        .toList(),
  );
}

/// Layer 2：Block 模型层（source+type → toElement）。
///
/// 输入是 BlockEditor 持有的 (source, BlockType) 序列——即编辑器保存/
/// 编辑操作实际使用的形态（DocumentEditor 语义，非原始文件字节）。
LayerSnapshot blockModelSnapshot(List<(String, BlockType)> blocks) {
  return LayerSnapshot.fromSignatures(
    'block-model',
    blocks.map((b) => elementSignature(toElement(b.$1, b.$2))).toList(),
  );
}

/// Layer 2：编辑器持有形态（生产加载路径的真实模型）。
///
/// 生产加载（editor_page.dart `_loadFromFile`）是 parse → 过滤
/// EmptyLineElement → 逐块 `insertBlock(element)`，**不经** fromElement/
/// toElement round-trip——所以编辑器持有的就是过滤后的 AST 元素。
/// 本层签名应与 [astSnapshot] 恒等（不等说明加载路径有过滤/变换）。
///
/// fromElement/toElement round-trip 是**编辑操作路径**（split/merge 序列化），
/// 它的保真度由测试单独守门（layered_snapshot_test.dart A4 已登记
/// 嵌套列表 round-trip 丢 nested 的缺口）。
LayerSnapshot editorModelSnapshot(List<DocumentElement> elements) {
  return LayerSnapshot.fromSignatures(
    'editor-model',
    elements
        .where((e) => e is! EmptyLineElement)
        .map(elementSignature)
        .toList(),
  );
}

/// Layer 3：渲染层签名（测试内采集 widget 树 runtimeType 序列）。
///
/// 输入是逐块的 widget runtimeType（测试用 `tester.widgetList` /
/// `find.byType` 采集）；本库只负责归一化为签名 + hash，使渲染层与
/// 上两层可同语言对拍。块类型名来自 BlockRenderer 的分发契约。
LayerSnapshot renderModelSnapshot(List<String> blockWidgetTypes) {
  return LayerSnapshot.fromSignatures('render-model', blockWidgetTypes);
}

/// 三层对拍：返回首个不一致的层（全部一致返回 null）。
///
/// 判定顺序 ast → editor-model → render：AST 就错了不必看下层。
String? firstMismatch(
  LayerSnapshot ast,
  LayerSnapshot editorModel,
  LayerSnapshot render,
) {
  if (ast.contentHash != editorModel.contentHash) {
    return 'ast vs editor-model';
  }
  if (editorModel.contentHash != render.contentHash) {
    return 'editor-model vs render-model';
  }
  return null;
}
