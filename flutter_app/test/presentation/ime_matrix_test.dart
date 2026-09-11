/// U2 IME 组合测试矩阵（TEST-SYSTEM-UPGRADE-PLAN §3.2）。
///
/// 参照 SoloMD IME dogfooding 教训：IME 组合键守卫必须覆盖**多输入法场景**
/// （拼音 / 假名 / Hangul），而非单一 composing 用例。本矩阵把
/// `{IME 场景} × {块级 mutation / commit / cancel / 自动续行}` 参数化，
/// 全部纯 Dart 确定性运行（无真机 / 无字体依赖）。
///
/// 与既有测试的分工：
/// - `editing/ime_mutation_forbidden_test.dart`（TC-EDIT-6.9）：单 op 守门细节
/// - `editing/ime_transaction_integration_test.dart`（TC-EDIT-8.3）：Transaction
///   origin 标记 / coalescing 隔离
/// - **本测试**：跨输入法场景的矩阵化回归守门（ locale 维度是新增的）
///
/// 契约提醒（§2.1.1 Hard Rule）：[AutoContinueRules] / [AutoPairRules] 本身
/// 不检查 composing——由调用方（BaseBlockState._onTextChanged）保证仅在
/// `composing == TextRange.empty` 时调用。矩阵 Group 4 验证 commit 完成后
/// 规则立即恢复正常 firing（commit → enter 续行的真实组合流）。
library;

import 'package:flutter/widgets.dart' show TextEditingValue, TextSelection;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/block_operations.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/core/editing/composing_controller.dart';
import 'package:tafcm/core/editing/composing_state.dart';
import 'package:tafcm/core/editing/transaction.dart';
import 'package:tafcm/core/editing/transaction_builder.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/blocks/input/auto_continue_rules.dart';
import 'package:tafcm/presentation/blocks/input/auto_pair_rules.dart';

import '../editing/helpers/mock_composing_host.dart';
import '../editing/helpers/mock_document_editor.dart';

/// IME 输入法场景：composing 中间态文本 → 用户最终提交文本。
///
/// 三类覆盖东亚主流输入法的 composing 语义（中间态为拉丁转写或组字中，
/// 提交态为 CJK 字符）——正是 SoloMD dogfooding 抓到 Enter 误触发 bug 的场景族。
enum _ImeLocale {
  pinyin('拼音', 'nihao', '你好'),
  kana('假名', 'konnitiha', 'こんにちは'),
  hangul('谚文', 'annyeong', '안녕');

  const _ImeLocale(this.label, this.composingText, this.committedText);
  final String label;
  final String composingText;
  final String committedText;
}

/// 构造一个带 2 段的编辑器 + 处于 composing 态的 BlockOperations。
({MockDocumentEditor editor, MockComposingHost host, ComposingController
    composing, BlockId aId, BlockId bId, BlockOperations ops}) _makeCtx({
  _ImeLocale locale = _ImeLocale.pinyin,
}) {
  final editor = MockDocumentEditor();
  final aId = editor.addParagraph('hello');
  final bId = editor.addParagraph('world');

  final host = MockComposingHost(
    source: locale.composingText,
    composing: ComposingRegion(start: 0, end: locale.composingText.length),
  );
  final composing = ComposingController(host);
  composing.onComposingStart();

  final builder = TransactionBuilder(origin: TransactionOrigin.programmatic);
  final ops = BlockOperations(editor, builder, composing);
  return (
    editor: editor,
    host: host,
    composing: composing,
    aId: aId,
    bId: bId,
    ops: ops,
  );
}

