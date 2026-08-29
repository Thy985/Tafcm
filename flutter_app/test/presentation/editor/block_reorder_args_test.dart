import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/presentation/editor/block_reorder.dart';

/// [blockReorderArgs] 纯函数单测（Phase 3.5.5）。
///
/// 语义对齐 [ReorderableListView.onReorderItem]：newIndex 已扣除被移除项，
/// 等价于 `list.insert(newIndex, list.removeAt(oldIndex))`。
void main() {
  group('blockReorderArgs', () {
    final ids = const [
      BlockId('0'),
      BlockId('1'),
      BlockId('2'),
      BlockId('3'),
    ];

    test('下移 (old < new)：refId=ids[newIndex], before=false', () {
      final a = blockReorderArgs(ids, 0, 2)!;
      expect(a.targetId, const BlockId('0'));
      expect(a.refId, const BlockId('2'));
      expect(a.before, isFalse);
    });

    test('上移 (old > new)：refId=ids[newIndex], before=true', () {
      final a = blockReorderArgs(ids, 3, 1)!;
      expect(a.targetId, const BlockId('3'));
      expect(a.refId, const BlockId('1'));
      expect(a.before, isTrue);
    });

    test('相邻下移 (old=0,new=1)：refId=ids[1], before=false', () {
      final a = blockReorderArgs(ids, 0, 1)!;
      expect(a.targetId, const BlockId('0'));
      expect(a.refId, const BlockId('1'));
      expect(a.before, isFalse);
    });

    test('相同索引 -> null（无实际移动）', () {
      expect(blockReorderArgs(ids, 1, 1), isNull);
    });

    test('索引越界 -> null', () {
      expect(blockReorderArgs(ids, -1, 1), isNull);
      expect(blockReorderArgs(ids, 1, 99), isNull);
    });
  });
}
