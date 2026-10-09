/// FileRepository.getDocumentPreview 单元测试（ADR-0020 PR A review 反馈）。
///
/// 覆盖：正常文档 / 空文档 / 文件不存在 / 长短截断 / 纯空格首行。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/core/services/file_service.dart';

void main() {
  late Directory _tmpDir;
  late FileRepository _repo;

  setUp(() async {
    _tmpDir = Directory.systemTemp.createTempSync('ff_preview_test_');
    _repo = FileRepository()..testDocsDir = _tmpDir.path;
  });

  tearDown(() async {
    if (_tmpDir.existsSync()) _tmpDir.deleteSync(recursive: true);
  });

  test('正常文档：首非空行 ≤ 40 字符不截断', () async {
    final path = '${_tmpDir.path}/test.md';
    await File(path).writeAsString('# Title\n\nbody');
    final preview = await _repo.getDocumentPreview('test');
    expect(preview, '# Title');
  });

  test('正常文档：首非空行 > 40 字符截断 + …', () async {
    final path = '${_tmpDir.path}/long.md';
    final longLine = 'A' * 60;
    await File(path).writeAsString('$longLine\nbody');
    final preview = await _repo.getDocumentPreview('long');
    expect(preview.length, 41); // 40 chars + \u2026 (1 char)
    expect(preview, startsWith('A' * 40));
    expect(preview, endsWith('\u2026'));
  });

  test('多空行开头：跳过，取首非空行', () async {
    final path = '${_tmpDir.path}/blank.md';
    await File(path).writeAsString('\n\n\n## Real Title\n');
    final preview = await _repo.getDocumentPreview('blank');
    expect(preview, '## Real Title');
  });

  test('空文档（仅空行）→ 返回空字符串', () async {
    final path = '${_tmpDir.path}/empty.md';
    await File(path).writeAsString('\n\n\n');
    final preview = await _repo.getDocumentPreview('empty');
    expect(preview, '');
  });

  test('纯空格行：视为空行，无有效内容返回空字符串', () async {
    final path = '${_tmpDir.path}/whitespace.md';
    await File(path).writeAsString('   \n   \n');
    final preview = await _repo.getDocumentPreview('whitespace');
    expect(preview, '');
  });

  test('文件不存在 → 返回空字符串（优雅降级）', () async {
    final preview = await _repo.getDocumentPreview('nonexistent');
    expect(preview, '');
  });

  group('#336-6 GBK 编码文件预览（AGENTS §4.3 编码兜底）', () {
    // 「中文测试」的 GBK 字节序列（与 file_service_gbk_test 同源样本）。
    // 这些字节在 UTF-8 下是非法序列，strict `utf8.decoder` 会在首个非法
    // 字节上抛 `FormatException: Missing extension byte`（旧实现的崩溃形态）。
    const gbkTitle = <int>[
      0xD6, 0xD0, // 中
      0xCE, 0xC4, // 文
      0xB2, 0xE2, // 测
      0xCA, 0xD4, // 试
    ];

    test('decodeBytesAuto 对 GBK 标题字节产出中文（兜底判定前提）', () {
      expect(decodeBytesAuto(gbkTitle), '中文测试');
    });

    test('GBK 文件预览返回标题，不抛 FormatException', () async {
      final path = '${_tmpDir.path}/gbk.md';
      // 标题行 + 空行 + 正文行，模拟真实 .md 结构。
      await File(path).writeAsBytes(
        <int>[...gbkTitle, 0x0A, 0x0A, ...gbkTitle],
      );
      final preview = await _repo.getDocumentPreview('gbk');
      expect(preview, '中文测试');
    });
  });
}
