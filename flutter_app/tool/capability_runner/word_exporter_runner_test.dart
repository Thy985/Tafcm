import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/domain/services/exporters/word_exporter.dart';

/// Word 真实导出 runner（3.11 Word Full Golden Loop）：
/// 真实 md 输入 → FormulaFix WordExporter → 真实 docx 产物（FFX_OUT_DIR）。
/// 回退 word_ooxml_builder 产品代码 → 导出的 docx 有缺陷 → docx_qa audit 失败
/// → verify word FAIL（Controlled Real Defect Reproduction，真实代码缺陷）。
void main() {
  test('word exporter live export: md -> WordExporter -> docx', () async {
    const md = '''
# 标题

中文段落 with **bold** and *italic*.

- 列表项一
- 列表项二

行内公式 \$E=mc^2\$ 与文本混合。

| 列A | 列B |
|-----|-----|
| 1   | 2   |
''';
    final bytes = await WordExporter.export(md, title: 'word-full-loop');
    final outDir = Platform.environment['FFX_OUT_DIR'] ??
        Directory.systemTemp.path;
    final out = File('$outDir/cap_word_live.docx');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
    print('WORD_LIVE_DOCX ${out.path} size=${bytes.length}');
  });
}