void main() {
  group('U2-1 守门矩阵：composing 态 × 7 类块级 mutation × 3 输入法', () {
    test('全部 locale × 全部 mutation 在 composing 态被拒', () {
      final rejected = <String>[];
      final leaked = <String>[];

      for (final locale in _ImeLocale.values) {
        final cases = <(String, void Function())>[];
        late MockDocumentEditor editor;
        late BlockId aId;
        late BlockId bId;
        late BlockOperations ops;

        // 每个 mutation 用独立 ctx，避免 op 副作用互相污染判定。
        (String, void Function()) makeCase(
            String name, void Function(BlockOperations, MockDocumentEditor, BlockId, BlockId) run) {
          return (name, () {
            final ctx = _makeCtx(locale: locale);
            editor = ctx.editor;
            aId = ctx.aId;
            bId = ctx.bId;
            ops = ctx.ops;
            run(ops, editor, aId, bId);
          });
        }

        cases.add(makeCase('insertAfter',
            (o, e, a, b) => o.insertAfter(a, const ParagraphElement(children: [TextElement('x')]))));
        cases.add(makeCase('delete', (o, e, a, b) => o.delete(a)));
        cases.add(makeCase('merge', (o, e, a, b) => o.merge(a, b)));
        cases.add(makeCase('split', (o, e, a, b) => o.split(a, 2)));
        cases.add(makeCase('move', (o, e, a, b) => o.move(b, a)));
        cases.add(makeCase('tryTransform', (o, e, a, b) => o.tryTransform(a)));
        cases.add(makeCase('updateSource', (o, e, a, b) => o.updateSource(a, 'edited')));

        for (final (name, run) in cases) {
          try {
            run();
            leaked.add('${locale.label}/$name');
          } on StateError {
            rejected.add('${locale.label}/$name');
          }
        }
      }

      // 3 locale × 7 mutation = 21 全部必须被守门拦截。
      expect(leaked, isEmpty,
          reason: 'composing 态泄漏的块级 mutation：$leaked');
      expect(rejected.length, 21);
    });

    test('全部 locale 下 composing 态守门不影响 editor 状态（无半写）', () {
      for (final locale in _ImeLocale.values) {
        final ctx = _makeCtx(locale: locale);
        try {
          ctx.ops.split(ctx.aId, 2);
        } on StateError {
          // 预期路径
        }
        expect(ctx.editor.blockCount, 2,
            reason: '${locale.label}：被拒的 op 不得产生半写状态');
        expect(ctx.composing.isActive, isTrue);
      }
    });
  });

  group('U2-2 commit 矩阵：3 输入法 × 3 块类型 source（铁律 2 不丢字）', () {
    const sources = <String, String>{
      'paragraph': 'hello ',
      'list': '- item ',
      'heading': '## Title ',
    };

    test('commit 把 composing region 替换为提交文本，原内容无丢失', () {
      for (final locale in _ImeLocale.values) {
        for (final entry in sources.entries) {
          final host = MockComposingHost(
            source: '${entry.value}${locale.composingText}',
            composing: ComposingRegion(
              start: entry.value.length,
              end: entry.value.length + locale.composingText.length,
            ),
          );
          final composing = ComposingController(host);
          composing.onComposingStart();
          composing.onComposingCommit(locale.committedText);

          expect(composing.state, ComposingState.idle,
              reason: '${locale.label}/${entry.key}：commit 后应回到 idle');
          expect(host.source, '${entry.value}${locale.committedText}',
              reason: '${locale.label}/${entry.key}：commit 后 source 不丢字');
          expect(host.source.contains(locale.composingText), isFalse,
              reason: '${locale.label}/${entry.key}：拉丁中间态必须被替换');
        }
      }
    });
  });

  group('U2-3 cancel 矩阵：3 输入法（铁律 3 回滚）', () {
    test('cancel 恢复 composing 前的 source', () {
      for (final locale in _ImeLocale.values) {
        final original = 'keep ${locale.composingText} me';
        final host = MockComposingHost(
          source: original,
          composing: const ComposingRegion(start: 5, end: 11),
        );
        final composing = ComposingController(host);
        composing.onComposingStart();

        // 模拟组字过程中 host 内联变化（真实 IME 行为）。
        host.source = 'keep ${locale.composingText.toUpperCase()} me';
        composing.onComposingUpdate();

        composing.onComposingCancel();
        expect(composing.state, ComposingState.idle);
        expect(host.source, original,
            reason: '${locale.label}：cancel 必须回滚到组字前 source');
      }
    });
  });

  group('U2-4 commit → 续行/配对组合流（§10 A1 的确定性断言面）', () {
    test('commit 完成后 Enter 触发续行（3 输入法 × 列表/引用/任务）', () {
      final prefixes = <String, String>{
        'list': '- ',
        'quote': '> ',
        'task': '- [ ] ',
      };
      for (final locale in _ImeLocale.values) {
        for (final p in prefixes.entries) {
          // commit 后的块 source：前缀 + 提交文本 + 用户回车。
          final text = '${p.value}${locale.committedText}\n';
          final cmd = AutoContinueRules.detect(
            newValue: TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            ),
            blockId: const BlockId('matrix'),
          );
          expect(cmd, isNotNull,
              reason: '${locale.label}/${p.key}：commit 后回车必须续行');
          expect(cmd!.isExit, isFalse);
        }
      }
    });

    test('commit 后块尾输入配对符触发自动配对（3 输入法）', () {
      for (final locale in _ImeLocale.values) {
        final text = 'see ${locale.committedText}(';
        final cmd = AutoPairRules.detect(
          newValue: TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
          oldValue: TextEditingValue(
            text: 'see ${locale.committedText}',
            selection:
                TextSelection.collapsed(offset: 'see ${locale.committedText}'.length),
          ),
          blockId: const BlockId('matrix'),
        );
        expect(cmd, isNotNull,
            reason: '${locale.label}：CJK 提交文本后的配对符必须正常配对');
        expect(cmd!.suffixChar, ')');
      }
    });

    test('空列表项回车 = 退出续行（三前缀 × 抽样 locale）', () {
      for (final prefix in ['- ', '> ', '- [ ] ']) {
        final cmd = AutoContinueRules.detect(
          newValue: TextEditingValue(
            text: '$prefix\n',
            selection: TextSelection.collapsed(offset: '$prefix\n'.length),
          ),
          blockId: const BlockId('matrix'),
        );
        expect(cmd, isNotNull);
        expect(cmd!.isExit, isTrue, reason: '空项回车应退出而非续行');
      }
    });
  });
}
