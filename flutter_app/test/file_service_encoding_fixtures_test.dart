/// U6 真实编码样本 fixture 测试（TEST-SYSTEM-UPGRADE-PLAN §3.6）。
///
/// 学 Jota 的教训：其"多编码能力"实来自 UniversalChardet 库的成熟探测，
/// 而库自带真实样本测试——合成字符串测不出真实世界字节流的坑。
/// 本测试用 `test/fixtures/encodings/` 下的**真实二进制样本**逐个断言
/// `decodeBytesAuto` 行为。
///
/// 样本清单（字节构成见 README）：
/// - gbk_note_cn.txt       GBK 编码"你好世界"（中文 Windows 记事本默认）
/// - utf8_bom_cn.txt       UTF-8 BOM + 中文
/// - utf16le_bom_cn.txt    UTF-16LE BOM + 中文（Windows Notepad "Unicode"）
/// - big5_tw.txt           Big5 编码"你好"（繁体 Windows 传统编码）
/// - mixed_utf8_with_gbk.txt  UTF-8 流中混入 GBK 字节（中国用户常见）
/// - latin1_fallback.txt   Latin-1 "Hello©"
///
/// **已登记缺口**（发现于 Wave U6，待 §4.2 编码显式化立项修复）：
/// `decodeBytesAuto` 的容错 UTF-8 分支（file_service.dart:27
/// `allowMalformed: true`）**永不抛错**，因此 GBK 专属分支（:34-38）
/// 在"无 BOM 的纯 GBK 文件"场景**不可达**——GBK 字节会先被容错 UTF-8
/// 消费，产出 U+FFFD 乱码。本测试对该场景断言"不抛错 + 可识别降级"
/// 而非"正确解码"，并把正确预期写在 reason 里供 §4.2 修复时改断言。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/services/file_service.dart';

const _fixtureDir = 'test/fixtures/encodings';

List<int> _readFixture(String name) {
  final file = File('$_fixtureDir/$name');
  expect(file.existsSync(), isTrue, reason: '缺少编码样本 fixture: $name');
  return file.readAsBytesSync();
}

void main() {
  group('U6-1 有 BOM 的样本（探测优先级 1，应精确解码）', () {
    test('UTF-8 BOM + 中文 → 正确解码且 BOM 被剥离', () {
      final result = decodeBytesAuto(_readFixture('utf8_bom_cn.txt'));
      expect(result, '你好世界',
          reason: 'UTF-8 BOM 路径是最成熟的分支，必须精确');
      expect(result.startsWith('\uFEFF'), isFalse, reason: 'BOM 必须被剥离');
    });

    test('UTF-16LE BOM + 中文 → 不抛错（正确解码待 §4.2 补 UTF-16 分支）', () {
      // 当前 decodeBytesAuto 无 UTF-16 分支：0xFF 0xFE 开头不是 UTF-8 BOM，
      // 严格/容错 UTF-8 都产出乱码。登记为缺口：Windows Notepad 存
      // "Unicode" 编码时用户会拿到这种文件。
      final result = decodeBytesAuto(_readFixture('utf16le_bom_cn.txt'));
      expect(result, isNotEmpty, reason: 'UTF-16LE 样本至少不能解码为空');
      // TODO(§4.2): 正确行为应是 expect(result, '你好世界')——
      // 需在 decodeBytesAuto 增加 UTF-16 BOM 分支。
    });
  });

  group('U6-2 无 BOM 的非 UTF-8 样本（容错路径，登记真实行为）', () {
    test('GBK"你好世界"→ 不抛错；正确解码依赖 §4.2 显式编码分支', () {
      final result = decodeBytesAuto(_readFixture('gbk_note_cn.txt'));
      // 真实行为：容错 UTF-8 先消费 GBK 双字节 → U+FFFD 乱码（GBK 分支
      // 不可达，见文件头注释）。可断言的契约是"不抛错、非空"。
      expect(result, isNotEmpty);
      // TODO(§4.2): 正确行为应是 expect(result, '你好世界')——
      // 需调整探测顺序或提供显式编码入口 decodeBytesWith。
    });

    test('Big5"你好"→ 不抛错（Big5 从未被支持，属 latin1/容错兜底）', () {
      final result = decodeBytesAuto(_readFixture('big5_tw.txt'));
      expect(result, isNotEmpty, reason: 'Big5 样本至少不能解码为空');
    });

    test('Latin-1 "Hello©" → 内容主体保留', () {
      final result = decodeBytesAuto(_readFixture('latin1_fallback.txt'));
      expect(result, contains('Hello'),
          reason: '0xA9 在容错 UTF-8 中变 U+FFFD，但 ASCII 主体必须保留');
    });
  });

  group('U6-3 混合字节流（中国用户真实场景）', () {
    test('UTF-8 流混入 GBK 字节 → 不抛错，UTF-8 部分完整保留', () {
      final result = decodeBytesAuto(_readFixture('mixed_utf8_with_gbk.txt'));
      expect(result, contains('# Doc'),
          reason: '混合流中 UTF-8 主体必须完好（decodeBytesAuto 的设计目标）');
      // 文件内容 "# Doc\n\n<GBK字节>\n" → split 为 4 段。
      final lines = result.split('\n');
      expect(lines, hasLength(4), reason: '行结构不得因容错解码而丢失');
      // GBK 段的真实行为：被容错 UTF-8 消费成 U+FFFD（GBK 分支不可达，
      // 见文件头"已登记缺口"）。断言该行为以便 §4.2 修复时同步改断言。
      // TODO(§4.2): 正确行为应是 lines[2] == '你好世界'。
      expect(lines[2], contains('\uFFFD'),
          reason: 'GBK 段当前走容错路径产出替换符——若此断言失败说明'
              '解码行为已变化（可能 §4.2 已修复），请同步更新本组断言');
    });
  });

  group('U6-4 真实样本 × FileRepository 端到端', () {
    test('GBK 样本落盘再读取 → 不抛错（存储链路对任意字节安全）', () async {
      final tempDir = Directory.systemTemp.createTempSync('tafcm_u6_e2e');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final file = File('${tempDir.path}${Platform.pathSeparator}gbk.md');
      await file.writeAsBytes(_readFixture('gbk_note_cn.txt'));

      final bytes = await file.readAsBytes();
      final decoded = decodeBytesAuto(bytes);
      expect(decoded, isNotEmpty, reason: '端到端：GBK 字节文件经读盘-解码不抛错');
    });
  });
}
