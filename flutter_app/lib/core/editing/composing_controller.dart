/// ComposingController 纯 Dart 逻辑层。
///
/// 落地 ADR-0007 §3.2 三铁律，不依赖 Flutter widget。
/// 详见 ADR-0007 §3.3（测试隔离）+ ADR-0008 §5（Transaction 接入预留）
/// + Phase 2.5 Task Contract §3.2 / §3.3。
///
/// 单一真相源原则（评审反馈 4）：
/// - composing region 真相源在 [ComposingHost]（对齐 TextEditingController.composingRange）
/// - ComposingController 不保存 composing region，仅保存 state + source backup
/// - 避免双 source of truth 不同步
library;

import 'block_types.dart';
import 'composing_state.dart';

/// ComposingHost 抽象接口。
///
/// 隔离 Flutter TextEditingController，使 [ComposingController] 可独立单测。
/// 详见 ADR-0007 §3.3（测试隔离）。
///
/// Phase 3 UI 层实现具体类，包装真实 TextEditingController。
/// Phase 2.5 单测用 mock 实现。
abstract class ComposingHost {
  /// 当前块的可编辑 source。
  String get source;

  /// 当前 composing region（与 TextEditingController.composingRange 对齐）。
  ///
  /// 真相源在 host，ComposingController 不保存（评审反馈 4）。
  ComposingRegion get composing;

  /// 替换 [start, end) 区间为 [replacement]。
  ///
  /// 铁律 2（commit 不丢字）的核心方法。
  /// 不覆盖整个 source，仅替换 composing region。
  void replaceRange(int start, int end, String replacement);

  /// 恢复到 [source] 状态。
  ///
  /// 铁律 3（cancel 回滚）的核心方法。
  ///
  /// **Phase 2.5 仅保证 source rollback**（评审反馈 3）：
  /// cursor / selection / composing range 归 Phase 2.6 Transaction Model 统一回滚。
  void restoreSource(String source);
}

/// Composing 状态变化观测回调（G2 修复，2026-08-10）。
///
/// **修复 G2**：ComposingController 在状态机转换时通过此回调通知上层，
/// 上层（presentation/blocks/base_block_state）把回调桥接到
/// [ObservabilityService.recordInteraction]，解决 IME composing
/// 异常路径无独立可观测信号的问题。
///
/// **为什么用抽象回调而非直接依赖 ObservabilityService**：
/// - 保持 core/editing 层纯 Dart（不依赖 core/observability）
/// - 单元测试可用 mock 回调断言状态变化
/// - 上层自由选择如何处理（落 trace / 上报 / 日志）
typedef ComposingObserver = void Function({
  required ComposingState newState,
  required ComposingRegion composing,
  required int sourceLength,
  required ComposingEvent event,
});

/// ComposingController 纯 Dart 逻辑层。
///
/// 落地 ADR-0007 §3.2 三铁律：
/// - 铁律 1（不切块）：[canEditBlock] / [assertBlockMutationAllowed]
/// - 铁律 2（commit 不丢字）：[onComposingCommit]
/// - 铁律 3（cancel 回滚）：[onComposingCancel]
///
/// **G2 修复（2026-08-10）**：可选 [observer] 回调在每次状态转换后被调用，
/// 用于把 composing 状态变化事件上报到可观测系统。
class ComposingController {
  final ComposingHost _host;
  final ComposingObserver? _observer;
  ComposingState _state = ComposingState.idle;

  /// 铁律 3 回滚备份（仅 source，不含 cursor/selection）。
  ///
  /// Phase 2.5 边界（评审反馈 3）：
  /// - ✅ source rollback（本 Phase 实现）
  /// - ❌ cursor / selection rollback（Phase 2.6 Transaction 上下文）
  String? _sourceBeforeComposing;

  ComposingController(this._host, {ComposingObserver? observer})
      : _observer = observer;

