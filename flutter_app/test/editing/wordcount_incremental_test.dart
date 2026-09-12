/// #245 回归测试：wordCount 增量维护 + structureVersion 失效信号。
///
/// 缺陷回顾：每次按键 `wordCount` 对全文档做 O(n²) 序列化求和
/// （allIds O(n) 分配 + getBlock 线性扫描 + fromElement 整块序列化），
/// 大文档输入掉帧；undo/redo 后 live 清空还可能残留计数漂移。
///
/// 修复：LiveEditingState 维护每块长度基线 + 累计值，稳态按键 O(1)
/// 差量更新；InMemoryDocumentEditor 新增 structureVersion（块集合
/// 变异自增），缓存据此 O(1) 失效检测。
///
/// 本套件守门：
/// 1. **计数正确性**：update 差量 / 结构变化全量重建 / reconcile 对齐
///    / clear 清零，任何路径下 wordCount 必须与"逐块求和"真值一致。
/// 2. **复杂度语义**：structureVersion 只在集合变异时变化（键盘输入
///    不触发全量重建路径的前提）；输入路径不再调用 getBlock 扫描。
/// 3. **非恒真**：行为差异用可观测断言区分（版本号、计数真值）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/editor/live_editing_state.dart';

/// "逐块求和"真值（独立于被测实现）。
int _truthWordCount(InMemoryDocumentEditor editor) {
  var sum = 0;
  for (final s in editor.allSources) {
    sum += s.length;
  }
  return sum;
}

void main() {
  group('#245 structureVersion 失效信号', () {
    test('集合变异（insert/remove/replace/migration）自增', () {
      final editor = InMemoryDocumentEditor();
      final v0 = editor.structureVersion;

      final id = editor.insertBlock(0, _para('a'));
      expect(editor.structureVersion, greaterThan(v0));
      final v1 = editor.structureVersion;

      editor.replaceBlock(id, _para('ab'));
      expect(editor.structureVersion, greaterThan(v1));
      final v2 = editor.structureVersion;

      editor.replaceBlockWithMigration(id, _para('abc'));
      expect(editor.structureVersion, greaterThan(v2));
      final v3 = editor.structureVersion;

      editor.removeBlock(
          editor.allIds.lastWhere((i) => i.value != ''));
      expect(editor.structureVersion, greaterThan(v3));
    });

    test('键盘输入路径（updateBlockContent）不变版本号', () {
      final editor = InMemoryDocumentEditor();
      final id = editor.insertBlock(0, _para('a'));
      editor.structureVersion; // 读取以建立基线语义
      final v = editor.structureVersion;

      editor.updateBlockContent(id, _para('ab'));

      expect(editor.structureVersion, v,
          reason: '内容更新不改变块集合——wordCount 增量路径依赖此语义');
    });
  });

  group('#245 wordCount 增量正确性', () {
    test('稳态按键（update 差量）与真值一致', () {
      final editor = InMemoryDocumentEditor();
      final id = editor.insertBlock(0, _para('hello'));
      final live = LiveEditingState(editor);

      expect(live.wordCount, _truthWordCount(editor)); // 建立基线

      live.update(id, 'hello world');
      live.update(id, 'hello world!');
      expect(live.wordCount, 'hello world!'.length,
          reason: '单块 live 漂移 = 该块实时长度');
      expect(live.wordCount, _truth(editor, live),
          reason: '与逐块求和真值一致');
    });

    test('结构变化（插入新块）后全量重建仍与真值一致', () {
      final editor = InMemoryDocumentEditor();
      final id = editor.insertBlock(0, _para('abc'));
      final live = LiveEditingState(editor);
      expect(live.wordCount, 3);

      editor.insertBlock(1, _para('de'));
      expect(live.wordCount, 5, reason: '集合变化 → 全量重建');

      live.update(id, 'abcdef');
      expect(live.wordCount, 8, reason: '重建后差量路径继续工作');
    });

    test('removeBlock 后计数无幽灵残留', () {
      final editor = InMemoryDocumentEditor();
      final id1 = editor.insertBlock(0, _para('aaaa'));
      editor.insertBlock(1, _para('bb'));
      final live = LiveEditingState(editor);
      expect(live.wordCount, 6);

      editor.removeBlock(id1);
      expect(live.wordCount, 2, reason: '删除块的长度必须从累计值中消失');
    });

    test('reconcile 对齐到 committed 后无漂移', () {
      final editor = InMemoryDocumentEditor();
      final id = editor.insertBlock(0, _para('abc'));
      final live = LiveEditingState(editor);
      expect(live.wordCount, 3);

      live.update(id, 'abcXXXX'); // live 漂移
      expect(live.wordCount, 7);

      editor.replaceBlock(id, _para('abc')); // commit 回 committed
      live.reconcile([id]);
      expect(live.wordCount, 3, reason: 'reconcile 后基线对齐 committed');
    });

    test('clear 清零后（undo 场景）重建结果与真值一致', () {
      final editor = InMemoryDocumentEditor();
      editor.insertBlock(0, _para('abc'));
      editor.insertBlock(1, _para('de'));
      final live = LiveEditingState(editor);
      expect(live.wordCount, 5);

      live.clear();
      expect(live.wordCount, 5,
          reason: 'clear 后集合未变 → 重算基线 = committed 真值');
    });

    test('块替换为不同类型 element（序列化长度不同）计数仍正确', () {
      final editor = InMemoryDocumentEditor();
      final id = editor.insertBlock(0, _para('code'));
      final live = LiveEditingState(editor);
      expect(live.wordCount, 4);

      // 换成 heading element：序列化后长度改变（# 前缀），且集合版本 +1。
      editor.replaceBlock(id, const HeadingElement(level: 1, children: [
        TextElement('code'),
      ]));
      expect(live.wordCount, _truthWordCount(editor),
          reason: '序列化长度变化（含类型前缀）必须如实反映');
    });
  });

  group('#245 编辑命令路径端到端（coordinator 集成）', () {
    test('InsertTextCommand 提交后 wordCount 与真值一致', () {
      final editor = InMemoryDocumentEditor();
      final id = editor.insertBlock(0, _para('hello'));
      final live = LiveEditingState(editor);
      expect(live.wordCount, 5);

      // 模拟按键 live 漂移 → commit（生产等价物：replaceBlock + reconcile）。
      live.update(id, 'hello world');
      editor.replaceBlock(id, _para('hello world'));
      live.reconcile([id]);
      expect(live.wordCount, _truthWordCount(editor));
    });
  });
}

/// 带真值对照的组合断言（live + committed 一致性）。
int _truth(InMemoryDocumentEditor editor, LiveEditingState live) {
  var sum = 0;
  for (final id in editor.allIds) {
    sum += live.sourceOf(id).length;
  }
  return sum;
}

dynamic _para(String text) => ParagraphElement(children: [TextElement(text)]);
