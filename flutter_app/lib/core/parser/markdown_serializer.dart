/// MarkdownSerializer：AST → Markdown 字符串（Phase 3.5.1 PR A）。
///
/// 落地 ADR-0020 Decision 1（AST 单一真相源）：Markdown 降级为序列化格式。
/// 序列化逻辑委托给 `block_serializer.dart` 的 `fromElement()` + `InlineSerializer`，
/// 本类仅提供干净的 `serialize(List<DocumentElement>)` 公开入口和文档级排版。
///
/// **与 [MarkdownParser] 的关系**：
/// ```
/// String → MarkdownParser.parse() → List<DocumentElement>  (load)
/// List<DocumentElement> → MarkdownSerializer.serialize() → String  (save)
/// ```
library;

import '../../data/models/document.dart';
import '../editing/block_serializer.dart';

/// AST → Markdown 序列化器（薄封装，委托 block_serializer.dart）。
class MarkdownSerializer {
  const MarkdownSerializer._();

  /// 将 [DocumentElement] 列表序列化为 Markdown 字符串。
  ///
  /// 块间以 `\n` 分隔（[EmptyLineElement] 不在此列表中，已在 parser 层过滤）；
  /// 需要段落间空行的场景由调用方在 join 时插入 `\n\n`。
  static String serialize(List<DocumentElement> elements) =>
      elements.map(fromElement).join('\n');
}
