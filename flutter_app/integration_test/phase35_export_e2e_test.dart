/// T3-4 导出全链路 E2E（Tier 3）。
///
/// 设备上 md → PDF/Word 真实产出字节流，校验字节头（%PDF / PK）+ 非零尺寸，
/// 并经 [ExportService.writeBytesToTempFile] 落真实文件复核。
///
/// 运行：Android 模拟器 `flutter test integration_test/phase35_export_e2e_test.dart`
/// （CI 不跑 integration_test，结果作为手动门禁记入 verification report）。
library;

import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/domain/services/export_service.dart';

void main() {
  group('T3-4 export full-chain E2E', () {
    // 含公式 / 表格 / 代码块，覆盖完整导出链路
    const markdown = r'''
# 文档

行内 $a^2 + b^2 = c^2$ 与块级：

$$E = mc^2$$

| A | B |
|---|---|
| 1 | 2 |

```dart
void main() {}
```
''';

    testWidgets('导出 PDF 字节流含 %PDF 头', (tester) async {
      final bytes =
          await MarkdownExporter.exportToPdf(markdown, title: 'E2E', isDark: false);
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]); // %PDF
    });

    testWidgets('导出 Word 字节流含 PK 头', (tester) async {
      final bytes = await MarkdownExporter.exportToWord(markdown, title: 'E2E');
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.sublist(0, 2), [0x50, 0x4B]); // PK (ZIP/OOXML)
    });

    testWidgets('导出落真实文件并校验头', (tester) async {
      final bytes =
          await MarkdownExporter.exportToPdf(markdown, title: 'E2E', isDark: false);
      final path = await ExportService.writeBytesToTempFile(
        bytes,
        ExportFormat.pdf,
        fileName: 'e2e',
      );
      final f = io.File(path);
      expect(await f.exists(), isTrue, reason: '临时文件应已写出');
      final head = await f.openRead(0, 4).first as Uint8List;
      expect(head, [0x25, 0x50, 0x44, 0x46], reason: '文件头应为 %PDF');
    });
  });
}
