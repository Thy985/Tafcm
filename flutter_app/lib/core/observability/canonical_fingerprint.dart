/// Canonical AST Fingerprint：确定性 Document fingerprint 生成。
///
/// 基于 Canonical JSON 序列化 + SHA-256 哈希，用于检测仅 AST 变化
/// 但 source 不变的场景。
///
/// 落地 ADR-0021 §2.3（Canonical AST Fingerprint 稳定性要求）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/models/document.dart';

/// 将 Document 序列化为确定性 JSON 字符串，保证相同输入始终产生相同输出。
///
/// 规则：
/// 1. Map 的 key 按字母序输出
/// 2. 数组排序：id 数组按字母序，children 按语义顺序保留
/// 3. 排除 key 在 [excludeKeys] 中的字段
/// 4. 不包含空格/换行符（紧凑格式）
String canonicalJsonEncode(
  Object? value, {
  Set<String> excludeKeys = const {
    'createdAt', 'updatedAt', 'sessionId', 'random',
    'isDirty', 'hasFocus', 'timestamp',
  },
}) {
  return _canonicalEncode(value, excludeKeys);
}

/// 递归编码（内部实现）。
String _canonicalEncode(Object? value, Set<String> excludeKeys) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) return value.toString();
  if (value is String) return jsonEncode(value); // 带引号转义

  if (value is List) {
    // 若所有元素都是 String，判断是否应按字母序排序
    // children 列表（含 InlineElement 等非 String 类型）保留顺序
    // 纯 String 列表（如 allIds）按字母序排序
    final allStrings = value.every((e) => e is String);
    final items = value.map((e) => _canonicalEncode(e, excludeKeys)).toList();
    if (allStrings) {
      items.sort();
    }
    return '[${items.join(',')}]';
  }

  if (value is Map) {
    final entries = <String>[];
    // 先排序 key，再过滤 + 编码
    final keys = (value.keys.cast<String>().toList()..sort());
    for (final key in keys) {
      if (excludeKeys.contains(key)) continue;
      final encodedValue = _canonicalEncode(value[key], excludeKeys);
      entries.add('${jsonEncode(key)}:$encodedValue');
    }
    return '{${entries.join(',')}}';
  }

  // 兜底
  return jsonEncode(value);
}

/// 从 [DocumentElement] 树生成 Canonical JSON Map。
///
/// 遍历 block 树，将每个 [DocumentElement] 转换为按字母序 key 的 Map，
/// 确保相同 AST 结构产生相同输出。
Map<String, Object?> elementToJson(DocumentElement element) {
  return switch (element) {
    HeadingElement e => {
      'type': 'heading',
      'level': e.level,
      // PR-3：children 已是 Inline AST。
      'children': e.children.map(inlineToJson).toList(),
    },
    ParagraphElement e => {
      'type': 'paragraph',
      'children': e.children.map(inlineToJson).toList(),
    },
    ListElement e => {
      'type': 'list',
      'ordered': e.ordered,
      'indent': e.indent,
      'children': e.children.map(inlineToJson).toList(),
    },
    CodeElement e => {
      'type': 'code',
      'code': e.code,
      if (e.language != null) 'language': e.language,
    },
    TableElement e => {
      'type': 'table',
      // PR-2：cell 已是 Inline AST，序列化为 inline JSON 数组。
      'headers': e.headers.map((h) => h.map(inlineToJson).toList()).toList(),
      'rows': e.rows
          .map((r) => r.map((c) => c.map(inlineToJson).toList()).toList())
          .toList(),
    },
    BlockquoteElement e => {
      'type': 'blockquote',
      // PR-2：children 已是 Inline AST。
      'children': e.children.map(inlineToJson).toList(),
    },
    MermaidElement e => {
      'type': 'mermaid',
      'code': e.code,
    },
    EmptyLineElement() => {
      'type': 'empty_line',
    },
    TaskListItemElement e => {
      'type': 'task_list_item',
      'checked': e.checked,
      'indent': e.indent,
      'children': e.children.map(inlineToJson).toList(),
    },
    HorizontalRuleElement() => {
      'type': 'horizontal_rule',
    },
  };
}

/// 将 [InlineElement] 转换为 Canonical JSON Map。
Map<String, Object?> inlineToJson(InlineElement element) {
  return switch (element) {
    TextElement e => {
      'type': 'text',
      'text': e.text,
    },
    FormulaElement e => {
      'type': 'formula',
      'latex': e.latex,
      if (e.displayMode) 'displayMode': e.displayMode,
    },
    BoldElement e => {
      'type': 'bold',
      'children': e.children.map(inlineToJson).toList(),
    },
    ItalicElement e => {
      'type': 'italic',
      'children': e.children.map(inlineToJson).toList(),
    },
    StrikethroughElement e => {
      'type': 'strikethrough',
      'children': e.children.map(inlineToJson).toList(),
    },
    InlineCodeElement e => {
      'type': 'inline_code',
      'code': e.code,
    },
    LinkElement e => {
      'type': 'link',
      'text': e.text,
      'url': e.url,
    },
    ImageElement e => {
      'type': 'image',
      'alt': e.alt,
      'url': e.url,
    },
  };
}

/// 从 block 列表生成 Canonical JSON Map。
///
/// [blocks] 按 blockId 字母序排序（保证确定性）。
Map<String, Object?> blocksToJson(List<MapEntry<String, DocumentElement>> blocks) {
  final sorted = blocks.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return {
    'blocks': sorted.map((e) => {
      'id': e.key,
      ...elementToJson(e.value),
    }).toList(),
  };
}

/// 计算 Document fingerprint：SHA-256 of canonical JSON。
///
/// [blocks] 为 `(blockId, DocumentElement)` 对列表。
/// 返回 hex 格式的 SHA-256 哈希（64 字符）。
String canonicalFingerprint(List<MapEntry<String, DocumentElement>> blocks) {
  final json = blocksToJson(blocks);
  final canonical = canonicalJsonEncode(json);
  final bytes = utf8.encode(canonical);
  return sha256.convert(bytes).toString();
}

/// 计算 source 摘要（用于 beforeSnapshot / afterSnapshot）。
///
/// 取所有 block 的 source 拼接后的 SHA-256（前 16 字符）。
String sourceDigest(List<MapEntry<String, String>> sources) {
  final sorted = sources.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final concatenated = sorted.map((e) => '${e.key}:${e.value}').join('|');
  final bytes = utf8.encode(concatenated);
  return sha256.convert(bytes).toString().substring(0, 16);
}