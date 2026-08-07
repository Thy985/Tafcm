/// CommandHandler：解释 EditorCommand 为 BlockOperation 序列。
///
/// 落地 ADR-0009 §3.3（v1.1 新增）：CommandHandler 是 EditorCommand 与
/// TransactionBuilder 之间的中间层，负责意图分发 + 守卫 + Transaction 生命周期。
///
/// **职责**：
/// 1. 接收 [EditorCommand]（用户意图，纯数据）
/// 2. 守卫检查（composing 态拒绝）
/// 3. 构造 [TransactionBuilder]（含正确的 origin 映射）
/// 4. 创建 [BlockOperations] 执行 BlockOperation（eager apply 到 [DocumentEditor]）
/// 5. 成功 → commit Transaction + push 到 [EditorHistory]
/// 6. 失败 → rollback（清空已收集的 ops）
///
/// **不持有 UI 状态**：CommandHandler 是纯逻辑层，依赖 [DocumentEditor] +
/// [EditorHistory] 两个内核抽象，不依赖任何 Facade/Coordinator（避免循环依赖）。
///
/// **依赖方向**（v1.1 修订，PR 评审 R1）：
/// commands/ → core/editing/（单向依赖，不反向引用 prototype/_shared/）
library;

import '../../core/editing/block_operations.dart';
import '../../core/editing/block_serializer.dart';
import '../../core/editing/document_editor.dart';
import '../../core/editing/edit_operation.dart';
import '../../core/editing/editor_history.dart';
import '../../core/editing/transaction.dart';
import '../../core/editing/transaction_builder.dart';
import '../../core/editing/transaction_rollback.dart';
import '../../core/observability/canonical_fingerprint.dart';
import '../../core/observability/command_replayer.dart';
import '../../core/observability/invariant_checker.dart';
import '../../core/observability/models.dart' as obs;
import '../../core/observability/observability_service.dart';
import '../../data/models/document.dart';
import 'commands.dart';

/// CommandHandler：解释 [EditorCommand] 为 [BlockOperation] 序列。
///
/// 依赖 [DocumentEditor] + [EditorHistory] 两个内核抽象。
/// 由 Facade/Coordinator 持有并注入这两个依赖（避免循环引用）。
class CommandHandler {
  /// 编辑器内核（持有 Document AST + BlockId 分配）。
  final DocumentEditor editor;

  /// Undo / Redo 历史栈。
  final EditorHistory history;

  /// 可观测服务（可选，LIGHT 模式下默认开启）。
  final ObservabilityService? observability;

  CommandHandler({
    required this.editor,
    required this.history,
    this.observability,
  });

