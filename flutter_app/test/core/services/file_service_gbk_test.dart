/// #320 守门：decodeBytesAuto 的 GBK 自动兜底不再是死代码。
///
/// **缺陷根因**：旧实现 `utf8.decode(bytes, allowMalformed: true)` 对任意
/// 字节都不抛异常，GBK 分支永不可达；且 `Encoding.getByName('gb18030')`
/// 在 Dart VM / Flutter 均为 null（dart:convert 不内置），即便可达也恒降级
/// latin1。结果：GBK 文档导入即 U+FFFD 乱码，且部分序列（`C7 A7` → ǧ）
/// 连 U+FFFD 告警都不触发。
///
/// **修复语义**（本文件逐条固化）：
/// - 严格 UTF-8 成功 / 容错 UTF-8 零 U+FFFD → 一律 UTF-8（合法 UTF-8
///   绝不被误判为 GBK）；
/// - 容错 UTF-8 有损坏 **且** GBK 能零损坏解码 **且** 产出含 CJK → 采纳
///   GBK（GBK 完整解释全部字节 + UTF-8 解释结构性损坏，证据压倒性）；
/// - GBK 自身也解不干净 → 维持 UTF-8 容错结果（U+FFFD 可被
///   `containsReplacementChar` 检出，UI 可提示手动指定编码）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/services/file_service.dart';

/// GBK 字节样本助手（与生产 TextEncoding.gb18030 同源于 fast_gbk，此处
/// 直接用字面量，避免测试依赖被测实现自身）。
const List<int> gbkZhongWenCeShi = <int>[
  0xD6, 0xD0, 0xCE, 0xC4, 0xB2, 0xE2, 0xCA, 0xD4, // 「中文测试」
];

void main() {
  group('decodeBytesAuto GBK 自动兜底（#320）', () {
    test('GBK「中文测试」→ 正确解码（QA 探针原样本）', () {
      expect(decodeBytesAuto(gbkZhongWenCeShi), '中文测试');
    });

    test('GBK 中文混合 Markdown 结构 → 全文正确', () {
      // "title: 中文测试\n- 列表项\n" 的 GBK 字节（Notepad 默认编码场景）。
      final bytes = <int>[
        ...('title: '.codeUnits),
        0xD6, 0xD0, // 中
        0xCE, 0xC4, // 文
        0xB2, 0xE2, // 测
        0xCA, 0xD4, // 试
        0x0A, 0x2D, 0x20, // "\n- "
        0xC1, 0xD0, // 列
        0xB1, 0xED, // 表
        0xCF, 0xEE, // 项
        0x0A,
      ];
      expect(decodeBytesAuto(bytes), 'title: 中文测试\n- 列表项\n');
    });

    test('合法 UTF-8 中文文档 → 不被误判为 GBK', () {
      const text = '# 标题\n\n正文段落，含 **加粗** 与公式 \$E=mc^2\$。\n';
      expect(decodeBytesAuto(utf8.encode(text)), text);
    });

    test('「GBK 双字节恰为合法 UTF-8」的 C7 A7 → 保持 UTF-8（ǧ），不误切', () {
      // C7 A7 既是 GBK 的「千」也是合法二字节 UTF-8（U+01E7 ǧ）。
      // 合法 UTF-8 字节流绝不被切到 GBK。
      expect(decodeBytesAuto(const [0xC7, 0xA7]), '\u01E7');
    });

    test('纯 ASCII → 原样', () {
      expect(decodeBytesAuto('# hello world\n- item\n'.codeUnits),
          '# hello world\n- item\n');
    });

    test('空字节流 → 空串', () {
      expect(decodeBytesAuto(const <int>[]), '');
    });

    test('UTF-8 BOM → 剥离后解码', () {
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('# 标题\n')];
      expect(decodeBytesAuto(bytes), '# 标题\n');
    });

    test('GBK 全角标点与常用汉字混合 → 正确', () {
      // "，。"（GBK A3 AC / A1 A3）+ "中文"
      final bytes = <int>[
        0xA3, 0xAC, // ，
        0xA1, 0xA3, // 。
        0xD6, 0xD0, 0xCE, 0xC4, // 中文
      ];
      final out = decodeBytesAuto(bytes);
      expect(out, contains('，'));
      expect(out, contains('。'));
      expect(out, contains('中文'));
      expect(containsReplacementChar(out), isFalse,
          reason: 'GBK 采纳后不允许残留 U+FFFD');
    });

    test('GBK 采纳结果不再触发 containsReplacementChar 告警', () {
      final out = decodeBytesAuto(gbkZhongWenCeShi);
      expect(containsReplacementChar(out), isFalse);
    });
  });
}
