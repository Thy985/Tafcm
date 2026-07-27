library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/panels/file_tree_panel.dart';

Document _doc(String id, String title, DateTime updatedAt) => Document(
      id: id,
      title: title,
      content: '',
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

void main() {
  testWidgets('FileTreePanel 渲染文档列表并触发 onOpenFile(doc.id)',
      (tester) async {
    String? tappedId;
    final docs = [
      _doc('aaa', 'Doc A', DateTime(2026, 7, 26, 10)),
      _doc('bbb', 'Doc B', DateTime(2026, 7, 25, 9)),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FileTreePanel(
          documents: docs,
          currentPath: '/data/user/0/app/documents/aaa.md',
          onOpenFile: (id) => tappedId = id,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Doc A'), findsOneWidget);
    expect(find.text('Doc B'), findsOneWidget);

    await tester.tap(find.text('Doc B'));
    await tester.pumpAndSettle();
    expect(tappedId, 'bbb');
  });

  testWidgets('FileTreePanel 空列表显示占位', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: FileTreePanel(documents: [])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('（暂无文档）'), findsOneWidget);
  });

  testWidgets('FileTreePanel 高亮当前打开文档（currentPath stem 匹配 id）',
      (tester) async {
    final docs = [
      _doc('aaa', 'Doc A', DateTime(2026, 7, 26, 10)),
      _doc('bbb', 'Doc B', DateTime(2026, 7, 25, 9)),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FileTreePanel(
          documents: docs,
          currentPath: '/x/aaa.md',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final selectedTiles =
        find.byWidgetPredicate((w) => w is ListTile && w.selected);
    expect(selectedTiles, findsOneWidget);
    final tile = tester.widget<ListTile>(selectedTiles);
    expect(tile.title, isA<Text>());
    expect((tile.title as Text).data, 'Doc A');
  });
}
