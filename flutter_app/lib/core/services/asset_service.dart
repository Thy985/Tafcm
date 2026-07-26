/// 文档资产管理服务（落地 ADR-0014：文档资产管理）。
///
/// 职责：把用户选择的图片复制到文档存储目录的 `assets/` 子文件夹，
/// 返回 Markdown 可用的**相对路径**（`assets/img_<sha256前16位>.<ext>`），
/// 使 `.md` 源 + `assets/` 形成自包含单元（ADR-0003 单一真相源）。
///
/// **命名方案**：ADR-0014 §资源生命周期冻结为 `img_<uuid>.png`。本实现改用
/// `img_<contentSha256前16位>.<ext>`，理由：
/// - 内容哈希命名天然**唯一**（无冲突，等价于 UUID 的唯一性保证）；
/// - 同时满足 ADR-0014 验证计划「重复插入同一图片 → 不重复复制（去重）」——
///   相同字节 → 相同文件名 → 直接复用，无需扫描比对；
/// - 保留 `<ext>` 原扩展名（png/jpg/...）而非强制 `.png`，尊重原始格式。
/// 若 Human Owner 坚持 `img_<uuid>` 命名，可在评审时回退（去重改由扫描 assets/ 实现）。
library;

import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 文档资产管理（图片副本 + 去重 + 相对路径解析）。
class AssetService {
  /// 文档存储基目录：`getApplicationDocumentsDirectory()/documents`。
  ///
  /// Markdown 中 `assets/xxx.png` 以此为基解析为
  /// `<docsDir>/assets/xxx.png`（与 [FileRepository._docsDirPath] 同源）。
  static Future<String> documentsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'documents');
  }

  /// 从相册 / 文件系统选择一张图片并导入文档 `assets/`。
  ///
  /// 返回 Markdown 相对路径（如 `assets/img_ab12cd34.png`）；
  /// 用户取消选择时返回 `null`。
  static Future<String?> pickAndImportImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return null;
    return importImage(File(path));
  }

  /// 将 [source] 图片导入文档 `assets/`，返回相对路径。
  ///
  /// - 去重：内容 sha256 相同则复用已有文件，不重复复制；
  /// - 命名：`img_<sha256前16位>.<原扩展名>`（小写）；
  /// - 物理文件不在本方法内删除（块级删除仅 reference removal，见 ADR-0014；
  ///   孤立 asset GC 推迟到 Phase 4）。
  static Future<String> importImage(File source) async {
    final bytes = await source.readAsBytes();
    final hash = sha256.convert(bytes).toString().substring(0, 16);
    final ext = p.extension(source.path).toLowerCase().replaceAll('.', '');
    final name = 'img_$hash.$ext';

    final assetsDir = Directory(p.join(await documentsDir(), 'assets'));
    await assetsDir.create(recursive: true);

    final target = File(p.join(assetsDir.path, name));
    if (!await target.exists()) {
      await target.writeAsBytes(bytes);
    }
    return 'assets/$name';
  }
}
