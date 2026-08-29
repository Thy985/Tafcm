/// undo-redo 行为 fuzz（Phase 3.9 Batch 5，CAP-010 深化）。
///
/// 审计目标：随机 BlockOperation 序列（insert/delete/merge/split）经
/// apply → undo 全部 → redo 全部 后，editor 状态必须回到初始/最终
/// （undo 幂等 + redo 恢复一致性，无状态污染）。
///
/// 固定 seed 可复现；发现不一致即 fail（与 roundtrip fuzz 同策略）。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_operations.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/core/editing/transaction.dart';
import 'package:tafcm/core/editing/transaction_builder.dart';
import 'package:tafcm/data/models/document.dart';

import 'helpers/mock_document_editor.dart';

/// 随机操作序列生成器（固定 seed 可复现）。
class UndoRedoFuzzGenerator {
  UndoRedoFuzzGenerator([int seed = 20260818]) : _rng = Random(seed);

  final Random _rng;

  static const _texts = ['a', 'b', 'c', '中文', 'x y', '1'];

  String _pickText() => _texts[_rng.nextInt(_texts.length)];

  /// 生成随机操作命令序列（最多 [maxOps] 步）。
  ///
  /// 返回闭包列表：每个闭包接收 (ops, editor) 执行一步操作，
  /// 并返回 true=成功 / false=被拒绝（如 delete 最后一块）。
  List<bool Function(BlockOperations ops, MockDocumentEditor editor)> generate(
    int maxOps,
  ) {
    final commands = <bool Function(BlockOperations, MockDocumentEditor)>[];
    for (var i = 0; i < maxOps; i++) {
      commands.add(_nextCommand());
    }
    return commands;
  }

  bool Function(BlockOperations, MockDocumentEditor) _nextCommand() {
    final r = _rng.nextDouble();
    if (r < 0.4) {
      // insertAfter：随机插到某块后
      return (ops, editor) {
        final ids = editor.allIds;
        if (ids.isEmpty) return false;
        final target = ids[_rng.nextInt(ids.length)];
        final el = ParagraphElement(children: [TextElement(_pickText())]);
        final id = ops.insertAfter(target, el);
        return id != null;
      };
    } else if (r < 0.7) {
      // delete：随机删一块（需 blockCount > 1）
      return (ops, editor) {
        final ids = editor.allIds;
        if (ids.length <= 1) return false;
        final target = ids[_rng.nextInt(ids.length)];
        return ops.delete(target);
      };
    } else if (r < 0.85) {
      // merge：随机合并相邻两块（left/right 必须相邻且不同，
      // 否则 merge 同一块导致 BlockId not found）
      return (ops, editor) {
        final ids = editor.allIds;
        if (ids.length <= 1) return false;
        final li = _rng.nextInt(ids.length - 1);
        return ops.merge(ids[li], ids[li + 1]);
      };
    } else {
      // split：随机在 offset 处拆分
      return (ops, editor) {
        final ids = editor.allIds;
        if (ids.isEmpty) return false;
        final target = ids[_rng.nextInt(ids.length)];
        final source = editor.sourceOf(target);
        if (source.isEmpty) return false;
        final offset = 1 + _rng.nextInt(source.length);
        return ops.split(target, offset);
      };
    }
  }
}

void main() {
  group('CAP-010 undo-redo 行为 fuzz', () {
    test('随机操作序列：undo 全部回初始 + redo 全部回最终', () {
      const maxOps = 40;
      final gen = UndoRedoFuzzGenerator();
      final commands = gen.generate(maxOps);

      final editor = MockDocumentEditor();
      editor.addParagraph('seed0');
      final initialSources = editor.allSources.toList();
      final history = EditorHistory();

      // 1. apply 随机操作序列（每步新建 builder —— builder 一旦
      // commit 即 completed，不能跨步复用）
      final txs = <Transaction>[];
      for (var step = 0; step < commands.length; step++) {
        final builder = TransactionBuilder(
          origin: TransactionOrigin.programmatic,
          onChange: (tx) => history.push(tx),
        );
        final ops = BlockOperations(editor, builder);
        final accepted = commands[step](ops, editor);
        final tx = builder.commit();
        if (tx.ops.isNotEmpty) {
          txs.add(tx);
        }
        if (!accepted) {
          // 操作被拒绝（如 delete 最后一块）——不产生 tx，继续
          continue;
        }
      }
      final finalSources = editor.allSources.toList();

      // 2. undo 全部 → 应回初始状态
      for (var i = txs.length - 1; i >= 0; i--) {
        final undone = history.undo(txs[i]);
        if (undone == null) break; // 超过栈深度（边界允许）
        for (final op in undone.ops.reversed) {
          op.revert(editor);
        }
      }
      expect(editor.allSources, equals(initialSources),
          reason: 'undo 全部后应回初始状态');

      // 3. redo 全部 → 应回最终状态
      for (var i = 0; i < txs.length; i++) {
        final redone = history.redo(txs[i]);
        if (redone == null) break;
        for (final op in redone.ops) {
          op.apply(editor);
        }
      }
      expect(editor.allSources, equals(finalSources),
          reason: 'redo 全部后应回最终状态');

      // 4. 再 undo 一轮 → 仍回初始（幂等）
      for (var i = txs.length - 1; i >= 0; i--) {
        final undone = history.undo(txs[i]);
        if (undone == null) break;
        for (final op in undone.ops.reversed) {
          op.revert(editor);
        }
      }
      expect(editor.allSources, equals(initialSources),
          reason: '二次 undo 后仍回初始（幂等）');
    });

    test('多 seed 扫描（5 seed × 40 步）', () {
      for (final s in [1, 42, 20260818, 9999, 314159]) {
        final gen = UndoRedoFuzzGenerator(s);
        final commands = gen.generate(40);
        final editor = MockDocumentEditor();
        editor.addParagraph('seed0');
        final initialSources = editor.allSources.toList();
        final history = EditorHistory();
        final txs = <Transaction>[];
        for (final cmd in commands) {
          final builder = TransactionBuilder(
            origin: TransactionOrigin.programmatic,
            onChange: (tx) => history.push(tx),
          );
          final ops = BlockOperations(editor, builder);
          cmd(ops, editor);
          final tx = builder.commit();
          if (tx.ops.isNotEmpty) txs.add(tx);
        }
        final finalSources = editor.allSources.toList();
        for (var i = txs.length - 1; i >= 0; i--) {
          final undone = history.undo(txs[i]);
          if (undone == null) break;
          for (final op in undone.ops.reversed) {
            op.revert(editor);
          }
        }
        expect(editor.allSources, equals(initialSources),
            reason: 'seed=$s undo 后应回初始');
        for (var i = 0; i < txs.length; i++) {
          final redone = history.redo(txs[i]);
          if (redone == null) break;
          for (final op in redone.ops) {
            op.apply(editor);
          }
        }
        expect(editor.allSources, equals(finalSources),
            reason: 'seed=$s redo 后应回最终');
      }
    });
  });
}
