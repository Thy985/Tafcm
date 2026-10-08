/// #319 回归测试：活动文档 .md 从磁盘消失后的可见性与自愈。
///
/// **事件背景**（QA 2026-10-04 实测）：活动文档 .md 被外部删除后，应用不
/// 重建、不告知——列表流在读竞态下反复抛错，两屏冻结在陈旧数据；用户停止
/// 编辑后自动保存永不触发（仅由 dirty 翻转驱动），磁盘长期无文件。
///
/// 本文件覆盖可确定性验证的守门面：
/// - [FileRepository.documentFileExists]（编辑器 resume 检测的数据源）
/// - 文件被外部删除后 `listDocuments` 如实反映磁盘现状（不残留幽灵条目）
/// - 列表读取对「listSync 与读取之间消失」的文件具备容错（单文件失败不炸
///   整个列表——通过子类注入读取失败模拟竞态）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/data/models/document.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _MockPathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// 注入「读取即失败」的文件名，模拟 listSync 与读取之间文件消失的竞态
/// （#319 logcat 中的 PathNotFoundException：Cannot open file）。
class _RacyFileRepository extends FileRepository {
  final Set<String> vanishingNames;
  _RacyFileRepository(this.vanishingNames);

  @override
  Future<Document> readDocument(String path) async {
    if (vanishingNames.contains(Uri.file(path).pathSegments.last)) {
      throw StateError(' simulated race: file vanished before read');
    }
    return super.readDocument(path);
  }
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tafcm_t319_test_');
    PathProviderPlatform.instance = _MockPathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('documentFileExists（编辑器 resume 检测数据源）', () {
    test('存在的文件 → true；消失的文件 → false', () async {
      final repo = FileRepository()..testDocsDir = tmp.path;
      final path = '${tmp.path}${Platform.pathSeparator}exists.md';
      await File(path).writeAsString('# 文档\n\n正文');
      expect(await repo.documentFileExists(path), isTrue);
      await File(path).delete();
      expect(await repo.documentFileExists(path), isFalse);
    });
  });

  group('listDocuments 对消失文件的处理（#319）', () {
    test('外部删除后列表如实反映磁盘现状，无幽灵条目', () async {
      final repo = FileRepository()..testDocsDir = tmp.path;
      final p1 = await repo.createDocument('文档一', '内容一');
      await repo.createDocument('文档二', '内容二');

      expect((await repo.listDocuments()).length, 2);

      // 模拟外部删除（不经 repository API）。
      await File(p1).delete();

      final docs = await repo.listDocuments();
      expect(docs.length, 1);
      expect(docs.single.title, '文档二');
    });

    test('单文件读取竞态失败不炸整个列表：其余文档照常列出', () async {
      // 竞态模拟：listSync 能列出 vanishing.md，但读取瞬间它"消失"。
      final vanishing = File('${tmp.path}${Platform.pathSeparator}vanishing.md');
      await vanishing.writeAsString('# 幽灵\n\n不该被读到');
      final healthy = File('${tmp.path}${Platform.pathSeparator}healthy.md');
      await healthy.writeAsString('# 健康\n\n正常内容');

      final repo = _RacyFileRepository({'vanishing.md'})
        ..testDocsDir = tmp.path;

      final docs = await repo.listDocuments();
      expect(docs.length, 1, reason: '#319：单文件读取失败不得让整个列表抛错');
      expect(docs.single.title, '健康');
    });
  });
}
