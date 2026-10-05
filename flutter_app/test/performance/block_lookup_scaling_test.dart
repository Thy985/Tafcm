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
/// **本测试的守门判据（2026-10-05 修订）**：大规模侧的单次耗时绝对上限。
///
/// 早期版本用「规模比」守门（250 块 vs 4000 块的单次耗时之比 < 3.0），假设
/// O(1) → 比值 ≈ 1。该假设被 CI 实证证伪：Map 从 250 项扩到 4000 项后工作集
/// 跨出 L1，纯缓存层级延迟就能把比值推到 4+——2026-10-04 当天 CI 两次误报
/// （PR #345 / #348，实测 O(1) 代码比值 4.39），重跑即过。而真正的回退目标
/// （List + 线性扫描）在 4000 块时单次耗时是**几十微秒**量级，与 O(1) 实测
/// 0.039us 相差约 3 个数量级。
///
/// 因此改为断言 `_largeBlocks` 侧单次耗时 < [_maxLargeNPerOpUs]（1us）：
/// - O(1) + 任意缓存惩罚：仍有 ≥25× 余量，任何 runner 上都不会误报；
/// - O(n) 线性扫描：超标 30×+，必被拦下。
/// 规模比保留为**诊断输出**（打印），不再作为通过条件——缓存层级让纯比值
/// 门限在原理上无法同时避开 O(1) 误报与 O(n) 漏报。
///
/// **为什么不用 perf_ratchet（绝对 ms）**：O(1) 哈希查找的单次耗时在纳秒级，
/// `perf_baseline.json` 的「median ≤ baseline × slack」模型基线过紧；本守门
/// 的 1us 上限是**结构边界**而非棘轮基线（25× 余量），与棘轮的 flake 模式
/// 不同。
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
///
/// 取 5 万：健康路径总计时 ~0.4ms/1.9ms（int 微秒量化误差 ≤0.5%）；
/// 若真回退为线性扫描（~40us/op），5 轮总计 ~11s，仍远在测试超时之内、
/// 能给出干净的断言失败而非超时。
const _lookups = 50000;

/// 交替测量的轮数。
///
/// 交替（small → large → small → large）可抵消「先测的那组吃到 CPU 降频 /
/// 升频」的系统性偏差。
const _rounds = 5;

/// 大规模侧单次耗时的绝对上限（微秒）——本守门的**通过判据**。
///
/// O(1) 实测 0.039us（CI ubuntu-24.04），List 线性扫描回退在 4000 块时为
/// 数十 us。取 1us：对 O(1) 有 ≥25× 余量（覆盖任意缓存/调度惩罚），
/// 对 O(n) 有 ≥30× 违约量，两侧都远离抖动带。
const _maxLargeNPerOpUs = 1.0;

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

/// 交替测量两种规模，返回（小规模单次耗时, 大规模单次耗时, 规模比）。
///
/// **取每组 [_rounds] 轮的最小值**而非均值：`getBlock` 单次仅约 0.02us，
/// 极易被 GC / 调度 / 缓存抖动干扰，而干扰只会让耗时**变长**、不会变短，
/// 因此最小值是信噪比最高的统计量（也是基准测试的标准做法）。
({double smallUs, double largeUs, double ratio}) _measureScaling(
  double Function(InMemoryDocumentEditor) measure,
) {
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

  // ignore: avoid_print
  print('[#247-scaling] $_smallBlocks 块=${smallMin.toStringAsFixed(5)}us / '
      '$_largeBlocks 块=${largeMin.toStringAsFixed(5)}us → 比值 '
      '${(largeMin / smallMin).toStringAsFixed(2)}（$_rounds 轮取最小；'
      '判据：$_largeBlocks 块侧 < $_maxLargeNPerOpUs us）');

  return (smallUs: smallMin, largeUs: largeMin, ratio: largeMin / smallMin);
}

void main() {
  test('#247 守门：getBlock 大规模单次耗时保持 O(1) 量级（< 1us）', () {
    final m = _measureScaling(_getBlockUs);

    expect(
      m.largeUs,
      lessThan(_maxLargeNPerOpUs),
      reason: '块查找疑似退化为 O(n)：$_largeBlocks 块下单次 getBlock 耗时 '
          '${m.largeUs.toStringAsFixed(5)}us ≥ 上限 $_maxLargeNPerOpUs us'
          '（规模比诊断值 ${m.ratio.toStringAsFixed(2)}，O(1) 健康值 <0.05us）。'
          '请检查 in_memory_document_editor.dart 是否退回 List + 线性扫描实现'
          '（PR #299 引入的 Map<BlockId, _Entry> 索引是本守门的前提）。',
    );
  });

  test('#247 守门：updateBlockContent 大规模单次耗时保持 O(1) 量级（< 1us）', () {
    final m = _measureScaling(_updateContentUs);

    expect(
      m.largeUs,
      lessThan(_maxLargeNPerOpUs),
      reason: '块写入疑似退化为 O(n)：$_largeBlocks 块下单次 '
          'updateBlockContent 耗时 ${m.largeUs.toStringAsFixed(5)}us ≥ 上限 '
          '$_maxLargeNPerOpUs us（规模比诊断值 ${m.ratio.toStringAsFixed(2)}）。'
          '请检查 in_memory_document_editor.dart 是否退回 List + 线性扫描实现。',
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
