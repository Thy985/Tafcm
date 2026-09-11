/// U3 安全边界测试族（TEST-SYSTEM-UPGRADE-PLAN §3.3）。
///
/// 参照 SoloMD dogfooding 教训（路径穿越 exploit：`{"path": "../../tmp/pwn/x.md"}`
/// 逃逸 workspace），对文档存储边界做确定性守门：
/// - `documentPathFor`：id 含路径分隔符 / `..` 时必须拒绝（逃逸 vector）
/// - front matter 恶意 id：外部 .md 可携带任意 `id:` 值，解析后若被用作
///   documentPathFor 输入，同样被守门拦截
/// - `searchDocuments` / `getDocumentPreview`：恶意输入不崩溃
///
/// 防护落点：`FileRepository.documentPathFor`（ArgumentError 拒绝式守门）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/services/file_repository.dart';

void main() {
  late Directory tempDir;
  late FileRepository repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tafcm_security_u3');
    repo = FileRepository()..testDocsDir = tempDir.path;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('U3-1 documentPathFor 拒绝路径逃逸 id', () {
    test('含 ../ 的 id 抛 ArgumentError 且不落盘', () async {
      expect(
        () => repo.documentPathFor('../../tmp/pwn/x'),
        throwsArgumentError,
      );
      expect(
        () => repo.documentPathFor(r'..\..\Windows\evil'),
        throwsArgumentError,
      );
      // 守门后目录内不得出现逃逸产物。
      expect(tempDir.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('含裸路径分隔符的 id 抛 ArgumentError', () async {
      expect(() => repo.documentPathFor('sub/dir'), throwsArgumentError);
      expect(() => repo.documentPathFor(r'sub\dir'), throwsArgumentError);
    });

    test('空 id 抛 ArgumentError', () async {
      expect(() => repo.documentPathFor(''), throwsArgumentError);
    });

    test('伪装 id（..夹在中间 / 仅点号扩展）同样被拒', () async {
      expect(() => repo.documentPathFor('a..b'), throwsArgumentError);
      expect(() => repo.documentPathFor('..a'), throwsArgumentError);
    });

    test('合法 id 正常通过并指向 documents 根内', () async {
      final path = await repo.documentPathFor('abc123');
      expect(path, contains(tempDir.path));
      expect(path.endsWith('abc123.md'), isTrue);
    });
  });

  group('U3-2 外部 .md 恶意 front matter id 的间接逃逸', () {
    test('恶意 id 文档入库后，以其 id 查路径仍被守门（不逃逸）', () async {
      // 模拟外部导入的 .md（微信/QQ 打开链路），front matter id 被注入逃逸载荷。
      final evilFile = File('${tempDir.path}${Platform.pathSeparator}evil.md');
      await evilFile.writeAsString(
        '---\nid: ../../tmp/pwn/x\ncreatedAt: 2026-01-01T00:00:00Z\n'
        'updatedAt: 2026-01-01T00:00:00Z\n---\n# evil\n',
      );

      // 列表解析不崩溃，且 id 被原样读出（发现面）。
      final docs = await repo.listDocuments();
      expect(docs, isNotEmpty);

      // 关键断言：这个恶意 id 进 documentPathFor 被拒——文件树点击路径不逃逸。
      expect(
        () => repo.documentPathFor('../../tmp/pwn/x'),
        throwsArgumentError,
      );

      // 目录根外不存在任何逃逸文件。
      final outside = Directory.systemTemp
          .listSync(recursive: false)
          .whereType<Directory>()
          .where((d) => d.path.contains('pwn'));
      expect(outside, isEmpty);
    });
  });

  group('U3-3 查询面恶意输入不崩溃', () {
    test('searchDocuments 对注入样式输入返回结果或空，不抛', () async {
      for (final q in ["'; DROP TABLE docs;--", '../../etc/passwd', '\x00']) {
        final result = await repo.searchDocuments(q);
        expect(result, isA<List>(), reason: 'query=$q 应安全返回');
      }
    });

    test('getDocumentPreview 对恶意 id 优雅失败（不逃逸读文件）', () async {
      // 守门生效后：恶意 id 在 documentPathFor 即抛出，preview 不再继续读。
      expect(
        () => repo.getDocumentPreview('../../etc/hosts'),
        throwsArgumentError,
      );
    });
  });

  group('U3-4 front matter 畸形输入', () {
    test('无 front matter / 截断 front matter / 巨型 key 行均不崩溃', () async {
      final cases = <String>[
        'no front matter here\n# t',
        '---\nunclosed: value\n# t',
        '---\n${'k' * 5000}: v\n---\n# t',
        '---\nid: x\ncreatedAt: not-a-date\nupdatedAt: also-bad\n---\nbody',
      ];
      for (var i = 0; i < cases.length; i++) {
        final f = File('${tempDir.path}${Platform.pathSeparator}fm_$i.md');
        await f.writeAsString(cases[i]);
      }
      final docs = await repo.listDocuments();
      expect(docs.length, cases.length,
          reason: '畸形 front matter 不得让任何文档从列表消失');
    });
  });
}
