/// Editor Integrity Monitor：编辑器完整性监视器（Layer 0）。
///
/// 在每次 Transaction commit 后自动验证编辑器核心不变量，及早发现状态损坏。
/// 不变量失败不会阻止编辑器继续运行（不影响用户体验），但会自动触发 Error Snapshot。
///
/// 落地 ADR-0021 §2.7。
library;

import '../../data/models/document.dart';
import '../editing/block_serializer.dart';
import 'models.dart';

/// 编辑器不变量检查器（sealed class）。
sealed class EditorInvariant {
  /// 不变量名称。
  String get name;

  /// 检查是否通过。
  bool check(List<EditorInvariantContext> state);
}

/// 不变量检查上下文（从 [DocumentEditor] 提取的不可变快照）。
class EditorInvariantContext {
  final String blockId;
  final DocumentElement element;
  final String? parentId;

  /// History 栈中所有 ops 引用的 BlockId 集合（仅 [HistoryConsistent] 使用）。
  final Set<String> historyBlockIds;

  const EditorInvariantContext({
    required this.blockId,
    required this.element,
    this.parentId,
    this.historyBlockIds = const {},
  });
}

/// Invariant 1：Cursor 指向的 Block 必须存在。
///
/// 若 cursor 的 blockId 被删除但 cursor 未更新，编辑器将崩溃。
class CursorExists extends EditorInvariant {
  final String? cursorBlockId;

  CursorExists({this.cursorBlockId});

  @override
  String get name => 'CursorExists';

  @override
  bool check(List<EditorInvariantContext> state) {
    if (cursorBlockId == null) return true; // 无光标时跳过
    return state.any((b) => b.blockId == cursorBlockId);
  }
}

/// Invariant 2：Selection range 在 Block source 长度范围内。
///
/// 防止 selection 越界导致 ArrayIndexOutOfBounds 类错误。
class SelectionValid extends EditorInvariant {
  final String? selectionBlockId;
  final int? selectionStart;
  final int? selectionEnd;

  SelectionValid({
    this.selectionBlockId,
    this.selectionStart,
    this.selectionEnd,
  });

  @override
  String get name => 'SelectionValid';

  @override
  bool check(List<EditorInvariantContext> state) {
    if (selectionBlockId == null || selectionStart == null || selectionEnd == null) {
      return true;
    }
    if (selectionStart! < 0 || selectionStart! > selectionEnd!) return false;
    final block = state.where((b) => b.blockId == selectionBlockId).firstOrNull;
    if (block == null) return false;
    final sourceLength = fromElement(block.element).length;
    return selectionEnd! <= sourceLength;
  }
}

/// Invariant 3：Block 树无环。
///
/// Block 树中 parentId 不应形成循环引用。
class BlockTreeAcyclic extends EditorInvariant {
  @override
  String get name => 'BlockTreeAcyclic';

  @override
  bool check(List<EditorInvariantContext> state) {
    for (final block in state) {
      if (block.parentId == null) continue;
      // 检测环：从当前 block 沿 parentId 链向上追溯
      final chain = <String>{};
      String? current = block.blockId;
      while (current != null) {
        if (chain.contains(current)) return false; // 发现环
        chain.add(current);
        final parent = state.where((b) => b.blockId == current).firstOrNull;
        current = parent?.parentId;
      }
    }
    return true;
  }
}

/// Invariant 4：所有子 Block 的 parentId 指向存在的父 Block。
class ParentChildValid extends EditorInvariant {
  @override
  String get name => 'ParentChildValid';

  @override
  bool check(List<EditorInvariantContext> state) {
    for (final block in state) {
      if (block.parentId == null) continue;
      if (!state.any((b) => b.blockId == block.parentId)) {
        return false; // parentId 指向不存在的 Block
      }
    }
    return true;
  }
}

/// Invariant 5：空检查（Block 数量不为 0）。
///
/// 编辑器至少应有一个 Block（空文档也应有 Paragraph）。
class EditorNotEmpty extends EditorInvariant {
  @override
  String get name => 'EditorNotEmpty';

  @override
  bool check(List<EditorInvariantContext> state) {
    return state.isNotEmpty;
  }
}

/// Invariant 6：History 栈中引用的 BlockId 在当前 editor 中仍存在。
///
/// 若 History 栈中 Transaction 的 ops 引用了已删除的 BlockId，
/// undo/redo 将无法正确 revert，导致状态损坏。
class HistoryConsistent extends EditorInvariant {
  @override
  String get name => 'HistoryConsistent';

  @override
  bool check(List<EditorInvariantContext> state) {
    final historyIds = state.firstOrNull?.historyBlockIds;
    if (historyIds == null || historyIds.isEmpty) return true;
    final currentIds = state.map((b) => b.blockId).toSet();
    return historyIds.every((id) => currentIds.contains(id));
  }
}

/// 不变量检查器集合。
///
/// 运行所有已注册的编辑器不变量，返回失败列表。
class InvariantChecker {
  final List<EditorInvariant> _invariants;

  InvariantChecker({
    String? cursorBlockId,
    int? selectionStart,
    int? selectionEnd,
    String? selectionBlockId,
  }) : _invariants = [
    CursorExists(cursorBlockId: cursorBlockId),
    SelectionValid(
      selectionBlockId: selectionBlockId,
      selectionStart: selectionStart,
      selectionEnd: selectionEnd,
    ),
    BlockTreeAcyclic(),
    ParentChildValid(),
    EditorNotEmpty(),
    HistoryConsistent(),
  ];

  /// 运行所有不变量检查。
  ///
  /// 返回不变量名称 → 是否通过 的映射。
  /// 若全部通过，返回空列表。
  List<InvariantFailure> checkAll(List<EditorInvariantContext> state) {
    final failures = <InvariantFailure>[];
    for (final invariant in _invariants) {
      if (!invariant.check(state)) {
        failures.add(InvariantFailure(
          invariantName: invariant.name,
          message: 'Invariant "$invariant" failed',
          timestamp: DateTime.now(),
        ));
      }
    }
    return failures;
  }
}