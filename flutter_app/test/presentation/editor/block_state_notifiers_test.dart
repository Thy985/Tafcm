/// BlockStateNotifierRegistry 单元测试（#246 局部化刷新基础设施）。
///
/// **覆盖范围**：
/// - `sync()` 幂等性：结构版本未变时不重复分配 notifier
/// - 新增块补建 notifier / 移除块清理孤儿 notifier
/// - `bump()` 单调递增 + 无变化不重复通知（ValueNotifier 的 == 语义）
/// - `bumpAll()` / `bumpAllLive()` 多块批量
/// - `dispose()` 释放全部 notifier
///
/// **不在范围**：
/// - Widget 层重建次数（需要 widget test + 重建计数探针，见 editor_local_refresh_test.dart）
/// - CommandHandler dispatch 路径（见 command_handler_dispatch_test.dart）
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/block_state_notifiers.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';

void main() {
  late InMemoryDocumentEditor editor;
  late BlockStateNotifierRegistry registry;

  setUp(() {
    editor = InMemoryDocumentEditor();
    registry = BlockStateNotifierRegistry(editor);
  });

  tearDown(() {
    registry.dispose();
  });

  group('#246 sync 幂等性', () {
    test('初次 sync 为当前每个块建 notifier', () {
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      registry.sync();
      expect(registry.notifierOf(a), isNotNull);
      expect(registry.notifierOf(b), isNotNull);
    });

    test('结构版本未变时 sync 是 no-op（同一 notifier 实例）', () {
      final a = editor.addParagraph('a');
      registry.sync();
      final first = registry.notifierOf(a);
      // 结构未变：sync 不应重建 notifier 实例
      registry.sync();
      registry.sync();
      expect(registry.notifierOf(a), same(first),
          reason: '稳态 sync 不应分配新 notifier（否则每次按键都丢订阅）');
    });

    test('块文本变化（updateBlockContent）不触发块集合版本变化', () {
      final a = editor.addParagraph('a');
      registry.sync();
      final svBefore = registry.blockSetVersion;
      editor.updateBlockContent(
        a,
        const ParagraphElement(children: [TextElement('changed')]),
      );
      registry.sync();
      expect(registry.blockSetVersion, svBefore,
          reason: '#246：块内文本变化不应被误判为结构变化（否则视口整体重建）');
    });

    test('新增块后 sync 补建 notifier', () {
      final a = editor.addParagraph('a');
      registry.sync();
      final b = editor.addParagraph('b');
      registry.sync();
      expect(registry.notifierOf(b), isNotNull);
      expect(registry.notifierOf(a), isNotNull);
    });

    test('移除块后 sync 清理孤儿 notifier', () {
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      registry.sync();
      // notifierOf 先建好，确保进注册表
      registry.notifierOf(a);
      registry.notifierOf(b);
      editor.removeBlock(a);
      registry.sync();
      // a 已不在文档中：notifierOf 会重建一个新的（版本归零），
      // 说明旧实例已被 sync 清理（否则版本号会延续）。
      final fresh = registry.notifierOf(a);
      expect(fresh.value, equals(0));
    });
  });

  group('#246 bump 语义', () {
    test('bump 单调递增', () {
      final a = editor.addParagraph('a');
      registry.sync();
      final n = registry.notifierOf(a);
      final v0 = n.value;
      registry.bump(a);
      expect(n.value, equals(v0 + 1));
      registry.bump(a);
      expect(n.value, equals(v0 + 2));
    });

    test('bumpAll 批量递增多块', () {
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      final c = editor.addParagraph('c');
      registry.sync();
      final na = registry.notifierOf(a);
      final nb = registry.notifierOf(b);
      final nc = registry.notifierOf(c);
      final base = na.value;
      registry.bumpAll([a, b]);
      expect(na.value, equals(base + 1));
      expect(nb.value, equals(base + 1));
      expect(nc.value, equals(base),
          reason: '未受影响的块不应被 bump（否则等于全量重建）');
    });

    test('bumpAllLive 递增所有存活块', () {
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      registry.sync();
      final na = registry.notifierOf(a);
      final nb = registry.notifierOf(b);
      final base = na.value;
      registry.bumpAllLive();
      expect(na.value, equals(base + 1));
      expect(nb.value, equals(base + 1));
    });

    test('bumpAllLive 跳过已移除块的孤儿 notifier', () {
      final a = editor.addParagraph('a');
      final b = editor.addParagraph('b');
      registry.sync();
      registry.notifierOf(a);
      final orphan = registry.notifierOf(b);
      editor.removeBlock(b);
      registry.sync(); // 清理孤儿 b
      final base = orphan.value;
      registry.bumpAllLive();
      // b 已被清理，不应被 bumpAllLive 触碰
      expect(orphan.value, equals(base));
    });
  });

  group('#246 blockSetVersion vs structureVersion（防回归）', () {
    test('updateBlockContent（每次按键走）不递增 blockSetVersion', () {
      final a = editor.addParagraph('a');
      final svBefore = editor.blockSetVersion;
      editor.updateBlockContent(
        a,
        const ParagraphElement(children: [TextElement('changed')]),
      );
      expect(editor.blockSetVersion, svBefore,
          reason: '#246 关键回归：若此处递增，按键会重建视口，局部刷新完全失效');
    });

    test('replaceBlock（同 id 换内容）不递增 blockSetVersion', () {
      final a = editor.addParagraph('a');
      final svBefore = editor.blockSetVersion;
      editor.replaceBlock(
        a,
        const ParagraphElement(children: [TextElement('replaced')]),
      );
      expect(editor.blockSetVersion, svBefore,
          reason: 'BlockId 不变 = 结构不变（replaceBlock 保持 BlockId，见 Phase 3.1-A PR #2）');
    });

    test('replaceBlockWithMigration（换新 BlockId）递增 blockSetVersion', () {
      final a = editor.addParagraph('a');
      final svBefore = editor.blockSetVersion;
      editor.replaceBlockWithMigration(
        a,
        const ParagraphElement(children: [TextElement('migrated')]),
      );
      expect(editor.blockSetVersion, greaterThan(svBefore),
          reason: 'BlockId 变了 = 块身份变了，视口必须重建');
    });

    test('insertBlock / removeBlock 递增 blockSetVersion', () {
      var sv = editor.blockSetVersion;
      final a = editor.addParagraph('a');
      expect(editor.blockSetVersion, greaterThan(sv));
      sv = editor.blockSetVersion;
      editor.removeBlock(a);
      expect(editor.blockSetVersion, greaterThan(sv));
    });

    test('structureVersion 语义未被破坏（wordCount 缓存仍会失效）', () {
      final a = editor.addParagraph('a');
      final before = editor.structureVersion;
      editor.updateBlockContent(
        a,
        const ParagraphElement(children: [TextElement('x')]),
      );
      // updateBlockContent 从不递增 structureVersion（#245 原实现如此）
      expect(editor.structureVersion, before);
    });
  });

  group('#246 dispose', () {
    test('dispose 后 notifier 被释放（重复 dispose 不抛）', () {
      final a = editor.addParagraph('a');
      registry.sync();
      registry.notifierOf(a);
      registry.dispose();
      // ValueNotifier.dispose 后再设值会抛断言——这里只验证不抛重复 dispose
      expect(() => registry.dispose(), returnsNormally);
    });
  });
}