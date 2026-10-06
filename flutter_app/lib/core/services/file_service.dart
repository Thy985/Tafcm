import 'dart:convert';
import 'dart:io';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// GBK codec（#320）：Dart VM / Flutter 不内置 `gb18030`/`gbk`
/// （`Encoding.getByName` 返回 null，旧代码因此整条 GBK 路径是死代码），
/// 引入纯 Dart 的 fast_gbk 补齐解码 / 编码。
const GbkCodec _kGbk = GbkCodec();

/// 统计 [text] 中的 U+FFFD 数量（容错解码的损坏信号）。
int _countReplacementChars(String text) {
  var count = 0;
  for (final rune in text.runes) {
    if (rune == 0xFFFD) count++;
  }
  return count;
}

/// 是否包含 CJK 字符（汉字 / CJK 标点 / 全角符号 / GBK 私有区）。
///
/// 用于 #320 的 GBK 采纳判定：GBK 双字节解码出的中文落在这些区段；
/// 若 GBK 解码结果一个 CJK 都没有，说明字节流大概率真不是 GBK。
bool _containsCjk(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x4E00 && rune <= 0x9FFF) || // CJK 统一表意文字
        (rune >= 0x3400 && rune <= 0x4DBF) || // 扩展 A
        (rune >= 0x3000 && rune <= 0x303F) || // CJK 标点
        (rune >= 0xFF00 && rune <= 0xFFEF) || // 全角 Forms
        (rune >= 0xE000 && rune <= 0xF8FF)) {
      // GBK 映射的 PUA 区
      return true;
    }
  }
  return false;
}

/// 把任意来源的字节流尝试解析为字符串。优先级：
///   1. UTF-8 BOM / 严格 UTF-8
///   2. 容错 UTF-8（U+FFFD 替换非法序列）零损坏 → 按 UTF-8 返回——
///      覆盖「GBK 双字节恰好构成合法 UTF-8」的 `C7 A7`（→ ǧ）场景，
///      合法 UTF-8 字节流绝不被误判为 GBK
///   3. GBK（fast_gbk，覆盖 GB2312 / GBK 及 GB18030 双字节区）：仅当
///      容错 UTF-8 有损坏（U+FFFD > 0）**且** GBK 能**零损坏**解码且
///      产出含 CJK 时才采纳——GBK 完整解释了全部字节而 UTF-8 解释存在
///      结构性损坏，字节证据压倒性偏向 GBK（中文 Windows 记事本默认编码）。
///      GBK 自身也解不干净（罕见 GB18030 四字节区）时维持 UTF-8 容错
///      结果 + U+FFFD 告警（`containsReplacementChar`），用户可经
///      front matter `encoding:` 声明或 UI 手动指定重解码。
///   4. Latin-1（兜底，1:1 字节到字符映射，永不失败；见下方 latin1 分支）
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
  // 容错 UTF-8：保证不抛错。
  final utf8Tolerant = utf8.decode(bytes, allowMalformed: true);
  final utf8Damage = _countReplacementChars(utf8Tolerant);
  if (utf8Damage == 0) return utf8Tolerant;
  // GBK 兜底判定（#320）：容错 UTF-8 永不抛错，旧版在此直接返回导致
  // GBK 分支不可达（死代码）——必须在「UTF-8 有损坏」时主动比较两种解释。
  try {
    final gbkTolerant = _kGbk.decode(bytes, allowMalformed: true);
    if (_countReplacementChars(gbkTolerant) == 0 && _containsCjk(gbkTolerant)) {
      return gbkTolerant;
    }
  } on FormatException {
    // GBK 解码器异常 → 维持 UTF-8 容错结果
  }
  return utf8Tolerant;
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
        // #320：`Encoding.getByName('gb18030')` 在 VM/Flutter 均为 null
        // （dart:convert 不内置），旧实现实际恒降级 latin1（乱码）。
        // 统一走 fast_gbk；编码失败（罕见不可映射字符）退 latin1 兜底。
        return _kGbk.decode(bytes, allowMalformed: true);
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
        // #320：同 decode——fast_gbk 补齐写路径（旧实现 getByName null →
        // 恒走 _encodeLatin1Fallback，中文写盘即 '??' 乱码）。
        // fast_gbk 对不可映射字符内部替换为 GBK 替换码，encode 永不抛。
        return _kGbk.encode(text);
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
