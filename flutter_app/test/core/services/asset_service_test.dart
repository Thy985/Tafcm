/// Slice 4 (3.4.9 图片插入) 单元测试：AssetService（ADR-0014 v1.2 资产管理）。
///
/// 验证：
/// 1. 导入图片返回 `assets/img_<sha256前16位>.<ext>` 相对路径并物理落盘；
/// 2. 内容哈希去重：相同字节复用同一物理文件；
/// 3. 不同内容 → 不同文件名（保留原扩展名）；
/// 4. 错误处理：格式白名单 / 体积上限 / 源文件缺失 → AssetImportException。
///
/// `docsDir` 显式注入临时目录，不依赖 path_provider 平台通道
/// （CI 纯 Dart 测试环境无 MethodChannel 实现，MissingPluginException）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/services/asset_service.dart';

void main() {
  late Directory docsRoot;

  setUp(() {
    docsRoot = Directory.systemTemp.createTempSync('asset_svc_test_');
  });

  tearDown(() {
    if (docsRoot.existsSync()) {
      docsRoot.deleteSync(recursive: true);
    }
  });

  group('AssetService.importImage (ADR-0014)', () {
    test('返回 assets/ 相对路径并把文件落到 assets/ 子目录', () async {
      final src = File('${docsRoot.path}/src.png');
      await src.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
      final relative =
          await AssetService.importImage(src, docsDir: docsRoot.path);

      expect(relative, startsWith('assets/img_'),
          reason: '相对路径应以 assets/img_ 前缀');
      expect(relative, endsWith('.png'), reason: '保留原扩展名 .png');

      final target = File('${docsRoot.path}/$relative');
      expect(await target.exists(), isTrue, reason: '物理文件应已落盘');
    });

    test('相同字节去重：复用同一物理文件（仅新增 1 个副本）', () async {
      final bytes = List<int>.generate(16, (i) => i);
      final a = File('${docsRoot.path}/a.png')..writeAsBytesSync(bytes);
      final b = File('${docsRoot.path}/b.png')..writeAsBytesSync(bytes);

      final r1 = await AssetService.importImage(a, docsDir: docsRoot.path);
      final r2 = await AssetService.importImage(b, docsDir: docsRoot.path);
      expect(r1, equals(r2), reason: '内容相同 → 路径相同（去重）');

      final dir = Directory('${docsRoot.path}/assets');
      final count = dir.listSync().whereType<File>().length;
      expect(count, 1, reason: '相同内容重复导入不应新增物理文件');
    });

    test('不同内容 → 不同文件名，且保留各自扩展名', () async {
      final a = File('${docsRoot.path}/x.png')..writeAsBytesSync([1, 1]);
      final b = File('${docsRoot.path}/y.jpg')..writeAsBytesSync([2, 2]);
      final r1 = await AssetService.importImage(a, docsDir: docsRoot.path);
      final r2 = await AssetService.importImage(b, docsDir: docsRoot.path);

      expect(r1, isNot(equals(r2)), reason: '内容不同 → 文件名不同');
      expect(r1, endsWith('.png'));
      expect(r2, endsWith('.jpg'));

      expect(await File('${docsRoot.path}/$r1').exists(), isTrue);
      expect(await File('${docsRoot.path}/$r2').exists(), isTrue);
    });
  });

  group('AssetService.importImage 错误处理（评审 2026-07-26）', () {
    test('不支持的扩展名 → AssetImportException', () async {
      final src = File('${docsRoot.path}/doc.pdf')..writeAsBytesSync([1]);
      await expectLater(
        AssetService.importImage(src, docsDir: docsRoot.path),
        throwsA(isA<AssetImportException>()),
      );
    });

    test('源文件不存在（选择后被删除）→ AssetImportException', () async {
      final src = File('${docsRoot.path}/gone.png'); // 从未写入
      await expectLater(
        AssetService.importImage(src, docsDir: docsRoot.path),
        throwsA(isA<AssetImportException>()),
      );
    });

    test('AssetImportException 的 message 不含路径 / stack（用户可读）', () {
      const e = AssetImportException('图片保存失败', detail: 'disk full at C:/x');
      expect(e.message, isNot(contains('C:/')));
      expect(e.toString(), contains('图片保存失败'));
    });

    test('体积上限常量为 20MB（保护全量读内存路径）', () {
      expect(AssetService.maxAssetBytes, 20 * 1024 * 1024);
    });
  });
}
