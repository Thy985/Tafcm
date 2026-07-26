/// Slice 4 (3.4.9 图片插入) 单元测试：AssetService（ADR-0014 资产管理）。
///
/// 验证：
/// 1. 导入图片返回 `assets/img_<sha256前16位>.<ext>` 相对路径并物理落盘；
/// 2. 内容哈希去重：相同字节复用同一物理文件；
/// 3. 不同内容 → 不同文件名（保留原扩展名）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/services/asset_service.dart';

void main() {
  // getApplicationDocumentsDirectory() 需要测试绑定提供 method channel mock。
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('AssetService.importImage (ADR-0014)', () {
    test('返回 assets/ 相对路径并把文件落到 assets/ 子目录', () async {
      final src = File(
        '${Directory.systemTemp.path}/src_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await src.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
      final relative = await AssetService.importImage(src);

      expect(relative, startsWith('assets/img_'),
          reason: '相对路径应以 assets/img_ 前缀');
      expect(relative, endsWith('.png'), reason: '保留原扩展名 .png');

      final docsDir = await AssetService.documentsDir();
      final target = File('$docsDir/$relative');
      expect(await target.exists(), isTrue, reason: '物理文件应已落盘');

      await src.delete();
    });

    test('相同字节去重：复用同一物理文件（仅新增 1 个副本）', () async {
      final bytes = List<int>.generate(16, (i) => i);
      final a = File('${Directory.systemTemp.path}/a.png')..writeAsBytesSync(bytes);
      final b = File('${Directory.systemTemp.path}/b.png')..writeAsBytesSync(bytes);

      final r1 = await AssetService.importImage(a);
      final r2 = await AssetService.importImage(b);
      expect(r1, equals(r2), reason: '内容相同 → 路径相同（去重）');

      final docsDir = await AssetService.documentsDir();
      final dir = Directory('$docsDir/assets');
      final before = dir.existsSync()
          ? dir.listSync().whereType<File>().length
          : 0;
      await AssetService.importImage(a);
      await AssetService.importImage(b);
      final after = dir.listSync().whereType<File>().length;
      expect(after - before, 1, reason: '相同内容重复导入不应新增物理文件');

      a.deleteSync();
      b.deleteSync();
    });

    test('不同内容 → 不同文件名，且保留各自扩展名', () async {
      final a = File('${Directory.systemTemp.path}/x.png')..writeAsBytesSync([1, 1]);
      final b = File('${Directory.systemTemp.path}/y.jpg')..writeAsBytesSync([2, 2]);
      final r1 = await AssetService.importImage(a);
      final r2 = await AssetService.importImage(b);

      expect(r1, isNot(equals(r2)), reason: '内容不同 → 文件名不同');
      expect(r1, endsWith('.png'));
      expect(r2, endsWith('.jpg'));

      final docsDir = await AssetService.documentsDir();
      expect(await File('$docsDir/$r1').exists(), isTrue);
      expect(await File('$docsDir/$r2').exists(), isTrue);

      a.deleteSync();
      b.deleteSync();
    });
  });
}
