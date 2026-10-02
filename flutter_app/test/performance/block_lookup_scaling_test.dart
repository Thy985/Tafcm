/// #247 结构守门：块查找复杂度必须是 O(1)，不得退化为 O(n)。
///
/// **背景**：PR #299 把 `InMemoryDocumentEditor` 的块存储从「List + 线性扫描」
/// 改为 `Map<BlockId, _Entry>`（`flutter_app/lib/presentation/editor/
/// in_memory_document_editor.dart:28`），使 `getBlock` / `updateBlockContent` /
/// `replaceBlock` / `removeBlock` 由 O(n) 变为 O(1) 哈希查找。
///
/// **为什么不用 perf_ratchet（绝对 ms）**：O(1) 哈希查找的单次耗时在纳秒级，
/// 被计时器噪声与循环开销完全淹没。`perf_baseline.json` 的
/// 「median ≤ baseline × slack」模型无法区分 O(1) 与 O(n)——两者都能通过，
/// 绝对值棘轮在此场景只会制造 flake，不会报警。
///
/// **本测试改用「规模比」守门**：对两种规模（相差 16×）的编辑器各做**相同次数**
/// 的查找，取单次耗时之比。
/// - O(1) → 单次耗时与块数无关 → 比值 ≈ 1
/// - O(n) → 单次耗时正比于块数 → 比值 ≈ 16
///
/// 阈值 [_maxRatio] 距 O(n) 理论值 16 有 5× 余量，比 O(1) 理论值 1 高 3×。
/// 比值是同进程内的相对量，因此跨机器可比、对抖动不敏感。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_serializer.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';

/// 小规模编辑器块数。
const _smallBlocks = 250;

/// 大规模编辑器块数（与 [_smallBlocks] 相差 16×）。
const _largeBlocks = 4000;

/// 每种规模的查找次数（两种规模必须相同，否则循环开销会污染比值）。
const _lookups = 200000;

/// 交替测量的轮数。
///
/// 交替（small → large → small → large）可抵消「先测的那组吃到 CPU 降频 /
/// 升频」的系统性偏差。
const _rounds = 5;

/// 允许的耗时比上限。
///
/// O(1) 理论值 1.0；O(n) 理论值 16.0。取 3.0 居中，两侧均留 3~5× 余量。
const _maxRatio = 3.0;

/// 构造一个含 [count] 块的编辑器。
InMemoryDocumentEditor _buildEditor(int count) {
  final editor = InMemoryDocumentEditor();
  for (var i = 0; i < count; i++) {
    editor.insertBlock(
      i,
      toElement('第 $i 段正文，含 **加粗**。', BlockType.paragraph),
    );
  }
  expect(editor.blockCount, count, reason: '样本构造失败：实际块数不符。');
  return editor;
}

/// 对 [editor] 中**最坏位置**（最后一个块）执行 [_lookups] 次 `getBlock`，
/// 返回单次耗时（微秒）。
double _getBlockUs(InMemoryDocumentEditor editor) {
  final target = editor.allIds.last;
  // 预热：避免首次调用的 JIT 编译与惰性初始化计入。
  for (var i = 0; i < 2000; i++) {
    editor.getBlock(target);
  }

  var hits = 0;
  final sw = Stopwatch()..start();
  for (var i = 0; i < _lookups; i++) {
    // 累加结果既是数据依赖（防止死代码消除），也验证每次查找都命中。
    if (editor.getBlock(target) != null) hits++;
  }
  sw.stop();

  expect(hits, _lookups, reason: '存在未命中的查找，样本构造有误。');
  return sw.elapsedMicroseconds / _lookups;
}

