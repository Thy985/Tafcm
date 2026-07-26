/// Slice 4 (3.4.9 图片插入) 测试：图片 Markdown 往返 + 插入命令解析。
///
/// 覆盖：
/// 1. parser ↔ serializer 往返：inline 图片 `![...](assets/...)` 正确解析为
///    [ImageElement] 且序列化还原一致；
/// 2. [InsertTemplateCommand](insert) 走 [BlockOperations.updateSource] →
///    [TextOperation] → [toElement] → [MarkdownParser.parseInline]，把图片语法
///    解析为 [ImageElement]（渲染层据此用 [Image.file] 画本地图）；
/// 3. 回归守门：[TemplateInsertMode.newBlock] 把模板包成 [TextElement]，
///    图片语法不会变成 [ImageElement] —— 因此图片插入必须用 insert 模式。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/editing/block_serializer.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/commands/command_handler.dart';
import 'package:formula_fix/presentation/commands/commands.dart';
import 'package:formula_fix/presentation/commands/editor_command.dart';
import 'package:formula_fix/presentation/prototype/_shared/in_memory_document_editor.dart';

void main() {
  group('图片 Markdown 往返（parser ↔ serializer）', () {
    test('段落内 inline 图片解析为 ImageElement', () {
      final el = toElement('![](assets/img_ab12cd34.png)', BlockType.paragraph);
      expect(el, isA<ParagraphElement>());
      final p = el as ParagraphElement;
      expect(p.children, hasLength(1));
      final img = p.children.first;
      expect(img, isA<ImageElement>());
      expect((img as ImageElement).url, 'assets/img_ab12cd34.png');
      expect(img.alt, '');
    });

    test('带 alt 文本的图片往返一致', () {
      const md = '![封面](assets/cover.png)';
      final el = toElement(md, BlockType.paragraph) as ParagraphElement;
      expect(fromElement(el), md);
    });

    test('纯图片块序列化还原为原始 Markdown', () {
      const md = '![](assets/img_ab12cd34.png)';
      final el = toElement(md, BlockType.paragraph) as ParagraphElement;
      expect(fromElement(el), md);
    });
  });

  group('InsertTemplateCommand(image) → ImageElement', () {
    late InMemoryDocumentEditor editor;
    late EditorHistory history;
    late CommandHandler handler;

    setUp(() {
      editor = InMemoryDocumentEditor();
      history = EditorHistory();
      handler = CommandHandler(editor: editor, history: history);
    });

    test('insert 模式把 ![...](assets/...) 解析为 ImageElement（而非裸文本）', () {
      final id = editor.addParagraph('正文');
      final success = handler.handle(InsertTemplateCommand(
        blockId: id,
        template: '![](assets/img_ab12cd34.png)',
        mode: TemplateInsertMode.insert,
        origin: CommandOrigin.menu,
      ));
      expect(success, isTrue, reason: 'InsertTemplateCommand 应被 dispatch');

      final el = editor.getBlock(id);
      expect(el, isA<ParagraphElement>());
      final p = el as ParagraphElement;
      expect(p.children.any((c) => c is ImageElement), isTrue,
          reason: '图片语法应被解析为 ImageElement，而非残留为 TextElement 裸文本');
      final img = p.children.whereType<ImageElement>().single;
      expect(img.url, 'assets/img_ab12cd34.png');

      // 序列化回 Markdown 仍含图片语法（保存 / 导出正确）
      expect(fromElement(p), contains('![](assets/img_ab12cd34.png)'));
    });

    test('newBlock 模式（回归守门）：图片语法不会变成 ImageElement', () {
      final id = editor.addParagraph('正文');
      final success = handler.handle(InsertTemplateCommand(
        blockId: id,
        template: '![](assets/img_ab12cd34.png)',
        mode: TemplateInsertMode.newBlock,
        origin: CommandOrigin.menu,
      ));
      expect(success, isTrue);

      // 原块不变
      final original = editor.getBlock(id) as ParagraphElement;
      expect(original.children.any((c) => c is ImageElement), isFalse,
          reason: 'newBlock 把模板包成 TextElement，图片不会出现在原块');

      // 新块内容仍是裸文本（这正说明图片插入必须用 insert 模式）
      final newBlock = editor.getBlock(editor.allIds.last) as ParagraphElement;
      expect(newBlock.children.whereType<ImageElement>().isEmpty, isTrue);
      expect(newBlock.children.whereType<TextElement>().isNotEmpty, isTrue);
    });
  });
}
