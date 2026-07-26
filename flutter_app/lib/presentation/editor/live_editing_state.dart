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

  LiveEditingState(this._editor);

  /// 推入某 block 的实时编辑文本（由 `BaseBlockState._onTextChanged` 高频调用）。
  void update(BlockId id, String source) => _liveSources[id] = source;

  /// 读取某 block 的实时文本（live 优先，fallback 到已提交 source）。
  String sourceOf(BlockId id) => _liveSources[id] ?? _editor.sourceOf(id);

  /// 清空所有实时漂移（undo / redo / 保存后调用）。
  void clear() => _liveSources.clear();

  /// commit 成功后把 [ids] 指定的 block 对齐到 committed，
  /// 避免 false dirty / wordCount 漂移（不触碰其他 block 的 live）。
  void reconcile(Iterable<BlockId> ids) {
    for (final id in ids) {
      _liveSources[id] = _editor.sourceOf(id);
    }
  }

  /// 实时字数：对所有 block 累加实时文本长度（live 优先）。
  int get wordCount {
    var sum = 0;
    for (final id in _editor.allIds) {
      sum += sourceOf(id).length;
    }
    return sum;
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
