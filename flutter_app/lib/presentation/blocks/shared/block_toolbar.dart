/// BlockToolbar：悬浮在块右上角的操作条。
///
/// 落地 Phase 3.5.3（Block Toolbar：移动 / 删除 / 转换类型）。
/// 全部通过 [EditorCoordinator.handle] 派发 [EditorCommand]，
/// 禁止直接调用 core/editing mutation（TC-ARCH-UI-1）。
///
/// 视觉反馈由 [BlockSelectionChrome] 控制显隐（hover / 选中时显示）。
library;

import 'package:flutter/material.dart';

import '../../../core/editing/block_types.dart';
import '../../commands/commands.dart';
import '../../editor/editor_coordinator.dart';
import '../../themes/editor_tokens.dart';

/// 块操作工具条。
class BlockToolbar extends StatelessWidget {
  final EditorCoordinator coordinator;
  final BlockId blockId;
  final int index;

  const BlockToolbar({
    super.key,
    required this.coordinator,
    required this.blockId,
    required this.index,
  });

  bool get _canMoveUp => index > 0;
  bool get _canMoveDown => index < (coordinator.blockCount - 1);
  bool get _canDelete => coordinator.blockCount > 1;

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    final element = coordinator.getBlock(blockId);
    final type = element == null ? null : BlockType.fromElement(element);
    final canConvert = type == BlockType.paragraph ||
        type == BlockType.heading ||
        type == BlockType.blockquote;

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(EditorTokens.blockRadius),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(EditorTokens.blockRadius),
          border: Border.all(color: tokens.borderDefault),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '上移',
              icon: const Icon(Icons.arrow_upward, size: 16),
              onPressed: _canMoveUp
                  ? () => coordinator.handle(
                        MoveBlockUpCommand(blockId: blockId),
                      )
                  : null,
            ),
            IconButton(
              tooltip: '下移',
              icon: const Icon(Icons.arrow_downward, size: 16),
              onPressed: _canMoveDown
                  ? () => coordinator.handle(
                        MoveBlockDownCommand(blockId: blockId),
                      )
                  : null,
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: _canDelete
                  ? () => coordinator.handle(
                        DeleteBlockCommand(blockId: blockId),
                      )
                  : null,
            ),
            if (canConvert)
              PopupMenuButton<BlockType>(
                tooltip: '转换类型',
                icon: const Icon(Icons.transform, size: 16),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: BlockType.paragraph, child: Text('正文')),
                  PopupMenuItem(value: BlockType.heading, child: Text('标题')),
                  PopupMenuItem(value: BlockType.blockquote, child: Text('引用')),
                ],
                onSelected: _convertTo,
              ),
          ],
        ),
      ),
    );
  }

  void _convertTo(BlockType target) {
    final element = coordinator.getBlock(blockId);
    if (element == null) return;
    final source = coordinator.sourceOf(blockId);
    final newSource = _applyBlockPrefix(source, target);
    coordinator.handle(
      UpdateBlockSourceCommand(blockId: blockId, newSource: newSource),
    );
  }

  /// 剥离每行既有块级标记（# / > / 列表前缀），再按目标类型加前缀。
  ///
  /// - [BlockType.paragraph]：去除所有行的前缀
  /// - [BlockType.heading]：首行加 `# `，其余行去前缀
  /// - [BlockType.blockquote]：每行加 `> `
  ///
  /// 由 [BlockOperations.updateSource] 内部的 tryTransform 自动转化为目标 BlockType。
  String _applyBlockPrefix(String source, BlockType target) {
    final prefix = switch (target) {
      BlockType.heading => '# ',
      BlockType.blockquote => '> ',
      _ => null, // paragraph：仅去前缀
    };
    final lines = source.split('\n');
    // Strip existing block-level prefix from every line (fixes multi-line blockquote)
    final stripped = lines
        .map(
            (line) => line.replaceFirst(RegExp(r'^(#+\s+|>\s+|[-*+]\s+)'), ''))
        .toList();
    if (prefix == '> ') {
      // Blockquote: prefix every line
      return stripped.map((line) => '> $line').join('\n');
    } else if (prefix != null) {
      // Heading: # prefix only on first line
      stripped[0] = '$prefix${stripped[0]}';
    }
    return stripped.join('\n');
  }
}
