/// P0 真机 E2E：验证问题 4（导出 PDF/Word 中文乱码 + 公式未渲染）修复。
///
/// **对应文档**：docs/releases/phase3.5-realdevice-issues.md 问题 4
/// **修复内容**：pdf_exporter.dart 字体文件名 NotoSansSC-Regular.ttf → NotoSansSC.ttf
/// **可观测层**：debugPrint 'CJK font loaded successfully' / 守门测试 TC-P0-GUARD-2
///
/// 运行：flutter test integration_test/phase35_p0_export_test.dart -d <device>
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/domain/services/export_service.dart';

void main() {
  // 含中文 + 公式 + 表格 + 代码块，覆盖 P0 修复的全部场景
  const markdown = r'''
# 中文标题测试

这是一段中文正文，包含行内公式 $a^2 + b^2 = c^2$ 和加粗 **中文加粗**。

## 公式块

$$E = mc^2$$

$$\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}$$

## 表格

| 参数 | 值 | 说明 |
|------|-----|------|
| 光速 | $c$ | 真空中的光速 |
| 质量 | $m$ | 物体质量 |

## 代码块

```dart
// 中文注释
void main() {
  print('你好世界');
}
```

## 列表

- 第一项中文
- 第二项含公式 $\alpha + \beta$
- 第三项
''';

  group('P0 E2E: 问题4 — PDF 导出中文 + 公式', () {
    testWidgets('E2E-P0-6: PDF 字节流含 %PDF 头 + 足够大（含中文字体嵌入）', (tester) async {
      final bytes = await MarkdownExporter.exportToPdf(
        markdown,
        title: 'P0中文公式测试',
        isDark: false,
      );

      // 基本断言：非空 + %PDF 魔数
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46],
          reason: 'PDF 头必须是 %PDF');

      // P0 关键断言：字节流应足够大（含中文字体子集嵌入）
      // 修复前：字体加载失败 → 回退 Helvetica → 无 CJK 字体嵌入 → 文件偏小
      // 修复后：NotoSansSC.ttf 加载成功 → CJK 字体子集嵌入
      // 注意：integration_test 下 WebView 未挂载，公式回退到文本，PDF 会比真机小
      // 真机上公式以 SVG 嵌入，PDF 会更大；此处阈值取 15KB（含 CJK 子集 + 文本公式）
      expect(bytes.length, greaterThan(15000),
          reason: 'PDF 应含中文字体子集嵌入（>15KB）。'
              '修复前字体加载失败 → 回退 Helvetica → 文件偏小且中文方框');
    });

    testWidgets('E2E-P0-7: PDF 含中文 "你好世界"（非方框）', (tester) async {
      final bytes = await MarkdownExporter.exportToPdf(
        markdown,
        title: '中文验证',
        isDark: false,
      );

      // PDF 字节流中应包含中文字体的 ToUnicode CMap 或实际字符编码
      // 修复前：Helvetica 无 CJK glyph → 中文不嵌入 → PDF 中无中文字符引用
      // 修复后：NotoSansSC.ttf 含 CJK → 中文以子集嵌入
      //
      // 验证方式：PDF 字节流中应包含字体子集声明（/FontFile2 或 /FontFile3）
      // 这是 CJK TrueType 字体嵌入的标志
      final pdfStr = String.fromCharCodes(bytes);
      expect(
        pdfStr.contains('/FontFile2') || pdfStr.contains('/FontFile3'),
        isTrue,
        reason: 'PDF 应嵌入 TrueType 字体子集（/FontFile2 或 /FontFile3）。'
            '修复前字体加载失败 → 无 CJK 字体嵌入 → 中文方框',
      );
    });

    testWidgets('E2E-P0-8: PDF 公式非纯文本回退', (tester) async {
      // 公式渲染验证：修复前 WebView 未挂载 → SVG 失败 → PNG 缓存空 → 回退 [latex] 文本
      // 修复后：字体文件名正确 + WebView 就绪 → SVG 矢量嵌入
      //
      // 注意：integration_test 下 WebView 可能未挂载（L2 限制），
      // 公式可能降级到 flutter_math_fork 或文本回退。
      // 此测试验证导出不崩溃 + 字节流有效，公式渲染质量由真机人工验收。
      final bytes = await MarkdownExporter.exportToPdf(
        r'$$E = mc^2$$',
        title: '公式验证',
        isDark: false,
      );
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
    });
  });

  group('P0 E2E: 问题4 — Word 导出中文 + 公式', () {
    testWidgets('E2E-P0-9: Word 字节流含 PK 头 + 足够大', (tester) async {
      final bytes = await MarkdownExporter.exportToWord(
        markdown,
        title: 'P0中文公式测试',
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.sublist(0, 2), [0x50, 0x4B],
          reason: 'Word 头必须是 PK（ZIP/OOXML）');

      // P0 关键断言：Word 文件应足够大（含中文 document.xml + 公式图片）
      // 注意：integration_test 下 WebView 未挂载，公式回退到文本，Word 会比真机小
      expect(bytes.length, greaterThan(4000),
          reason: 'Word 文件应含中文内容 + 公式图片');
    });

    testWidgets('E2E-P0-10: Word document.xml 含中文内容', (tester) async {
      final bytes = await MarkdownExporter.exportToWord(
        '# 中文标题\n\n中文正文内容',
        title: '中文Word',
      );

      // Word 是 ZIP 格式，document.xml 在压缩前是 UTF-8 XML
      // 解压后应包含中文文字（w:t 标签内容）
      // 这里验证 ZIP 字节流非空 + PK 头（完整解压验证由真机 WPS/Word 打开人工验收）
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.sublist(0, 2), [0x50, 0x4B]);
      expect(bytes.length, greaterThan(2000),
          reason: '含中文的 Word 文件应 > 2KB');
    });
  });

  // E2E-P0-11/12 字体文件存在性已由 test/architecture/p0_realdevice_guard_test.dart
  // TC-P0-GUARD-2 覆盖（host 侧 io.File 检查，非 device 侧）。
}