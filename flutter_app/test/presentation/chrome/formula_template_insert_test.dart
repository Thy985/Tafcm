/// issue #358：WYSIWYG 工具栏块级公式插入入口回归测试。
///
/// **背景**：`+` 模板菜单此前 8 项（表格/Mermaid/代码块/任务列表/引用/分隔线/
/// 图片/链接），无公式项；用户只能手输 `$$`。本文件守门新增的「块级公式」入口。
///
/// **核心守门点**：公式必须走 [TemplateInsertMode.insert]（与图片同理）。
/// insert 经 `updateSource → TextOperation → toElement → parseInline`，把
/// `$$...$$` 解析为真正的 [FormulaElement]（displayMode=true），
/// [ParagraphBlock] `_isPureBlockFormula` 据此委派 [FormulaBlock] 渲染。
/// 若误用 newBlock，模板会包成裸 [TextElement] 残留为字面文本、不渲染公式
/// （见 [image_insert_command_test.dart] 的同型回归守门）。
///
/// **issue #358 遗留项**：`+` 菜单选「块级公式」改为弹 [FormulaInsertDialog]
/// （12 预设 + 实时预览 + 语法错误提示），确认后才插入——避免手输 `$$`
/// 定界符出错；插入语义仍为 insert 模式（见上文守门点）。
///
/// 独立成文件（非并入 template_menu_test.dart）以守 TC-ARCH-7 单文件 ≤ 400 行。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/chrome/editor_strings.dart';
import 'package:tafcm/presentation/chrome/markdown_toolbar.dart';
import 'package:tafcm/presentation/chrome/templates.dart';
import 'package:tafcm/presentation/chrome/toolbar_components.dart';
import 'package:tafcm/presentation/commands/commands.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_intent.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/widgets/formula_insert_dialog.dart';

void main() {
  late InMemoryDocumentEditor editor;
  late EditorHistory history;
  late EditorCoordinator coordinator;

  setUp(() {
    editor = InMemoryDocumentEditor();
    history = EditorHistory();
    coordinator = EditorCoordinator(editor: editor, history: history);
  });

  /// 构造测试 widget：AnimatedBuilder 监听 coordinator，触发 MarkdownToolbar 重建。
  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: coordinator,
          builder: (context, _) => MarkdownToolbar(coordinator: coordinator),
        ),
      ),
    );
  }

  group('issue #358 模板常量结构', () {
    test('公式模板为 display 定界符包裹的 LaTeX 示例', () {
      expect(Templates.formulaDisplayDefault, isNotEmpty);
      expect(Templates.formulaDisplayDefault, startsWith(r'$$'));
      expect(Templates.formulaDisplayDefault, endsWith(r'$$'));
      expect(Templates.formulaDisplayDefault, contains('E=mc^2'));
    });
  });

  group('issue #358 插入语义（Intent 层，无 widget 树）', () {
    test(r'公式 insert 模式把 $$ 解析为 display FormulaElement（非字面文本）', () {
      final id = editor.addParagraph('正文');
      coordinator.setFocus(id);
      final sel = coordinator.focusedSelection;
      coordinator.intents.dispatch(InsertTemplateIntent(
        id,
        Templates.formulaDisplayDefault,
        mode: TemplateInsertMode.insert,
        selection: sel,
        cursorOffset: -2,
      ));

      // insert 不新建块
      expect(coordinator.blockCount, equals(1));

      // 核心断言：块元素重解析出 display 公式，而非残留字面 $$ 文本。
      final el = coordinator.getBlock(id);
      expect(el, isA<ParagraphElement>());
      final p = el as ParagraphElement;
      final formula =
          p.children.whereType<FormulaElement>().singleWhere((f) => f.displayMode);
      expect(formula.latex, contains('E=mc^2'));

      // 序列化回 Markdown 仍为 $$ 定界形式（保存 / 导出正确）。
      expect(coordinator.sourceOf(id), contains(r'$$E=mc^2$$'));
    });

    test(r'newBlock 模式守门：$$ 模板残留为裸 TextElement，不产生 FormulaElement', () {
      // 反向守门：证明 insert 模式的必要性。
      final id = editor.addParagraph('正文');
      coordinator.setFocus(id);
      coordinator.intents.dispatch(InsertTemplateIntent(
        editor.allIds.last,
        Templates.formulaDisplayDefault,
        mode: TemplateInsertMode.newBlock,
        cursorOffset: 0,
      ));

      final newId = editor.allIds.last;
      final newBlock = coordinator.getBlock(newId) as ParagraphElement;
      expect(newBlock.children.whereType<FormulaElement>().isEmpty, isTrue,
          reason: r'newBlock 不触发 parseInline，$$ 残留为字面文本');
      expect(newBlock.children.whereType<TextElement>().isNotEmpty, isTrue);
    });
  });

  group('issue #358 `+` 模板菜单入口', () {
    test('模板常量：公式项登记在 kTemplateConfigs 且为 insert 模式', () {
      const configs = kTemplateConfigs;
      final formulaConfig =
          configs.firstWhere((c) => c.item == TemplateMenuItem.formula);
      expect(formulaConfig.label, EditorStrings.templateMenuFormula);
      expect(formulaConfig.template, Templates.formulaDisplayDefault);
      expect(formulaConfig.mode, TemplateInsertMode.insert);
      // 唯一公式项，不重复登记。
      expect(configs.where((c) => c.item == TemplateMenuItem.formula).length,
          equals(1));
    });

    testWidgets(r'`+` 菜单选择「块级公式」→ 弹对话框 → 选预设 → 插入 $$ 并产生 FormulaElement',
        (tester) async {
      final id = editor.addParagraph('');
      coordinator.setFocus(id);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.byTooltip(EditorStrings.templateMenuTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(EditorStrings.templateMenuFormula));
      await tester.pumpAndSettle();

      // issue #358 遗留项：公式项弹 FormulaInsertDialog（预设 + 实时预览 + 错误态）。
      expect(find.byType(FormulaInsertDialog), findsOneWidget,
          reason: r'公式项应弹插入对话框（替代直接插模板）');
      // 点击「分数」预设 → 输入框填入 \frac{a}{b} 并显示实时预览。
      await tester.tap(find.text('分数'));
      await tester.pumpAndSettle();
      // 点击「插入」提交。
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();

      // 对话框关闭，公式以 $$ 定界形式插入当前块（仍为单块）。
      expect(find.byType(FormulaInsertDialog), findsNothing);
      expect(coordinator.blockCount, equals(1));
      expect(coordinator.sourceOf(id), contains(r'$$\frac{a}{b}$$'));

      // 光标落在公式体内：$$\frac{a}{b}|$$
      // template.length=15（$$\frac{a}{b}$$，\frac{a}{b}=11 字符），
      // 空块 insertOffset=0, cursorOffset=-2 → offset 13
      final sel = coordinator.viewStateOf(id)?.selection;
      expect(sel, isNotNull);
      expect(sel!.baseOffset, equals(13),
          reason: r'光标应在公式体内（\frac{a}{b} 末尾，闭合 $$ 之前）');
      expect(sel.extentOffset, equals(sel.baseOffset));

      // 渲染契约：纯块级公式段落只含一个 displayMode=true 的 FormulaElement，
      // 满足 ParagraphBlock._isPureBlockFormula → FormulaBlock 渲染路径。
      final el = coordinator.getBlock(id) as ParagraphElement;
      expect(el.children.length, equals(1));
      final only = el.children.first;
      expect(only, isA<FormulaElement>());
      expect((only as FormulaElement).displayMode, isTrue);
    });
  });
}
