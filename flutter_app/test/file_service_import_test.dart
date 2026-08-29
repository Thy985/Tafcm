/// P1 回归测试（2026-08-06，phase3.5-realdevice-issues 问题 6A）：
/// `FileService.importFile` 文件选择器参数与扩展名校验。
///
/// 锁定三项行为：
/// 1. **pickFiles 必须用 `FileType.any`**（非 `FileType.custom` + allowedExtensions）。
///    原因：file_picker 8.3.7 在 Android 把 `FileType.custom` 转成
///    `Intent(type='*/*', EXTRA_MIME_TYPES=[...])`，小米 HyperOS SAF 过滤异常 →
///    弹窗完全空白。`FileType.any` 让 SAF 显示所有文件，Dart 层校验扩展名。
/// 2. **用户取消（pickFiles 返回 null）→ 抛 [FileImportException]**（非静默返回空串）。
/// 3. **选非白名单扩展名 → 抛 [FileImportException]，message 含"仅支持"**。
/// 4. **选白名单扩展名（.md/.txt/.tex）→ 读取文件并解码**（走 decodeBytesAuto）。
///
/// FilePicker 通过 PlatformInterface 暴露静态 `platform` setter，
/// 可在测试中注入 mock 子类（见 file_picker 8.3.7 `src/file_picker.dart:30-42`）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tafcm/core/services/file_service.dart';

/// 测试用 [FilePicker] 桩：记录 pickFiles 调用参数，按构造时指定的结果返回。
///
/// 必须继承（而非 implements）[FilePicker]，因为 file_picker 的 PlatformInterface
/// 用 token 校验 set platform 的实例（`src/file_picker.dart:33-42`）。
class _MockFilePicker extends FilePicker {
  _MockFilePicker(this._result);

  final FilePickerResult? _result;

  /// 最近一次 pickFiles 调用的参数（用于断言 type）。
  FileType? lastType;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    lastType = type;
    return _result;
  }
}

/// 路径提供桩：避免 path_provider 在测试环境抛 MissingPluginException。
class _MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => '/tmp/test_docs';
}

/// 创建临时文件并返回路径，用于验证 importFile 读取白名单扩展名文件。
String _writeTempFile(String name, List<int> bytes) {
  final dir = Directory('/tmp/test_docs');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _MockPathProviderPlatform();
  });

  setUp(() {
    // 每个测试前清理临时目录，避免上一个测试的文件污染。
    final dir = Directory('/tmp/test_docs');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  tearDown(() {
    final dir = Directory('/tmp/test_docs');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('P1 FileService.importFile（phase3.5-realdevice-issues 问题 6A）', () {
    test('pickFiles 必须用 FileType.any（非 custom + allowedExtensions）',
        () async {
      final mockPicker = _MockFilePicker(null);
      FilePicker.platform = mockPicker;

      // 用户取消 → 抛异常，但我们只关心 pickFiles 被调用时的 type 参数。
      await expectLater(FileService.importFile(), throwsA(isA<FileImportException>()));

      expect(mockPicker.lastType, FileType.any,
          reason:
              '必须用 FileType.any 绕过小米 HyperOS SAF 对 custom+MIME 过滤异常的 bug');
    });

    test('用户取消（pickFiles 返回 null）→ 抛 FileImportException', () async {
      final mockPicker = _MockFilePicker(null);
      FilePicker.platform = mockPicker;

      await expectLater(
        FileService.importFile(),
        throwsA(isA<FileImportException>()),
      );
    });

    test('选非白名单扩展名（.pdf）→ 抛 FileImportException，message 含"仅支持"',
        () async {
      // mock 返回一个 .pdf 路径（文件无需真实存在，校验在 readAsBytes 之前）。
      final mockResult = FilePickerResult([
        PlatformFile(path: '/mock/doc.pdf', name: 'doc.pdf', size: 100),
      ]);
      final mockPicker = _MockFilePicker(mockResult);
      FilePicker.platform = mockPicker;

      await expectLater(
        FileService.importFile(),
        throwsA(allOf(
          isA<FileImportException>(),
          predicate<FileImportException>(
              (e) => e.message.contains('仅支持')),
        )),
      );
    });

    test('选 .md 文件 → 读取并解码内容', () async {
      final bytes = [0x68, 0x65, 0x6C, 0x6C, 0x6F]; // "hello"
      final path = _writeTempFile('doc.md', bytes);

      final mockResult = FilePickerResult([
        PlatformFile(path: path, name: 'doc.md', size: bytes.length),
      ]);
      final mockPicker = _MockFilePicker(mockResult);
      FilePicker.platform = mockPicker;

      final content = await FileService.importFile();
      expect(content, 'hello');
    });

    test('选 .txt 文件 → 读取并解码内容', () async {
      final bytes = [0x74, 0x65, 0x78, 0x74]; // "text"
      final path = _writeTempFile('notes.txt', bytes);

      final mockResult = FilePickerResult([
        PlatformFile(path: path, name: 'notes.txt', size: bytes.length),
      ]);
      final mockPicker = _MockFilePicker(mockResult);
      FilePicker.platform = mockPicker;

      final content = await FileService.importFile();
      expect(content, 'text');
    });

    test('选 .tex 文件 → 读取并解码内容', () async {
      final bytes = [0x24, 0x78, 0x24]; // "$x$"
      final path = _writeTempFile('formula.tex', bytes);

      final mockResult = FilePickerResult([
        PlatformFile(path: path, name: 'formula.tex', size: bytes.length),
      ]);
      final mockPicker = _MockFilePicker(mockResult);
      FilePicker.platform = mockPicker;

      final content = await FileService.importFile();
      expect(content, r'$x$');
    });

    test('扩展名校验大小写不敏感（.MD 大写扩展名）', () async {
      final bytes = [0x68, 0x69]; // "hi"
      final path = _writeTempFile('UPPER.MD', bytes);

      final mockResult = FilePickerResult([
        PlatformFile(path: path, name: 'UPPER.MD', size: bytes.length),
      ]);
      final mockPicker = _MockFilePicker(mockResult);
      FilePicker.platform = mockPicker;

      final content = await FileService.importFile();
      expect(content, 'hi',
          reason: '.MD 大写扩展名应通过校验（toLowerCase 处理）');
    });
  });
}
