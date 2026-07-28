/// applyBlockPrefix：块类型转换的 source 前缀映射（纯函数，Phase 3.5.3 / T1-4）。
///
/// 从 [BlockToolbar] 抽出（与 `editor/block_reorder.dart` 同模式：
/// 纯函数、零 Widget 依赖、可直接单测）。
/// 由 `BlockOperations.updateSource` 内部的 tryTransform 依据新 source
/// 前缀自动转化为目标 BlockType。
library;

import '../../../core/editing/block_types.dart';

/// 每行既有块级标记（`#` 标题 / `>` 引用 / `-`/`*`/`+` 列表）匹配。
final RegExp _blockPrefixPattern = RegExp(r'^(#+\s+|>\s+|[-*+]\s+)');

/// 剥离每行既有块级标记，再按 [target] 类型加前缀。
///
/// - [BlockType.paragraph]：去除所有行的前缀（无新前缀）
/// - [BlockType.heading]：首行加 `# `，其余行仅去前缀
/// - [BlockType.blockquote]：每行剥旧前缀后统一加 `> `
/// - 其他类型：等价于 paragraph（仅去前缀）
String applyBlockPrefix(String source, BlockType target) {
  final prefix = switch (target) {
    BlockType.heading => '# ',
    BlockType.blockquote => '> ',
    _ => null, // paragraph：仅去前缀
  };
  final lines = source.split('\n');
  // 逐行剥离既有块级前缀（修复多行 blockquote 仅清首行的缺陷，commit 4589bd7）
  final stripped =
      lines.map((line) => line.replaceFirst(_blockPrefixPattern, '')).toList();
  if (prefix == '> ') {
    // Blockquote：每行加前缀
    return stripped.map((line) => '> $line').join('\n');
  } else if (prefix != null) {
    // Heading：仅首行加前缀
    stripped[0] = '$prefix${stripped[0]}';
  }
  return stripped.join('\n');
}