  /// 计算当前 Document fingerprint。
  String? _computeFingerprint() {
    if (observability?.isEnabled != true) return null;
    final blocks = editor.allIds
        .map((id) => MapEntry<String, DocumentElement?>(id.value, editor.getBlock(id)))
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, e.value!))
        .toList();
    return canonicalFingerprint(blocks);
  }

  /// 构造编辑器状态快照提供者（用于 Transaction Trace 的 before/after snapshot）。
  ///
  /// 每块取 BlockId 前 8 字符 + source 前 80 字符，拼成可读摘要。
  StateSnapshotProvider _snapshotProvider() {
    return () {
      final buf = StringBuffer();
      for (final id in editor.allIds) {
        final element = editor.getBlock(id);
        if (element == null) continue;
        final source = fromElement(element);
        final shortId = id.value.length > 8 ? id.value.substring(0, 8) : id.value;
        final shortSource = source.length > 80 ? '${source.substring(0, 80)}...' : source;
        buf.writeln('$shortId: $shortSource');
      }
      return buf.toString();
    };
  }

  /// 处理 [command]，返回是否成功。
  ///
  /// 内部流程：
  /// 1. 守卫检查（composing 态拒绝 —— Prototype 阶段不接入 IME，跳过）
  /// 2. 构造 [TransactionBuilder]（origin = command.origin 映射）
  /// 3. 创建 [BlockOperations]（每次 handle 创建新实例，绑定新 builder）
  /// 4. 分发到对应的 _handle* 方法
  /// 5. 成功 → builder.commit()（触发 onChange → history.push）
  /// 6. 失败 → revertBuilder(builder, editor)（原子回滚：逆序 revert 已 eager-apply 的 op）
  /// 7. 异常 → Error Snapshot（ADR-0021 §3.7.2）
  bool handle(EditorCommand command) {
    // Prototype 阶段不接入 ComposingController，守卫跳过
    // Phase 3 正式实现时：if (composing?.isActive == true) return false;

    // === Observability: 记录 before state ===
    final beforeHash = _computeFingerprint();

    final builder = TransactionBuilder(
      origin: _toTransactionOrigin(command.origin),
      onChange: (tx) => history.push(tx),
      observability: observability,
      stateSnapshotProvider: _snapshotProvider(),
    );
    final operations = BlockOperations(editor, builder);

    bool success;
    try {
      success = _dispatch(command, operations, builder);
      if (success) {
        builder.commit(label: command.displayName);
        _runInvariantCheck();
      } else {
        // D3 原子性：BlockOperations 在 op.apply 成功后才加入 builder，
        // 故 builder.ops 均为已 apply 到 editor 的 op。失败须逆序 revert 以恢复
        // 编辑器到命令前状态（避免多原语命令中途失败残留部分变异态）。
        // P1 信噪比修复：成功路径 false（守卫拒绝 / no-op）走良性 rollback，
        // 不触发 ErrorSnapshot。
        revertBuilder(builder, editor);
      }
    } catch (e) {
      // === Observability: 触发 Error Snapshot（ADR-0021 §3.7.2） ===
      _captureCommandError(command, e);
      // 确保 builder 回滚（异常时可能未 complete）
      // P1 信噪比修复：异常路径才是真正的"非预期回滚"，传 unexpected: true
      // 触发 ErrorSnapshot（与 TransactionBuilder.rollback 的 unexpected 参数对齐）。
      if (!builder.isCompleted) {
        revertBuilder(builder, editor, unexpected: true);
      }
      success = false;
    }

    // === Observability: 记录 Command 轨迹 ===
    final afterHash = _computeFingerprint();
    _recordCommandTrace(command, success, beforeHash, afterHash, builder.id);

    return success;
  }

  /// Transaction commit 后运行不变量检查（ADR-0021 §2.7）。
  ///
  /// 检查失败不阻塞编辑器运行，但自动触发 Error Snapshot。
  void _runInvariantCheck() {
    final svc = observability;
    if (svc?.isEnabled != true) return;

    final historyBlockIds = <String>{};
    Transaction? lastTx = history.lastOrNull;
    if (lastTx != null) {
      for (final op in lastTx.ops) {
        if (op is TextOperation) {
          historyBlockIds.add(op.blockId.value);
        }
      }
    }

    final state = editor.allIds
        .map((id) {
          final element = editor.getBlock(id);
          return element != null
              ? EditorInvariantContext(
                  blockId: id.value,
                  element: element,
                  historyBlockIds: historyBlockIds,
                )
              : null;
        })
        .whereType<EditorInvariantContext>()
        .toList();

    final failures = svc!.checkInvariants(state);
    if (failures.isNotEmpty) {
      svc.captureError(
        type: 'InvariantViolation',
        message: 'Invariant check failed: ${failures.map((f) => f.invariantName).join(", ")}',
        commandName: 'InvariantChecker',
      );
    }
  }

  /// 捕获 Command 执行异常并生成 Error Snapshot。
  void _captureCommandError(EditorCommand command, Object error) {
    final svc = observability;
    if (svc?.isEnabled != true) return;

    svc!.captureError(
      type: 'CommandExecutionError',
      message: error.toString(),
      commandName: command.runtimeType.toString(),
      commandParams: {'displayName': command.displayName},
    );
  }

  /// 记录 Command 执行轨迹到 ObservabilityService。
  void _recordCommandTrace(
    EditorCommand command,
    bool success,
    String? beforeHash,
    String? afterHash,
    TransactionId transactionId,
  ) {
    final svc = observability;
    if (svc?.isEnabled != true) return;
    final ctx = svc!.currentContext;

    // 使用 CommandReplayer.serialize 提取完整参数以支持 Replay
    final replayEvent = CommandReplayer.serialize(command);
    final params = replayEvent.params;

    svc.recordCommand(obs.CommandTraceEntry(
      commandName: command.runtimeType.toString(),
      params: params,
      origin: _mapOrigin(command.origin),
      timestamp: DateTime.now(),
      transactionId: transactionId.toString(),
      succeeded: success,
      beforeStateHash: beforeHash,
      afterStateHash: afterHash,
      traceId: ctx?.traceId,
      spanId: ctx?.spanId,
    ));
  }

  obs.CommandOrigin _mapOrigin(CommandOrigin origin) {
    return switch (origin) {
      CommandOrigin.keyboard => obs.CommandOrigin.keyboard,
      CommandOrigin.ime => obs.CommandOrigin.ime,
      CommandOrigin.ai => obs.CommandOrigin.ai,
      CommandOrigin.voice => obs.CommandOrigin.voice,
      CommandOrigin.menu => obs.CommandOrigin.menu,
      CommandOrigin.gesture => obs.CommandOrigin.gesture,
    };
  }

  /// 分发 [command] 到对应处理方法。
  ///
  /// **Phase 3.1-A 修订（R6）**：从 if-else 链改为 switch 表达式。
  /// 配合 [EditorCommand] 的 `sealed class` 声明，编译器强制穷举所有 8 种 Command 子类。
  /// 新增 Command 类型时，编译器立即报错提示添加 case 分支。
  ///
  /// **变量绑定**（`XCommand c`）：让 narrowed 后的具体类型直接传给 `_handleX`，
  /// 避免再写一次 `command is XCommand` 类型检查。
  bool _dispatch(
    EditorCommand command,
    BlockOperations operations,
    TransactionBuilder builder,
  ) {
    return switch (command) {
      SplitBlockCommand c => _handleSplitBlock(c, operations),
      MergeWithPreviousCommand c => _handleMerge(c, operations),
      InsertBlockAfterCommand c => _handleInsert(c, operations),
      DeleteBlockCommand c => _handleDelete(c, operations),
      MoveBlockUpCommand c => _handleMoveUp(c, operations),
      MoveBlockDownCommand c => _handleMoveDown(c, operations),
      MoveBlockCommand c => _handleMove(c, operations),
      UpdateBlockSourceCommand c => _handleUpdateSource(c, operations),
      TransformBlockCommand c => _handleTransform(c, operations),
      // Phase 3.3 PR #2A 新增 3 个分支（Markdown 工具栏 + 模板菜单）
      InsertTextCommand c => _handleInsertText(c, operations),
      WrapSelectionCommand c => _handleWrapSelection(c, operations),
      InsertTemplateCommand c => _handleInsertTemplate(c, operations),
      // Phase 3.3 PR #3 新增 2 个分支（自动配对 + 自动续列表）
      PairInsertCommand c => _handlePairInsert(c, operations),
      InsertNewLineWithPrefixCommand c => _handleNewLineWithPrefix(c, operations),
    };
  }

  /// [CommandOrigin] → [TransactionOrigin] 映射。
  ///
  /// 仅 [keyboard] / [ime] 有特殊语义（参与 Coalescing），
  /// 其他来源统一映射为 [TransactionOrigin.programmatic]。
  TransactionOrigin _toTransactionOrigin(CommandOrigin origin) {
    return switch (origin) {
      CommandOrigin.keyboard => TransactionOrigin.keyboard,
      CommandOrigin.ime => TransactionOrigin.ime,
      CommandOrigin.ai => TransactionOrigin.programmatic,
      CommandOrigin.voice => TransactionOrigin.programmatic,
      CommandOrigin.menu => TransactionOrigin.programmatic,
      CommandOrigin.gesture => TransactionOrigin.programmatic,
    };
  }

  // ============ 各 _handle* 方法 ============

  bool _handleSplitBlock(SplitBlockCommand c, BlockOperations ops) {
    // BlockOperations.split 内部已自动 tryTransform（Phase 2.7）
    return ops.split(c.blockId, c.offset);
  }

  bool _handleMerge(MergeWithPreviousCommand c, BlockOperations ops) {
    final currentIndex = editor.indexOf(c.blockId);
    if (currentIndex <= 0) return false; // 第一块无法合并
    final prevId = editor.allIds[currentIndex - 1];
    return ops.merge(prevId, c.blockId);
  }

  bool _handleInsert(InsertBlockAfterCommand c, BlockOperations ops) {
    final newId = ops.insertAfter(c.blockId, c.element);
    return newId != null;
  }

  bool _handleDelete(DeleteBlockCommand c, BlockOperations ops) {
    return ops.delete(c.blockId);
  }

  bool _handleMoveUp(MoveBlockUpCommand c, BlockOperations ops) {
    final currentIndex = editor.indexOf(c.blockId);
    if (currentIndex <= 0) return false;
    final prevId = editor.allIds[currentIndex - 1];
    return ops.move(c.blockId, prevId, before: true);
  }

  bool _handleMoveDown(MoveBlockDownCommand c, BlockOperations ops) {
    final currentIndex = editor.indexOf(c.blockId);
    if (currentIndex + 1 >= editor.blockCount) return false;
    final nextId = editor.allIds[currentIndex + 1];
    return ops.move(c.blockId, nextId, before: false);
  }

  bool _handleMove(MoveBlockCommand c, BlockOperations ops) {
    return ops.move(c.targetId, c.refId, before: c.before);
  }

  bool _handleUpdateSource(UpdateBlockSourceCommand c, BlockOperations ops) {
    return ops.updateSource(c.blockId, c.newSource);
  }

  bool _handleTransform(TransformBlockCommand c, BlockOperations ops) {
    return ops.tryTransform(c.blockId);
  }

  // ============ Phase 3.3 PR #2A 新增 _handle* 方法 ============
  //
  // 落地 Task Contract v2.1 §4.3.2 + ADR-0011 §5。
  //
  // 设计要点：
  // - 复用 [BlockOperations.updateSource]（通过完整 source 替换）
  // - selection 由 Command 字段携带（方案 A，见 v2.1 §2.4）
  // - newBlock 模式复用 [BlockOperations.insertAfter] + ParagraphElement

  /// 处理 [InsertTextCommand]：在光标位置插入文本。
  ///
  /// 计算逻辑：
  /// 1. 读取当前 source + selection
  /// 2. 在 selection.baseOffset（或末尾）处插入 [text]
  /// 3. 调用 [BlockOperations.updateSource] 替换完整 source
  ///
  /// **光标位置不在此方法处理**：光标位置由 Toolbar / EditorCoordinator
  /// 在 Command 执行后根据 [InsertTextCommand.cursorOffset] 调整
  /// （CommandHandler 仅修改数据，不操作 UI 焦点）。
  bool _handleInsertText(InsertTextCommand c, BlockOperations ops) {
    final element = editor.getBlock(c.blockId);
    if (element == null) return false;

    final source = fromElement(element);
    final insertOffset = c.selection?.baseOffset ?? source.length;

    // 越界保护
    if (insertOffset < 0 || insertOffset > source.length) return false;

    final newSource =
        source.substring(0, insertOffset) + c.text + source.substring(insertOffset);
    return ops.updateSource(c.blockId, newSource);
  }

  /// 处理 [WrapSelectionCommand]：选区包裹为 `prefix + selection + suffix`。
  ///
  /// 计算逻辑：
  /// 1. 读取当前 source + selection
  /// 2. 选区文本 = source[selection.start..selection.end]
  /// 3. newSource = source[..start] + prefix + selected + suffix + source[end..]
  /// 4. 调用 [BlockOperations.updateSource] 替换完整 source
  bool _handleWrapSelection(WrapSelectionCommand c, BlockOperations ops) {
    final element = editor.getBlock(c.blockId);
    if (element == null) return false;

    final source = fromElement(element);
    final start = c.selection.start;
    final end = c.selection.end;

    // 越界保护
    if (start < 0 || end > source.length || start > end) return false;

    final selected = source.substring(start, end);
    final newSource = source.substring(0, start) +
        c.prefix +
        selected +
        c.suffix +
        source.substring(end);
    return ops.updateSource(c.blockId, newSource);
  }

  /// 处理 [InsertTemplateCommand]：插入模板（表格 / Mermaid / 代码块等）。
  ///
  /// - [TemplateInsertMode.insert]：在光标位置插入模板文本（复用 [_handleInsertText]）
  /// - [TemplateInsertMode.newBlock]：在当前块后插入新 ParagraphElement
  ///
  /// **newBlock 模式**：模板作为单一 ParagraphElement 插入，由
  /// [BlockOperations.updateSource] 的 transform 机制（Phase 2.7）自动
  /// 转换为对应 BlockType（如表格模板 → TableBlock）。
  bool _handleInsertTemplate(InsertTemplateCommand c, BlockOperations ops) {
    switch (c.mode) {
      case TemplateInsertMode.insert:
        // 复用 InsertText 逻辑：在光标位置插入模板文本
        return _handleInsertText(
          InsertTextCommand(
            blockId: c.blockId,
            text: c.template,
            selection: c.selection,
          ),
          ops,
        );
      case TemplateInsertMode.newBlock:
        // 新建块：模板作为 ParagraphElement 插入，由 tryTransform 自动转换 BlockType
        final newId = ops.insertAfter(
          c.blockId,
          ParagraphElement(children: [TextElement(c.template)]),
        );
        if (newId != null) {
          // Phase 2.7：自动转换（表格→TableBlock / Mermaid→MermaidBlock / 任务列表→TaskListItem…）
          // 修复：原 insertAfter 不触发 transform，导致 newBlock 模板停留在 ParagraphElement。
          ops.tryTransform(newId);
        }
        return newId != null;
    }
  }

  // ============ Phase 3.3 PR #3 新增 _handle* 方法 ============
  //
  // 落地 Task Contract v1.1 §3.3 + ADR-0011 §5。
  //
  // 设计要点（v1.1 Human Owner 审批）：
  // - PairInsertCommand：基于 insertOffset，不通过 selection 推断 cursor
  // - InsertNewLineWithPrefixCommand：Handler 读取 source，Command 不携带 State

  /// 处理 [PairInsertCommand]（v1.1：基于 insertOffset，不推断 cursor）。
  ///
  /// 两种模式都是追加 [PairInsertCommand.suffixChar] 到 [insertOffset] 位置：
  /// - appendAfterCursor：insertOffset = 光标位置（'(' 之后）
  /// - wrapSelection：insertOffset = 选区末尾（selection.end）
  bool _handlePairInsert(PairInsertCommand c, BlockOperations ops) {
    final element = editor.getBlock(c.blockId);
    if (element == null) return false;
    final source = fromElement(element);

    // v1.1：直接使用 c.insertOffset，不通过 selection 推断
    if (c.insertOffset < 0 || c.insertOffset > source.length) return false;

    final newSource = source.substring(0, c.insertOffset) +
        c.suffixChar +
        source.substring(c.insertOffset);
    return ops.updateSource(c.blockId, newSource);
  }

  /// 处理 [InsertNewLineWithPrefixCommand]（v1.1：Handler 读取 source）。
  ///
  /// - isExit = false：在 source 末尾追加 [prefix]
  /// - isExit = true：清除当前行（最后一行）的列表前缀
  bool _handleNewLineWithPrefix(
      InsertNewLineWithPrefixCommand c, BlockOperations ops) {
    final element = editor.getBlock(c.blockId);
    if (element == null) return false;
    final source = fromElement(element); // v1.1：Handler 读取 source

    if (c.isExit) {
      // 退出续行：清除最后一行的前缀
      // source 形如 "- \n"（'\n' 由 IME 提交），移除最后的空列表项前缀
      final lastNewline = source.lastIndexOf('\n');
      final lastLineStart = lastNewline == -1 ? 0 : lastNewline + 1;
      final lastLine = source.substring(lastLineStart);
      // 若最后一行恰好是 prefix（无内容），移除它
      if (lastLine == c.prefix) {
        final newSource = source.substring(0, lastLineStart);
        return ops.updateSource(c.blockId, newSource);
      }
      return false;
    }

    // 续行：在 source 末尾追加 prefix
    final newSource = source + c.prefix;
    return ops.updateSource(c.blockId, newSource);
  }
}
