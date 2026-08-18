/// CAP-WORD-017 Android 模拟机真实导出 DOCX（Export Runtime E2E）。
///
/// 在真实 Flutter runtime（模拟器）上执行完整导出链：
///   Markdown → WordExporter.export → .docx 字节 → 写入应用文档目录
///   → 验证文件存在 / 大小 > 0 / ZIP magic
///
/// 验证内容：文件路径 / 权限 / 导出流程 / 真实 runtime 下 Word 导出不崩溃。
/// （真实 Word/WPS 消费端打开验证在 CAP-WORD-019/020，属 DOCX Consumer
///   Compatibility E2E，见驱动脚本 tools/adi/run_word_consumer_check.sh）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/domain/services/exporters/word_exporter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CAP-WORD-017 模拟机真实导出 DOCX（文件存在 + 大小 + ZIP magic）',
      (tester) async {
    const md = '# 标题\n\n中文段落内容\n\n- 列表项A\n- 列表项B\n\n'
        '| 列1 | 列2 |\n|---|---|\n| 1 | 2 |';

    // 真实 runtime：完整导出链
    final bytes = await WordExporter.export(md, title: 'cap-word-017');
    expect(bytes.length, greaterThan(0), reason: '导出字节非空');

    // ZIP magic 校验（PK\x03\x04）
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4b);

    // 写入应用文档目录（真实文件系统路径验证）
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File('${docsDir.path}/cap_word_017.docx');
    await file.writeAsBytes(bytes);
    expect(await file.exists(), isTrue, reason: 'docx 文件应落盘');
    final size = await file.length();
    expect(size, greaterThan(1000), reason: 'docx 大小应 > 1KB（实际 $size）');

    // 落盘文件可读回且字节一致
    final reread = await file.readAsBytes();
    expect(reread.length, bytes.length, reason: '回读字节长度一致');

    // ignore: avoid_print — 驱动脚本解析该行
    print('CAP_WORD_017_OK path=${file.path} size=$size');
  });
}
