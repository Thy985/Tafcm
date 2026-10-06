/// #319 逻辑回归：`recreateDocFileIfMissing` 守护函数（真实文件系统）。
///
/// EditorPage 的 resume 接线由 `editor_page_missing_file_test.dart`（内存
/// fake 仓储）覆盖；本文件用**真实临时目录**覆盖守护函数本身的文件系统行为：
/// - 文件消失 → 用内存内容重建，返回 true；
/// - 文件健在 → 不动文件（不重写、不改 mtime），返回 false；
/// - 仓储异常 → 原样上抛（调用方决定上报与文案）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/presentation/editor/doc_file_resume_guard.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _MockPathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory tmp;
  late File docFile;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tafcm_t319_guard_');
    PathProviderPlatform.instance = _MockPathProvider(tmp.path);
    docFile = File('${tmp.path}${Platform.pathSeparator}guard_doc.md');
    await docFile.writeAsString('# 旧内容\n');
  });

  tearDown(() async {
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } on FileSystemException {
      // Windows 句柄延迟释放：忽略（系统临时目录会被 OS 回收）。
    }
  });

  test('文件消失 → 用内存内容重建，返回 true', () async {
    final repo = FileRepository()..testDocsDir = tmp.path;
    await docFile.delete();

    final recreated = await recreateDocFileIfMissing(
      repo: repo,
      path: docFile.path,
      title: '守护测试',
      content: '# 守护测试\n\n内存中的最新内容',
    );

    expect(recreated, isTrue);
    expect(await docFile.readAsString(), contains('内存中的最新内容'));
  });

  test('文件健在 → 返回 false 且不重写（mtime 不变）', () async {
    final repo = FileRepository()..testDocsDir = tmp.path;
    final beforeModified = docFile.lastModifiedSync();
    final before = await docFile.readAsString();

    final recreated = await recreateDocFileIfMissing(
      repo: repo,
      path: docFile.path,
      title: '守护测试',
      content: '# 不该写入的内容',
    );

    expect(recreated, isFalse);
    expect(docFile.lastModifiedSync(), beforeModified, reason: '不得重写健在文件');
    expect(await docFile.readAsString(), before);
  });

  test('仓储抛异常 → 原样上抛', () async {
    final repo = FileRepository()..testDocsDir = tmp.path;
    await docFile.delete();
    // 制造一个必然失败的写入目标：路径指向一个已存在的**目录**。
    final dirAsPath = '${tmp.path}${Platform.pathSeparator}not_a_file.md';
    await Directory(dirAsPath).create();

    expect(
      () => recreateDocFileIfMissing(
        repo: repo,
        path: dirAsPath,
        title: 'x',
        content: 'y',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
