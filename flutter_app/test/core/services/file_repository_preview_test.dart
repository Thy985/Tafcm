/// FileRepository.getDocumentPreview 单元测试（ADR-0020 PR A review 反馈）。
///
/// 覆盖：正常文档 / 空文档 / 文件不存在 / 长短截断 / 纯空格首行。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/services/file_repository.dart';

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
}
