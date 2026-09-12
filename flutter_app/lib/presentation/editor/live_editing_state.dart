/// LiveEditingState：ADR-0012 Live Editing State（高频、不进 History）。
///
/// 落地 ADR-0012 §双状态模型——把「实时编辑文本」这一独立职责从
/// [EditorCoordinator] 抽出，避免协调器膨胀成 God Object（Phase 3.0 §2.4）。
///
/// **职责**：
/// - 保存每个 Block 的实时编辑文本（[update] 高频写入）。
/// - 驱动 wordCount / isDirty 的「实时」维度（输入即刷新，无需等待 commit）。
/// - commit（失焦 / 规则触发）后由 [reconcile] 把受影响块对齐到 committed source。
/// - undo / redo / 保存后由 [clear] 清空实时漂移。
///
/// **数据依赖**：持有 [InMemoryDocumentEditor] 引用作为「已提交状态」真源
/// （fallback / 对齐用），不拥有领域状态，符合 Hard Rule 4。
library;

import '../../core/editing/block_types.dart';
import 'in_memory_document_editor.dart';

/// Live Editing State 管理器（实时文本 / 实时字数 / 实时脏标记）。
class LiveEditingState {
  final InMemoryDocumentEditor _editor;

  /// 每个 Block 的实时编辑文本（live 优先，缺失时 fallback 到已提交 source）。
  final Map<BlockId, String> _liveSources = {};

  /// 增量 wordCount 缓存（#245 性能修复，2026-09-12）。
  ///
  /// 原实现每次按键对全文档做 O(n²) 序列化求和（allIds O(n) 分配 +
  /// getBlock 线性扫描 O(n) + fromElement 整块序列化），千行文档输入
  /// 主 isolate 达百毫秒级。现维护每块已计入长度 [blockLengths] 与
  /// 累计值 [_total]：稳态按键只做差量更新 O(1)；块集合变化
  /// （structureVersion 变）时全量重算一次——仍无 O(n²) 查找
  /// （迭代 _liveSources 与 _editor.allSources，均不按 id 扫描）。
  final Map<BlockId, int> _blockLengths = {};
  int _total = 0;
  int _cachedStructureVersion = -1;

  LiveEditingState(this._editor);

  /// 推入某 block 的实时编辑文本（由 `BaseBlockState._onTextChanged` 高频调用）。
  void update(BlockId id, String source) {
    _liveSources[id] = source;
    // 差量更新：仅当该块长度变化时调整累计值（O(1)）。
    final old = _blockLengths[id];
    if (old != null && old != source.length) {
      _total += source.length - old;
      _blockLengths[id] = source.length;
    }
  }

  /// 读取某 block 的实时文本（live 优先，fallback 到已提交 source）。
  String sourceOf(BlockId id) => _liveSources[id] ?? _editor.sourceOf(id);

  /// 清空所有实时漂移（undo / redo / 保存后调用）。
  ///
  /// 长度基线一并失效：undo 可能已改变块集合（structureVersion 已变，
  /// wordCount 会在下次读取时全量重建）；即使集合未变，把基线对齐到
  /// committed 才能保证清空后计数无残留漂移。
  void clear() {
    _liveSources.clear();
    _blockLengths.clear();
    _total = 0;
    // 强制下次读取重建基线：若集合未变，version 相等会让 getter 误判
    // 缓存有效而返回已清零的 _total（回归测试 #245 clear 用例实证）。
    _cachedStructureVersion = -1;
  }

  /// commit 成功后把 [ids] 指定的 block 对齐到 committed，
  /// 避免 false dirty / wordCount 漂移（不触碰其他 block 的 live）。
  void reconcile(Iterable<BlockId> ids) {
    for (final id in ids) {
      final source = _editor.sourceOf(id);
      final old = _blockLengths[id];
      if (old != null) {
        if (old != source.length) {
          _total += source.length - old;
        }
      } else {
        // 该块不在基线里（基线从未建立 / clear 后）：累计值不可信，
        // 强制下次读取全量重建（live-first，必含对齐后的 committed）。
        // 实证：editor_coordinator_test undo 用例——基线未建时跳过差量
        // 会让 _total 停在旧值。
        _cachedStructureVersion = -1;
      }
      _liveSources[id] = source;
      _blockLengths[id] = source.length;
    }
  }

  /// 实时字数：对所有 block 累加实时文本长度（live 优先）。
  ///
  /// #245 增量实现：稳态（块集合未变）直接返回累计值 O(1)；
  /// 块集合变化（structureVersion 变）时全量重算一次 O(n)（n = 块数，
  /// allSources 已按序给出全部 committed source，无按 id 扫描），并
  /// 重建 [blockLengths] 基线。live 漂移经 [update] 差量计入。
  int get wordCount {
    if (_cachedStructureVersion != _editor.structureVersion) {
      _total = 0;
      _blockLengths.clear();
      for (final id in _editor.allIds) {
        // live-first（原实现语义）：live 漂移的块按实时长度计入。
        final len = sourceOf(id).length;
        _blockLengths[id] = len;
        _total += len;
      }
      _cachedStructureVersion = _editor.structureVersion;
    }
    return _total;
  }

  /// 实时 dirty：已提交脏标记 **或** 任意 live source 与 committed 不一致。
  ///
  /// 复杂度：O(n)（n = block 数），每次 [EditorCoordinator.notifyListeners] 翻转时遍历。
  /// 该路径由 `BaseBlockState._onTextChanged` 在每次按键触发，故为高频路径。
  /// 预期文档规模下开销可忽略（ADR-0013 评审·代码 #4）；若未来出现大文档 TTI 退化，
  /// 可优化为「脏 block 集合」仅增量维护差异，而非全量比较。
  bool get isDirty {
    if (_editor.isDirty) return true;
    for (final id in _editor.allIds) {
      final live = _liveSources[id];
      if (live != null && live != _editor.sourceOf(id)) return true;
    }
    return false;
  }
}
