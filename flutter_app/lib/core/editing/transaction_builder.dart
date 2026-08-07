/// TransactionBuilder：收集 [EditOperation] 并构造 [Transaction]。
///
/// 落地 ADR-0008 §3（TransactionBuilder commit/rollback 原子性）+ §5（与 IME 交互）。
///
/// v1.2 关键约束：
/// - [TransactionId] 在 Builder **创建时**生成（非 commit 时），便于 debug 追踪
/// - onChange 回调：顶层 commit 时触发 1 次（嵌套 commit 不触发，合并到 parent）
/// - rollback：丢弃已收集的 ops，不应用任何变更
/// - 嵌套合并：子 builder commit 时把 ops 合并到 parent（explicit parent-child merge，
///   no ambient transaction context）
///
/// **apply 责任**：本类只负责 **收集** op + 构造 [Transaction]。
/// 实际 apply 到 [DocumentEditor] 的责任在 [EditorHistory] 或调用方。
///
/// 详见 Phase 2.6 Task Contract §3.5。
library;

import 'edit_operation.dart';
import 'transaction.dart';
import '../observability/models.dart' as obs;
import '../observability/observability_service.dart';

/// 顶层 commit 时触发的回调类型（1 commit = 1 notification）。
///
/// 调用方（如 EditorHistory）在此回调中：
/// 1. 对 [DocumentEditor] 应用 [Transaction.ops]
/// 2. 把 [Transaction] 推入 undo 栈
/// 3. 触发 UI rebuild（通过 ChangeNotifier）
typedef TransactionChangeListener = void Function(Transaction transaction);

/// 编辑器状态快照提供者（用于 Transaction Trace 的 before/after snapshot）。
///
/// 返回 blocks source 摘要（每块首 80 字符 + BlockId），供诊断时定位状态变化。
typedef StateSnapshotProvider = String Function();

/// [Transaction] 的构造器（收集 [EditOperation] 并 commit）。
///
/// 用法：
/// ```dart
/// final builder = TransactionBuilder(
///   origin: TransactionOrigin.keyboard,
///   onChange: (tx) => history.apply(tx),
/// );
/// builder.add(TextOperation(...));
/// builder.add(TextOperation(...));
/// builder.commit(label: '输入 hello');
/// ```
///
/// **嵌套用法**（子 builder 的 ops 合并到 parent）：
/// ```dart
/// final parent = TransactionBuilder(origin: TransactionOrigin.programmatic);
/// parent.add(op1);
///
/// final child = TransactionBuilder(
///   origin: TransactionOrigin.programmatic,
///   parent: parent,
/// );
/// child.add(op2);
/// child.commit();  // 不触发 onChange，op2 合并到 parent
///
/// parent.commit();  // 触发 onChange，包含 op1 + op2
/// ```
class TransactionBuilder {
  /// 此 builder 的 id（创建时生成，commit 时复用）。
  final TransactionId id;

  /// 操作来源。
  final TransactionOrigin origin;

  /// 父 builder（嵌套时非 null）。
  final TransactionBuilder? parent;

  /// 顶层 commit 时触发的回调（嵌套 builder 的 commit 不触发）。
  final TransactionChangeListener? onChange;

  /// 可观测服务（可选，LIGHT 模式下默认开启）。
  final ObservabilityService? observability;

  /// 编辑器状态快照提供者（可选，用于 Transaction Trace 的 before/after snapshot）。
  final StateSnapshotProvider? stateSnapshotProvider;

  /// 默认标签（commit 时若未指定 label 则用此值）。
  final String? _defaultLabel;

  final List<EditOperation> _ops = [];

  bool _committed = false;
  bool _rolledBack = false;

  /// 事务开始前的状态快照（commit 时填充 beforeSnapshot）。
  String? _beforeSnapshot;

  /// 事务开始时间（commit 时计算 elapsed）。
  final DateTime _startedAt;

  TransactionBuilder({
    required this.origin,
    this.parent,
    this.onChange,
    this.observability,
    this.stateSnapshotProvider,
    String? label,
  })  : id = TransactionId.next(),
        _defaultLabel = label,
        _startedAt = DateTime.now() {
    _beforeSnapshot = stateSnapshotProvider?.call();
  }

  /// 是否嵌套（有 parent）。
  bool get isNested => parent != null;

  /// 是否已完成（commit 或 rollback）。
  bool get isCompleted => _committed || _rolledBack;

  /// 已收集的 ops（不可变视图）。
  List<EditOperation> get ops => List.unmodifiable(_ops);

  /// 已收集的 op 数量。
  int get opCount => _ops.length;

  /// 添加 op 到当前事务。
  ///
  /// 若已完成（commit 或 rollback）抛 [StateError]。
  void add(EditOperation op) {
    if (isCompleted) {
      throw StateError(
          'TransactionBuilder already completed (committed=$_committed, rolledBack=$_rolledBack)');
    }
    _ops.add(op);
  }

