import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 把任意来源的字节流尝试解析为字符串。优先级：
///   1. UTF-8 BOM / 严格 UTF-8
///   2. UTF-8 容错模式（用 U+FFFD 替换非法序列）— 在中国用户的 .md 文件里
///      GBK / GB18030 字节序列混入 UTF-8 流中很常见，严格模式会抛
///      "Unexpected extension byte"，容错模式可以挽救大部分内容。
///   3. GBK（覆盖 GB2312 / GB18030 的子集）— 中文 Windows 记事本默认编码
///   4. Latin-1（兜底，1:1 字节到字符映射，永不失败）
String decodeBytesAuto(List<int> bytes) {
  if (bytes.isEmpty) return '';
  // BOM 探测
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  // 严格 UTF-8 试一次
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 继续尝试更宽松的解码器
  }
  // 容错 UTF-8：保证不抛错，对 GBK 字节也基本能恢复出可读文本
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } on FormatException {
    // 极小概率走到这
  }
  // GBK / GB18030：覆盖中文 Windows 记事本默认编码。某些 Flutter SDK
  // 不在 dart:convert 顶层直接导出 `gb18030`，但可以通过
  // `Encoding.getByName('gb18030')` 拿到。拿不到时退到 latin1 兜底。
  try {
    final gbk = Encoding.getByName('gb18030') ?? Encoding.getByName('gbk');
    if (gbk != null) return gbk.decode(bytes);
  } on FormatException {
    // 最后兜底
  }
  return latin1.decode(bytes);
}

/// P0-2 编码手动指定（EXTERNAL-PROJECTS-EMPOWERMENT-PLAN §4.2）：
/// 用户可选的文本编码白名单。Big5 依赖运行时 `Encoding.getByName`
 /// 是否可用（dart:convert 不内置），不可用时解码降级 Latin-1。
///
/// 枚举内裸名 `utf8`/`latin1` 会被同名枚举值遮蔽（解析为
/// TextEncoding.utf8.decode → 递归自身），编解码一律走顶层常量。
const Utf8Codec _kUtf8 = Utf8Codec();

/// latin1 兜底：SDK `Latin1Codec` 的 allowInvalid 只作用于 decoder
/// （encoder 永远拒绝非 Latin-1 字符，见 sky_engine convert/latin1.dart
/// ：34 "Encoders will not accept invalid characters"）——编码兜底需手动
/// 映射：>0xFF 码点替换为 `?`，保证降级路径写中文不抛异常。
List<int> _encodeLatin1Fallback(String text) => text
    .codeUnits
    .map((c) => c > 0xFF ? 0x3F : c)
    .toList();

/// latin1 解码用顶层常量——枚举体内裸名 `latin1` 会被同名枚举值遮蔽
/// （`TextEncoding.latin1.decode` = 递归自身，栈溢出）。
const Latin1Codec _kLatin1Decode = Latin1Codec(allowInvalid: true);

enum TextEncoding {
  utf8('UTF-8'),
  gb18030('GB18030'),
  big5('Big5'),
  latin1('Latin-1');

  final String label;
  const TextEncoding(this.label);

  /// 解码 [bytes]；Big5 运行时不可用时降级 Latin-1（永不抛格式异常：
  /// latin1 是 1:1 字节映射兜底）。
  String decode(List<int> bytes) {
    switch (this) {
      case TextEncoding.utf8:
        // BOM 剥离 + 容错，与 decodeBytesAuto 的 utf8 分支同语义。
        if (bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF) {
          return _kUtf8.decode(bytes.sublist(3), allowMalformed: true);
        }
        return _kUtf8.decode(bytes, allowMalformed: true);
      case TextEncoding.gb18030:
        final enc =
            Encoding.getByName('gb18030') ?? Encoding.getByName('gbk');
        if (enc != null) return enc.decode(bytes);
        return latin1.decode(bytes);
      case TextEncoding.big5:
        final enc = Encoding.getByName('big5');
        if (enc != null) return enc.decode(bytes);
        return _kLatin1Decode.decode(bytes);
      case TextEncoding.latin1:
        return _kLatin1Decode.decode(bytes);
    }
  }