/// 对 [editor] 中**最坏位置**的块执行 [_lookups] 次 `updateBlockContent`，
/// 返回单次耗时（微秒）。
///
/// 被写入的 [DocumentElement] **预先构造好并在循环外复用**——否则循环内
/// `toElement` 的解析开销（单块约 0.07ms）会完全淹没待测的哈希写入，
/// 测到的就不再是查找复杂度。
double _updateContentUs(InMemoryDocumentEditor editor) {
  final target = editor.allIds.last;
  final next = toElement('改写后的段落内容。', BlockType.paragraph);

  for (var i = 0; i < 2000; i++) {
    editor.updateBlockContent(target, next);
  }

  final sw = Stopwatch()..start();
  for (var i = 0; i < _lookups; i++) {
    editor.updateBlockContent(target, next);
  }
  sw.stop();

  expect(editor.getBlock(target), isNotNull, reason: '写入后目标块丢失。');
  return sw.elapsedMicroseconds / _lookups;
}

/// 交替测量两种规模，取比值。
///
/// **取每组 [_rounds] 轮的最小值**而非均值：`getBlock` 单次仅约 0.02us，
/// 极易被 GC / 调度 / 缓存抖动干扰，而干扰只会让耗时**变长**、不会变短，
/// 因此最小值是信噪比最高的统计量（也是基准测试的标准做法）。
/// 早期版本用「两轮均值」，实测 updateBlockContent 比值在 1.18~2.32 间抖动，
/// 阈值 3.0 只剩 1.3× 余量——即 flake 风险。改取最小值后抖动显著收敛。
double _measureRatio(double Function(InMemoryDocumentEditor) measure) {
  final small = _buildEditor(_smallBlocks);
  final large = _buildEditor(_largeBlocks);

  var smallMin = double.infinity;
  var largeMin = double.infinity;
  for (var round = 0; round < _rounds; round++) {
    final s = measure(small);
    if (s < smallMin) smallMin = s;
    final l = measure(large);
    if (l < largeMin) largeMin = l;
  }

  final ratio = largeMin / smallMin;

  // ignore: avoid_print
  print('[#247-scaling] $_smallBlocks 块=${smallMin.toStringAsFixed(5)}us / '
      '$_largeBlocks 块=${largeMin.toStringAsFixed(5)}us → 比值 '
      '${ratio.toStringAsFixed(2)}（$_rounds 轮取最小；O(1) 期望≈1，'
      'O(n) 期望≈16，上限 $_maxRatio）');

  return ratio;
}

void main() {
  test('#247 守门：getBlock 耗时不随块数线性增长（O(1) 哈希查找）', () {
    final ratio = _measureRatio(_getBlockUs);

    expect(
      ratio,
      lessThan(_maxRatio),
      reason: '块查找疑似退化为 O(n)：块数放大 '
          '${_largeBlocks / _smallBlocks}× 后，getBlock 单次耗时同步放大 '
          '${ratio.toStringAsFixed(2)}×。请检查 in_memory_document_editor.dart 是否'
          '退回 List + 线性扫描实现（PR #299 引入的 Map<BlockId, _Entry> 索引是本守门的前提）。',
    );
  });

  test('#247 守门：updateBlockContent 耗时不随块数线性增长（O(1) 哈希写入）', () {
    final ratio = _measureRatio(_updateContentUs);

    expect(
      ratio,
      lessThan(_maxRatio),
      reason: '块写入疑似退化为 O(n)：块数放大 '
          '${_largeBlocks / _smallBlocks}× 后，updateBlockContent 单次耗时同步放大 '
          '${ratio.toStringAsFixed(2)}×。请检查 in_memory_document_editor.dart 是否'
          '退回 List + 线性扫描实现。',
    );
  });

  test('#247 备注：indexOf 仍是 O(n)（PR #299 描述中的偏差）', () {
    // 本测试**不**守门 indexOf 的复杂度——按位置查询天然是 O(n)，
    // List.indexOf 是正确实现。这里显式记录该事实，防止 #247 描述里的
    // 「indexOf 已 O(1)」被后人误当成契约；其无用性跟进见 #301。
    final editor = _buildEditor(100);
    expect(editor.indexOf(editor.allIds[50]), 50);
  });
}