  /// 通知观测器（内部 helper）。
  ///
  /// 抽成 helper 让所有状态转换走同一路径，便于测试 mock 计数。
  void _notifyObserver(ComposingEvent event) {
    final cb = _observer;
    if (cb == null) return;
    cb(
      newState: _state,
      composing: _host.composing,
      sourceLength: _host.source.length,
      event: event,
    );
  }

  /// 当前状态。
  ComposingState get state => _state;

  /// 是否处于组合态（铁律 1 用）。
  ///
  /// composing / committing / cancelling 都视为"不可切块"。
  bool get isActive => _state != ComposingState.idle;

  /// 铁律 1：组合态中间不切块（查询接口）。
  ///
  /// 调用方在 onBlur / split / merge 前可选检查此方法。
  /// 若返回 false，调用方必须先 commit 或 cancel。
  bool canEditBlock() => !isActive;

  /// 铁律 1：组合态中间不切块（架构约束，评审反馈 2）。
  ///
  /// 所有 BlockOperation（insert / delete / merge / split / move）必须先调用此方法。
  /// 把铁律 1 从"编码规范"升级为"架构约束"——开发者无法绕过。
  ///
  /// Phase 2.6 BlockOperation 实现时，每个操作前置调用：
  /// ```dart
  /// void insert(BlockId afterId, DocumentElement element) {
  ///   _composing.assertBlockMutationAllowed();
  ///   // ... 后续逻辑
  /// }
  /// ```
  void assertBlockMutationAllowed() {
    if (_state != ComposingState.idle) {
      throw StateError(
        'Block mutation forbidden during IME composing (state=$_state). '
        'Commit or cancel composing first.',
      );
    }
  }

  /// IME composing 开始。
  ///
  /// 备份当前 source 用于铁律 3 回滚。
  void onComposingStart() {
    _state = transitionComposingState(
      current: _state,
      event: ComposingEvent.start,
    );
    _sourceBeforeComposing = _host.source;
    _notifyObserver(ComposingEvent.start);
  }

  /// IME composing 更新（self-transition，评审反馈 1）。
  ///
  /// 状态保持 composing，仅 composing region 变化。
  /// composing region 真相源在 [_host]，不保存到 controller（评审反馈 4）。
  void onComposingUpdate() {
    _state = transitionComposingState(
      current: _state,
      event: ComposingEvent.update,
    );
    // composing region 由 host 管理（对齐 TextEditingController.composingRange）
    _notifyObserver(ComposingEvent.update);
  }

  /// 铁律 2：commit 时不丢字。
  ///
  /// 用 [committedText] 替换 composing region，不覆盖整个 source。
  ///
  /// 流程：
  /// 1. composing → committing（状态转换）
  /// 2. host.replaceRange(composing.start, composing.end, committedText)
  /// 3. committing → idle（commitComplete）
  /// 4. 清空 _sourceBeforeComposing（已 commit，无需回滚）
  void onComposingCommit(String committedText) {
    _state = transitionComposingState(
      current: _state,
      event: ComposingEvent.commit,
    );
    final composing = _host.composing;
    _host.replaceRange(
      composing.start,
      composing.end,
      committedText,
    );
    _state = transitionComposingState(
      current: _state,
      event: ComposingEvent.commitComplete,
    );
    _sourceBeforeComposing = null;
    _notifyObserver(ComposingEvent.commitComplete);
  }

  /// 铁律 3：cancel 时回滚。
  ///
  /// 恢复到 commit 前 source。
  ///
  /// **Phase 2.5 仅保证 source rollback**（评审反馈 3）：
  /// cursor / selection / composing range 归 Phase 2.6 Transaction Model
  /// 统一回滚（Transaction 上下文携带光标状态）。
  void onComposingCancel() {
    _state = transitionComposingState(
      current: _state,
      event: ComposingEvent.cancel,
    );
    final backup = _sourceBeforeComposing;
    if (backup != null) {
      _host.restoreSource(backup);
    }
    _state = transitionComposingState(
      current: _state,
      event: ComposingEvent.cancelComplete,
    );
    _sourceBeforeComposing = null;
    _notifyObserver(ComposingEvent.cancelComplete);
  }
}
