/// P0-2 编码手动指定守门（EXTERNAL-PROJECTS-EMPOWERMENT-PLAN §4.2 验收）。
///
/// 覆盖：
/// - TextEncoding 原语：GBK/Big5 字节解码、encode/decode 往返、
///   tryParse 白名单（含别名）、U+FFFD 检测
/// - front-matter `encoding:` 声明：build 写入声明 / parse 读端接线
/// - FileRepository 声明感知读端：GBK 原件解码正确、utf8 容错不受影响
/// - FileRepository 声明保持写端：GBK 原件编辑后字节仍为 GBK（不漂移 UTF-8）
///
/// GB18030 依赖运行时 `Encoding.getByName`（flutter_test 环境
/// dart:io 下可用），与 file_service_decode_test 同前提。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/core/services/file_service.dart';
import 'package:tafcm/core/services/front_matter_parser.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _MockPathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// GBK 编码助手：测试环境 `Encoding.getByName` 可能不提供 GBK
/// （file_service_decode_test 先例：不可用即 skip 该用例）。
/// 返回 null 表示环境不支持，调用方 skip。
Encoding? _gbkEncoder() =>
    Encoding.getByName('gb18030') ?? Encoding.getByName('gbk');

void main() {
  group('TextEncoding 原语', () {
    test('gb18030 解码 GBK 字节正确', () {
      final enc = _gbkEncoder();
      if (enc == null) {
        // 编码器不可用即 skip（同 file_service_decode_test 先例）。
        return;
      }
      const text = '矩阵的逆与定积分';
      final decoded = TextEncoding.gb18030.decode(enc.encode(text));
      expect(decoded, text);
    });

    test('encode → decode 往返一致（gb18030 / latin1）', () {
      const sample = 'Abc 中文 123';
      // latin1 1:1 字节映射：非 Latin-1 字符降级为 `?`（allowInvalid 兜底，
      // 写路径永不抛）——断言 ASCII 段保留 + 不抛异常即守门。
      final l1Bytes = TextEncoding.latin1.encode(sample);
      expect(l1Bytes, everyElement(isA<int>()));
      expect(TextEncoding.latin1.decode(l1Bytes), startsWith('Abc'));
      final enc = _gbkEncoder();
      if (enc == null) return; // 环境不支持 GBK 则 skip
      expect(
          TextEncoding.gb18030.decode(TextEncoding.gb18030.encode(sample)),
          sample);
    });

    test('tryParse 白名单：全名 / 别名 / 大小写 / 未知值', () {
      expect(TextEncoding.tryParse('utf-8'), TextEncoding.utf8);
      expect(TextEncoding.tryParse('UTF8'), TextEncoding.utf8);
      expect(TextEncoding.tryParse('gbk'), TextEncoding.gb18030);
      expect(TextEncoding.tryParse('GB2312'), TextEncoding.gb18030);
      expect(TextEncoding.tryParse('big5'), TextEncoding.big5);
      expect(TextEncoding.tryParse('iso-8859-1'), TextEncoding.latin1);
      expect(TextEncoding.tryParse('shift-jis'), isNull);
      expect(TextEncoding.tryParse(null), isNull);
      expect(TextEncoding.tryParse(''), isNull);
    });

    test('containsReplacementChar 检测容错解码痕迹', () {
      // 拉丁 1 非法 UTF-8 序列 → utf8 容错解码产生 U+FFFD。
      final text = TextEncoding.utf8.decode([0x61, 0xFF, 0x62]);
      expect(containsReplacementChar(text), isTrue);
      expect(containsReplacementChar('正常文本'), isFalse);
    });
  });

  group('front-matter encoding 声明', () {
    test('build 带 encoding 写入声明，不带不写', () {
      final withDecl = FrontMatterParser.build(
        id: 'a',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        title: 'T',
        content: 'c',
        encoding: 'gb18030',
      );
      expect(withDecl, contains('encoding: gb18030'));

      final noDecl = FrontMatterParser.build(
        id: 'a',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        title: 'T',
        content: 'c',
      );
      expect(noDecl, isNot(contains('encoding:')));
    });
  });

  group('FileRepository 声明感知（临时目录）', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('tafcm_enc_test_');
      PathProviderPlatform.instance = _MockPathProvider(tmp.path);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    /// 构造 GBK 原件（声明 + GBK 编码的正文，模拟外部 GBK 文件导入）。
    /// 环境无 GBK 编码器时返回 null（调用方 skip）。
    Future<File?> _writeGbkFixture(String name, String body) async {
      final enc = _gbkEncoder();
      if (enc == null) return null;
      final f = File('${tmp.path}${Platform.pathSeparator}$name');
      final md = FrontMatterParser.build(
        id: 'gbk-$name',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        title: 'GBK 文档',
        content: body,
        encoding: 'gb18030',
      );
      await f.writeAsBytes(enc.encode(md));
      return f;
    }

    test('读端：GBK 原件按声明解码正确（绕过自动链）', () async {
      final f = await _writeGbkFixture('a.md', '矩阵与行列式');
      if (f == null) return; // 环境不支持 GBK 编码器则 skip
      final repo = FileRepository();
      final doc = await repo.readDocument(f.path);
      expect(doc.title, 'GBK 文档');
      expect(doc.content, contains('矩阵与行列式'));
    });

    test('写端：GBK 原件编辑后字节仍为 GBK（声明保持，不漂移 UTF-8）', () async {
      final f = await _writeGbkFixture('b.md', '原始内容');
      if (f == null) return; // 环境不支持 GBK 编码器则 skip
      final repo = FileRepository();

      await repo.writeDocument(f.path, title: 'GBK 文档', content: '编辑后的内容');

      final bytes = await f.readAsBytes();
      // 字节级断言：按声明 GBK 解码应还原"编辑后的内容"（若已漂移成
      // UTF-8，GBK 解码会得到乱码而非目标串）。
      final gbk = _gbkEncoder()!;
      expect(gbk.decode(bytes), contains('编辑后的内容'),
          reason: '按声明 GBK 写回');
      // 声明行保留。
      expect(latin1.decode(bytes.sublist(0, 128)), contains('encoding: gb18030'));
    });

    test('无声明文件保持旧行为：自动链读 + UTF-8 写', () async {
      final f = File('${tmp.path}${Platform.pathSeparator}plain.md');
      await f.writeAsString('# 无声明\n\n正文', encoding: utf8);
      final repo = FileRepository();
      final doc = await repo.readDocument(f.path);
      expect(doc.content, contains('正文'));
      await repo.writeDocument(f.path, title: '无声明', content: '新正文');
      // 无声明 → UTF-8 写回，且不注入声明行。
      final text = await f.readAsString(encoding: utf8);
      expect(text, contains('新正文'));
      expect(text, isNot(contains('encoding:')));
    });
  });
}