  /// 编码 [text] 为字节（写回路径）；Big5 不可用时降级 Latin-1。
  List<int> encode(String text) {
    switch (this) {
      case TextEncoding.utf8:
        return _kUtf8.encode(text);
      case TextEncoding.gb18030:
        final enc =
            Encoding.getByName('gb18030') ?? Encoding.getByName('gbk');
        if (enc != null) return enc.encode(text);
        return _encodeLatin1Fallback(text);
      case TextEncoding.big5:
        final enc = Encoding.getByName('big5');
        if (enc != null) return enc.encode(text);
        return _encodeLatin1Fallback(text);
      case TextEncoding.latin1:
        return _encodeLatin1Fallback(text);
    }
  }

  /// 从 front matter 声明值（如 `gb18030`）解析；未知值返回 null（走自动链）。
  static TextEncoding? tryParse(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'utf-8':
      case 'utf8':
        return TextEncoding.utf8;
      case 'gb18030':
      case 'gbk':
      case 'gb2312':
        return TextEncoding.gb18030;
      case 'big5':
        return TextEncoding.big5;
      case 'latin-1':
      case 'latin1':
      case 'iso-8859-1':
        return TextEncoding.latin1;
      default:
        return null;
    }
  }
}

/// 检测解码结果是否含 U+FFFD（容错解码痕迹 = 自动判定可能出错，
/// 规划 §4.2 方案 1：UI 据此提示"编码异常"并让用户手动指定重解码）。
bool containsReplacementChar(String text) => text.contains('\uFFFD');

class FileService {
  /// 从系统文件选择器导入文件并解码为字符串。
  ///
  /// P1 修复（2026-08-06，phase3.5-realdevice-issues 问题 6A）：原用
  /// `FileType.custom + allowedExtensions:['md','txt','tex']`，file_picker 8.3.7
  /// 在 Android 上会把它转成 `Intent(type='*/*', EXTRA_MIME_TYPES=[...])`。
  /// 小米 HyperOS 的 SAF 实现对该配置过滤异常 → 弹窗完全空白（与 home_screen._openAnyMd
  /// 同一根因，详见 [home_screen.dart] _openAnyMd 注释）。改用 `FileType.any` 让 SAF
  /// 显示所有文件，Dart 层校验扩展名：非白名单时抛 [FileImportException]。
  ///
  /// 白名单：`md` / `txt` / `tex`。
  static Future<String> importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result == null || result.files.single.path == null) {
      throw FileImportException('No file selected or file is invalid');
    }

    final path = result.files.single.path!;
    // Dart 层扩展名校验（替代 FileType.custom 的 MIME 过滤，避免厂商 SAF 异常）。
    final lower = path.toLowerCase();
    if (!lower.endsWith('.md') &&
        !lower.endsWith('.txt') &&
        !lower.endsWith('.tex')) {
      throw FileImportException('仅支持 .md / .txt / .tex 文件');
    }

    final file = File(path);
    final bytes = await file.readAsBytes();
    return decodeBytesAuto(bytes);
  }

  /// [encoding]（P0-2 §4.2 方案 2）：非 null 时绕过自动链，用指定编码解码。
  static Future<String> loadFromPath(String path, {TextEncoding? encoding}) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (encoding != null) return encoding.decode(bytes);
      return decodeBytesAuto(bytes);
    } catch (e) {
      throw FileLoadException('Failed to load file: $path');
    }
  }

  static Future<String> saveToFile(String content, {String? filename}) async {
    if (content.isEmpty) {
      throw FileSaveException('Cannot save empty content');
    }
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = filename ?? 'tafcm_${DateTime.now().millisecondsSinceEpoch}.md';
      final file = File('${dir.path}/$name');
      await file.writeAsString(content);
      return file.path;
    } catch (e) {
      throw FileSaveException('Failed to save file: $e');
    }
  }

  static Future<List<FileSystemEntity>> listDocuments() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync()
          .where((f) => f.path.endsWith('.md') || f.path.endsWith('.txt'))
          .toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (e) {
      throw FileListException('Failed to list files: $e');
    }
  }

  static Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      throw FileDeleteException('Failed to delete file: $e');
    }
  }
}

class FileImportException implements Exception {
  final String message;
  FileImportException(this.message);
  @override
  String toString() => message;
}

class FileLoadException implements Exception {
  final String message;
  FileLoadException(this.message);
  @override
  String toString() => message;
}

class FileSaveException implements Exception {
  final String message;
  FileSaveException(this.message);
  @override
  String toString() => message;
}

class FileListException implements Exception {
  final String message;
  FileListException(this.message);
  @override
  String toString() => message;
}

class FileDeleteException implements Exception {
  final String message;
  FileDeleteException(this.message);
  @override
  String toString() => message;
}
