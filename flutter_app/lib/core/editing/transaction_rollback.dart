/// D3 原子性 helper：逆序 revert builder 中已 apply 的 op，恢复 editor 到命令前状态，然后丢弃 ops。
///
/// 落地 ADR-0020 D3：「Transaction 不要求延迟执行，eager apply 允许；
/// 但失败时须可 revert 原子恢复」。
///
/// 设计取舍（与 [TransactionBuilder] 职责单一一致）：
/// - [TransactionBuilder.rollback] 仅清空已收集的 ops，**不耦合** [DocumentEditor]
///   （保持 builder 可被 UI/测试灵活组合，不反向依赖内核）。
/// - 本函数负责把已 apply 的 op **逆向恢复**：调用方（[CommandHandler]）同时持有
///   editor 与 builder，是唯一的 Transaction 入口（TC-ARCH-MODEL-3），故原子回滚责任在此。
///
/// 逆序 revert 保证多 op 事务的部分失败可精确恢复
/// （如 split + 自动 transform 中途失败 → 先 revert transform 再 revert split）。
///
/// 约定：[BlockOperations] 仅在 op.apply 成功后才把 op 加入 builder，
/// 故 [TransactionBuilder.ops] 中的 op 均已成功 apply 到同一 editor，逆序 revert 安全。
library;

import 'document_editor.dart';
import 'transaction_builder.dart';

/// 原子回滚一个 [TransactionBuilder]：逆序 revert 已 apply 的 op，再清空 ops。
///
/// [builder] 必须尚未 commit/rollback（否则 [TransactionBuilder.rollback] 抛 [StateError]）。
void revertBuilder(TransactionBuilder builder, DocumentEditor editor) {
  // 逆序：先撤销最后 apply 的 op，再撤销更早的 op，确保依赖顺序正确
  for (final op in builder.ops.reversed) {
    op.revert(editor);
  }
  builder.rollback();
}