  /// 提交事务，返回构造的 [Transaction]。
  ///
  /// - 顶层 builder（[isNested] == false）：触发 [onChange] 回调 1 次
  /// - 嵌套 builder（[isNested] == true）：把 ops 合并到 [parent]，不触发 [onChange]
  ///
  /// 若已完成抛 [StateError]。
  ///
  /// 可选 [label]：覆盖默认 label；不传则用构造时的 [_defaultLabel]。
  Transaction commit({String? label}) {
    if (isCompleted) {
      throw StateError(
          'TransactionBuilder already completed (committed=$_committed, rolledBack=$_rolledBack)');
    }
    _committed = true;

    final transaction = Transaction(
      id: id,
      ops: List.unmodifiable(_ops),
      metadata: TransactionMetadata(
        timestamp: DateTime.now(),
        label: label ?? _defaultLabel,
      ),
      origin: origin,
    );

    if (isNested) {
      // 嵌套 commit：把 ops 合并到 parent（不触发 onChange）
      for (final op in _ops) {
        parent!.add(op);
      }
    } else {
      // 顶层 commit：
      // **P1 信噪比修复（2026-08-06）**：空 ops 顶层 commit 是 no-op
      // （CommandHandler 的 _dispatch 返回 true 但实际无 op，例如幂等命令）。
      // 此时不触发 onChange（不污染 undo 栈）也不记录 trace（不污染 RingBuffer），
      // 与 [BaseBlockState._commitSource] 的 no-op guard 对齐。
      if (_ops.isEmpty) {
        return transaction;
      }
      // 顶层 commit：触发 onChange 1 次
      onChange?.call(transaction);

      // === Observability: 记录 Transaction 轨迹 ===
      _recordTransactionTrace(transaction, obs.TransactionResult.commit);
    }

    return transaction;
  }

  /// 记录 Transaction 轨迹到 ObservabilityService。
  void _recordTransactionTrace(
    Transaction transaction,
    obs.TransactionResult result, {
    String? rollbackReason,
  }) {
    final svc = observability;
    if (svc?.isEnabled != true) return;
    final ctx = svc!.currentContext;

    final afterSnapshot = (result == obs.TransactionResult.commit)
        ? stateSnapshotProvider?.call()
        : null;

    final operations = transaction.ops.map((op) {
      String blockId = '';
      if (op is TextOperation) {
        blockId = op.blockId.value;
      }
      return obs.OperationSummary(
        type: op.runtimeType.toString(),
        blockId: blockId,
      );
    }).toList();

    svc.recordTransaction(obs.TransactionTraceEntry(
      transactionId: transaction.id.toString(),
      origin: _mapOrigin(transaction.origin),
      beforeSnapshot: _beforeSnapshot ?? '',
      beforeHash: '',
      operations: operations,
      afterSnapshot: afterSnapshot ?? '',
      afterHash: '',
      result: result,
      rollbackReason: rollbackReason,
      elapsed: DateTime.now().difference(_startedAt),
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
    ));
  }

  obs.TransactionOrigin _mapOrigin(TransactionOrigin origin) {
    return switch (origin) {
      TransactionOrigin.keyboard => obs.TransactionOrigin.keyboard,
      TransactionOrigin.ime => obs.TransactionOrigin.ime,
      TransactionOrigin.paste => obs.TransactionOrigin.paste,
      TransactionOrigin.programmatic => obs.TransactionOrigin.programmatic,
      TransactionOrigin.undo => obs.TransactionOrigin.undo,
      TransactionOrigin.redo => obs.TransactionOrigin.redo,
    };
  }

  /// 回滚事务：丢弃已收集的 ops，不应用任何变更。
  ///
  /// - 顶层 builder：直接清空 ops
  /// - 嵌套 builder：仅清空子 builder 的 ops（不影响 parent 已收集的 ops）
  ///
  /// 若已完成抛 [StateError]。
  ///
  /// **P1 信噪比修复（2026-08-06）**：新增 [unexpected] 参数区分回滚语义：
  /// - `unexpected=false`（默认）：良性回滚。CommandHandler 在 `_dispatch`
  ///   返回 false 时（守卫拒绝 / no-op / 校验失败）调用 [revertBuilder]
  ///   后再 `rollback()`，状态已被 revert 恢复，不是异常 → 仅记录 trace，
  ///   **不触发 ErrorSnapshot**，避免良性回滚淹没真正异常。
  /// - `unexpected=true`：非预期回滚。CommandHandler 在 catch 异常后调用
  ///   `rollback(unexpected: true)`，这才是 ADR-0021 §3.7.2 所指"非预期回滚"
  ///   → 触发 ErrorSnapshot。
  void rollback({bool unexpected = false}) {
    if (isCompleted) {
      throw StateError(
          'TransactionBuilder already completed (committed=$_committed, rolledBack=$_rolledBack)');
    }
    _rolledBack = true;
    _ops.clear();

    // === Observability: 记录 Transaction rollback ===
    // 仅顶层 builder 记录（嵌套 builder 的 rollback 合并到 parent）
    if (!isNested) {
      _recordTransactionTrace(
        Transaction(
          id: id,
          ops: const [],
          metadata: TransactionMetadata(
            timestamp: DateTime.now(),
            label: _defaultLabel,
          ),
          origin: origin,
        ),
        obs.TransactionResult.rollback,
        rollbackReason:
            unexpected ? 'unexpected (exception)' : 'benign (guard rejected)',
      );

      // === Observability: 触发 Error Snapshot（仅非预期回滚） ===
      // P1 修复前：所有 rollback 都触发 ErrorSnapshot，导致良性 guard 拒绝
      // 也产生"错误"快照，淹没真正异常。P1 修复后：仅 unexpected=true 触发。
      if (unexpected) {
        _triggerRollbackErrorSnapshot();
      }
    }
  }

  /// 触发 Transaction rollback 的 Error Snapshot。
  void _triggerRollbackErrorSnapshot() {
    final svc = observability;
    if (svc?.isEnabled != true) return;

    svc!.captureError(
      type: 'TransactionRollback',
      message: 'Transaction rolled back unexpectedly (origin=$origin, id=$id)',
      commandName: 'TransactionBuilder',
      commandParams: {
        'transactionId': id.toString(),
        'origin': origin.name,
      },
    );
  }

  @override
  String toString() =>
      'TransactionBuilder(id=$id, origin=$origin, opCount=$opCount, '
      'isNested=$isNested, isCompleted=$isCompleted)';
}
