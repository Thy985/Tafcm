/// AssetService：文档图片资产管理（ADR-0014 v1.2）。
///
/// 职责：把用户选择的图片复制到文档目录的 `assets/` 子文件夹，
/// 返回 Markdown 相对路径（`assets/img_<hash>.<ext>`）。
///
/// **命名策略（ADR-0014 v1.2 内容寻址）**：
/// `img_<sha256 前 16 位>.<原扩展名>`。同一图片重复插入时 hash 相同，
/// 天然去重（不重复复制），并为 Phase 4 云同步 / 增量同步 / 版本化
/// 提供稳定的内容标识（与 Git object / Docker layer digest 同思路）。
///
/// **格式策略（ADR-0014 v1.2）**：保留原始扩展名（不统一转 PNG），
/// 避免 jpg→png 体积膨胀与 gif/webp 动画丢失；仅接受 [supportedExtensions]
/// 白名单内的格式，其余拒绝并抛 [AssetImportException]。
///
/// **TC-ARCH-2 白名单说明**：本文件是资产文件 IO 的唯一入口
/// （`writeAsBytes` 仅此一处），与 FileRepository（文档 IO）平行，
/// 已登记 test/architecture/file_access_test.dart 白名单。
library;

import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 图片导入失败（用户可读 message + 开发者 detail 分离，风格同 ExportFailure）。
class AssetImportException implements Exception {
  /// 面向用户的简短消息（不含路径 / stack）。
  final String message;

  /// 开发者排查细节（原始异常字符串等）。
  final String? detail;

  const AssetImportException(this.message, {this.detail});

  @override
  String toString() => 'AssetImportException: $message'
      '${detail == null ? '' : ' ($detail)'}';
}

/// 文档图片资产服务（ADR-0014）。
class AssetService {
  AssetService._();

  /// 单张图片体积上限（字节）。手机原图通常 3-10MB，20MB 已覆盖
  /// 绝大多数拍摄场景；超限拒绝导入（全量读内存 + 落盘的保护阈值）。
  static const int maxAssetBytes = 20 * 1024 * 1024;

  /// 支持的图片扩展名白名单（ADR-0014 v1.2：保留原格式，不支持则拒绝）。
  static const Set<String> supportedExtensions = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp',
  };

  /// 文档存储基目录（`<AppDocuments>/documents`），与 FileRepository 同根。
  static Future<String> documentsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'documents');
  }

  /// 从系统相册 / 文件选择器选一张图并导入 `assets/`。
  ///
  /// 返回 Markdown 相对路径；用户取消选择时返回 `null`。
  /// 选择器权限被拒 / 源文件不可读 / 超限 / 格式不支持时抛
  /// [AssetImportException]（由调用方决定 UI 反馈）。
  static Future<String?> pickAndImportImage() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.image);
    } catch (e) {
      throw AssetImportException('无法打开图片选择器', detail: e.toString());
    }
    final path = result?.files.single.path;
    if (path == null) return null; // 用户取消
    return importImage(File(path), docsDir: await documentsDir());
  }

  /// 把 [source] 复制到 `<docsDir>/assets/`，返回相对路径 `assets/<name>`。
  ///
  /// [docsDir] 显式注入（生产传 [documentsDir]，测试传临时目录，
  /// 避免单测依赖 path_provider 平台通道）。
  ///
  /// 失败场景统一抛 [AssetImportException]：
  /// - 源文件不存在 / 不可读（选择后被删除等）
  /// - 体积超过 [maxAssetBytes]
  /// - 扩展名不在 [supportedExtensions]
  /// - 目标目录创建 / 写入失败（磁盘满等）
  static Future<String> importImage(
    File source, {
    required String docsDir,
  }) async {
    final ext = p.extension(source.path).toLowerCase().replaceAll('.', '');
    if (!supportedExtensions.contains(ext)) {
      throw AssetImportException('不支持的图片格式：.$ext');
    }

    final List<int> bytes;
    try {
      final length = await source.length();
      if (length > maxAssetBytes) {
        throw const AssetImportException(
          '图片超过 ${maxAssetBytes ~/ (1024 * 1024)}MB 上限',
        );
      }
      bytes = await source.readAsBytes();
    } on AssetImportException {
      rethrow;
    } catch (e) {
      throw AssetImportException('图片读取失败', detail: e.toString());
    }

    final hash = sha256.convert(bytes).toString().substring(0, 16);
    final name = 'img_$hash.$ext';
    try {
      final assetsDir = Directory(p.join(docsDir, 'assets'));
      await assetsDir.create(recursive: true);
      final target = File(p.join(assetsDir.path, name));
      // 内容寻址去重：同 hash 文件已存在则跳过复制。
      if (!await target.exists()) {
        await target.writeAsBytes(bytes);
      }
    } catch (e) {
      throw AssetImportException('图片保存失败', detail: e.toString());
    }
    return 'assets/$name';
  }
}
