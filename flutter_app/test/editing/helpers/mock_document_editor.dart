/// DocumentEditor 的 mock 实现（测试专用）。
///
/// 用于 Phase 2.6 各类测试（TC-EDIT-6.1 ~ 6.9）验证 EditOperation / Transaction /
/// EditorHistory / BlockOperations 的 apply / revert 行为，无需依赖真实 UI 层。
///
/// 维护 `List<_Entry>` 保存每个 [BlockId] 对应的 [DocumentElement]，
/// 模拟真实 DocumentEditor 的 BlockId 分配 / 查找 / 修改行为。
///
/// **不暴露 listener**（v1.1 评审反馈 2：DocumentEditor 是 model mutation boundary，
/// notification 责任在 [TransactionBuilder.commit] 一层）。
///
/// 本文件仅用于 test/，不放入 lib/。
library;

import 'package:tafcm/core/editing/block_serializer.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/document_editor.dart';
import 'package:tafcm/data/models/document.dart';

/// 用于单测的 [DocumentEditor] mock 实现。
///
/// 维护 `List<_Entry>` 保存每个 [BlockId] 对应的 [DocumentElement]，
/// 模拟真实 DocumentEditor 的 BlockId 分配 / 查找 / 修改行为。
///
/// 提供 [addParagraph] / [sourceOf] 等测试辅助方法，简化测试代码。
class MockDocumentEditor implements DocumentEditor {
  final Map<BlockId, _Entry> _blocks = {};
  final List<BlockId> _ids = [];

  MockDocumentEditor();

  @override
  int get blockCount => _ids.length;

  @override
  DocumentElement? getBlock(BlockId id) => _blocks[id]?.element;

  @override
  int indexOf(BlockId id) => _ids.indexOf(id);

  @override
  BlockId insertBlock(int index, DocumentElement element, {BlockId? preserveId}) {
    if (index < 0 || index > _ids.length) {
      throw RangeError('index out of range: $index');
    }
    final id = preserveId ?? BlockId.generate();
    _ids.insert(index, id);
    _blocks[id] = _Entry(id, element);
    return id;
  }

  @override
  DocumentElement removeBlock(BlockId id) {
    final entry = _blocks.remove(id);
    if (entry == null) {
      throw StateError('BlockId not found: $id');
    }
    _ids.remove(id);
    return entry.element;
  }

  @override
  DocumentElement replaceBlock(BlockId id, DocumentElement element) {
    final entry = _blocks[id];
    if (entry == null) {
      throw StateError('BlockId not found: $id');
    }
    // Phase 3.1-A PR #2（R5）：保持 BlockId 不变（之前是分配新 BlockId）
    _blocks[id] = _Entry(id, element);
    return entry.element;
  }

  @override
  DocumentElement replaceBlockKeepId(BlockId id, DocumentElement element) {
    return replaceBlock(id, element);
  }

  @override
  DocumentElement replaceBlockWithMigration(
    BlockId id,
    DocumentElement element, {
    void Function(BlockId oldId, BlockId newId)? onMigrated,
  }) {
    final entry = _blocks[id];
    if (entry == null) {
      throw StateError('BlockId not found: $id');
    }
    final old = entry.element;
    final newId = BlockId.generate();
    _ids[_ids.indexOf(id)] = newId;
    _blocks.remove(id);
    _blocks[newId] = _Entry(newId, element);
    onMigrated?.call(id, newId);
    return old;
  }

  @override
  void updateBlockContent(BlockId id, DocumentElement newContent) {
    if (!_blocks.containsKey(id)) {
      throw StateError('BlockId not found: $id');
    }
    _blocks[id] = _Entry(id, newContent);
  }

  // ============ 测试辅助方法 ============

  /// 用 source 构造 [ParagraphElement] 并插入到末尾，返回 [BlockId]。
  BlockId addParagraph(String source) {
    return insertBlock(_ids.length, ParagraphElement(children: [
      TextElement(source),
    ]));
  }

  /// 用 source 构造 [ParagraphElement] 并插入到指定位置，返回 [BlockId]。
  BlockId addParagraphAt(int index, String source) {
    return insertBlock(index, ParagraphElement(children: [
      TextElement(source),
    ]));
  }

  /// 用任意 source + type 构造 [DocumentElement] 并插入到末尾，返回 [BlockId]。
  BlockId addBlock(String source, BlockType type) {
    return insertBlock(_ids.length, toElement(source, type));
  }

  /// 获取指定 [BlockId] 对应块的 Markdown source（通过 [fromElement] 序列化）。
  ///
  /// 找不到时抛 [StateError]。
  String sourceOf(BlockId id) {
    final element = getBlock(id);
    if (element == null) {
      throw StateError('BlockId not found: $id');
    }
    return fromElement(element);
  }

  /// 返回所有块的 source 列表（用于断言整体状态）。
  List<String> get allSources {
    return [for (final id in _ids) fromElement(_blocks[id]!.element)];
  }

  /// 返回当前所有 BlockId 列表（按顺序）。
  @override
  List<BlockId> get allIds => List.unmodifiable(_ids);
}

class _Entry {
  final BlockId id;
  final DocumentElement element;
  _Entry(this.id, this.element);
}
