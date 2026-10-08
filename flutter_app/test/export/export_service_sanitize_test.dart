/// issue #327 回归测试：
/// - Part A：导出文件名跟随标题块（`InMemoryDocumentEditor.titleFromContent`）
/// - Part B：`writeBytesToTempFile` 对 user-controllable title 做文件名消毒
///
/// 均用普通 `test()`（非 testWidgets）+ 真实 `Directory.systemTemp`，避免
/// fake-async 不推进真实文件 I/O 挂死。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/domain/services/export_service.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';

/// path_provider 的 method channel（与 `path_provider_platform_interface` 一致）。
const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

/// 取 basename：writeBytesToTempFile 用 `${dir.path}/$name` 拼路径（`/` 分隔），
/// Windows 下 `File.path` 可能仍保留 `/`，故按任意分隔符（`\` 或 `/`）取末段。
String _basename(String p) => p.split(RegExp(r'[\\/]')).last;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InMemoryDocumentEditor.titleFromContent', () {
    test('取首个 H1 标题块文本作为导出文件名来源', () {
      final editor = InMemoryDocumentEditor(title: '未命名');
      editor.insertBlock(
          editor.blockCount,
          const HeadingElement(level: 1, children: [TextElement('qa: export/doc')]));
      editor.insertBlock(
          editor.blockCount,
          const ParagraphElement(children: [TextElement('正文')]));
      expect(editor.titleFromContent, 'qa: export/doc');
    });

    test('H2+ 标题块不作为文件名来源（fallback null）', () {
      final editor = InMemoryDocumentEditor(title: '未命名');
      editor.insertBlock(
          editor.blockCount,
          const HeadingElement(level: 2, children: [TextElement('小节')]));
      expect(editor.titleFromContent, isNull);
    });

    test('标题块含加粗内联时拍平为纯文本', () {
      final editor = InMemoryDocumentEditor(title: '未命名');
      editor.insertBlock(
          editor.blockCount,
          const HeadingElement(level: 1, children: [
            BoldElement(children: [TextElement('我的')]),
            TextElement('笔记'),
          ]));
      expect(editor.titleFromContent, '我的笔记');
    });

    test('空标题块返回 null（让调用方 fallback 到存储层文档名）', () {
      final editor = InMemoryDocumentEditor(title: '未命名');
      editor.insertBlock(
          editor.blockCount,
          const HeadingElement(level: 1, children: []));
      expect(editor.titleFromContent, isNull);
    });

    test('无标题块返回 null', () {
      final editor = InMemoryDocumentEditor(title: '未命名');
      editor.insertBlock(
          editor.blockCount,
          const ParagraphElement(children: [TextElement('只有正文')]));
      expect(editor.titleFromContent, isNull);
    });
  });

  group('ExportService.writeBytesToTempFile 文件名消毒', () {
    late Directory tempDir;

    setUp(() {
      // 真实临时目录，保证文件真写盘。
      tempDir = Directory.systemTemp.createTempSync('tafcm_export_sanitize_');
      // path_provider 在测试宿主无真实插件实现，mock method channel 指向真实目录。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, null);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('title 含 : / 反斜杠等非法字符，文件名不含这些字符且导出成功',
        () async {
      final path = await ExportService.writeBytesToTempFile(
        Uint8List.fromList([1, 2, 3]),
        ExportFormat.pdf,
        fileName: 'qa: export/doc',
      );
      final name = _basename(path);
      expect(name.contains(':'), isFalse, reason: '未消毒的 : 残留');
      expect(name.contains('/'), isFalse, reason: '未消毒的 / 残留');
      expect(name.contains('\\'), isFalse, reason: '未消毒的反斜杠残留');
      expect(name, endsWith('.pdf'));
      expect(File(path).existsSync(), isTrue, reason: '导出文件未真正写出');
    });

    test('null fileName 走默认「Tafcm 文档」', () async {
      final path = await ExportService.writeBytesToTempFile(
        Uint8List.fromList([1]),
        ExportFormat.txt,
      );
      final name = _basename(path);
      expect(name, 'Tafcm 文档.txt');
      expect(File(path).existsSync(), isTrue);
    });

    test('空白 fileName 走默认，避免空文件名（.pdf）', () async {
      final path = await ExportService.writeBytesToTempFile(
        Uint8List.fromList([1]),
        ExportFormat.docx,
        fileName: '   ',
      );
      final name = _basename(path);
      expect(name, 'Tafcm 文档.docx');
    });

    test('合法 title 原样保留（含空格，不做空白折叠）', () async {
      final path = await ExportService.writeBytesToTempFile(
        Uint8List.fromList([1]),
        ExportFormat.pdf,
        fileName: '我的 文档',
      );
      final name = _basename(path);
      expect(name, '我的 文档.pdf');
    });
  });
}
