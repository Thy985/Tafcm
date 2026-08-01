import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/document.dart';
import '../document_repository.dart';
import 'file_service.dart' show decodeBytesAuto;
import 'front_matter_parser.dart';

/// 文档元数据（不含正文），用于列表 / 元数据查询 / 搜索 / 监听。
///
/// 与 [Document] 的区别在于不携带 `content`，避免大文件全量加载。
class DocMetadata {
  final String id;
  final String path;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DocMetadata({
    required this.id,
    required this.path,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// 文档存储的单一入口（见 ADR-0003 §边界约束 1/2/6）。
///
/// 所有文档 I/O 必须经过本 Repository；业务层禁止直写 [File]。
/// 内部统一使用 [atomicWrite]（tmp → 删除旧目标 → rename）保证原子性。
/// 以 [DocumentRepository] 端口类型实现，[fileRepositoryProvider] 位于 providers/
/// （presentation 经其访问，不直连本文件）。
class FileRepository implements DocumentRepository {
  @visibleForTesting
  String? testDocsDir;

  Future<String> _docsDirPath() async {
    if (testDocsDir != null) return testDocsDir!;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}documents';
  }

  /// 由文档 id（= .md 文件名 stem）推导规范化路径。
  @override
  Future<String> documentPathFor(String id) async =>
      '${await _docsDirPath()}${Platform.pathSeparator}$id.md';

  ({Document doc, String path}) _parseEntry(
    String path,
    String raw,
    DateTime fallbackModified,
  ) {
    final parsed = FrontMatterParser.parse(raw);
    final meta = parsed.meta;
    final body = parsed.body;
    final id =
        (meta?['id']?.isNotEmpty == true) ? meta!['id']! : _stem(path);
    final createdAt = _parseDate(meta?['createdAt']) ?? fallbackModified;
    final updatedAt = _parseDate(meta?['updatedAt']) ?? fallbackModified;
    final title = _extractTitle(body) ?? '未命名文档';
    final doc = Document(
      id: id,
      title: title,
      content: body,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    return (doc: doc, path: path);
  }

  Future<List<({Document doc, String path})>> _readAll() async {
    final docsDir = Directory(await _docsDirPath());
    if (!await docsDir.exists()) return [];
    final files = docsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    final entries = <({Document doc, String path})>[];
    for (final f in files) {
      final raw = decodeBytesAuto(await f.readAsBytes());
      final stat = await f.stat();
      entries.add(_parseEntry(f.path, raw, stat.modified));
    }
    entries.sort((a, b) => b.doc.updatedAt.compareTo(a.doc.updatedAt));
    return entries;
  }

  DocMetadata _toMeta(({Document doc, String path}) e) => DocMetadata(
        id: e.doc.id,
        path: e.path,
        title: e.doc.title,
        createdAt: e.doc.createdAt,
        updatedAt: e.doc.updatedAt,
      );

  // ---- CRUD ----

  @override
  Future<List<Document>> listDocuments() async =>
      (await _readAll()).map((e) => e.doc).toList();

  @override
  Future<Document> readDocument(String path) async {
    final file = File(path);
    final raw = decodeBytesAuto(await file.readAsBytes());
    final stat = await file.stat();
    return _parseEntry(path, raw, stat.modified).doc;
  }

  /// 新建文档：生成 uuid 文件名，写入带 front matter 的 .md，返回路径。
  @override
  Future<String> createDocument(String title, String content) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final path = await documentPathFor(id);
    final md = FrontMatterParser.build(
      id: id,
      createdAt: now,
      updatedAt: now,
      title: title,
      content: content,
    );
    await atomicWrite(File(path), md);
    return path;
  }

  /// 写入（upsert）：保留已有 id / createdAt，刷新 updatedAt。
  /// 正文原样透传（含用户写入的 `# H1`），不重复注入标题。
  @override
  Future<void> writeDocument(
    String path, {
    required String title,
    required String content,
  }) async {
    final file = File(path);
    String id;
    DateTime createdAt;
    if (await file.exists()) {
      final raw = decodeBytesAuto(await file.readAsBytes());
      final meta = FrontMatterParser.parse(raw).meta;
      id = (meta?['id']?.isNotEmpty == true) ? meta!['id']! : _stem(path);
      createdAt = _parseDate(meta?['createdAt']) ?? DateTime.now();
    } else {
      id = const Uuid().v4();
      createdAt = DateTime.now();
    }
    final updatedAt = DateTime.now();
    final md = FrontMatterParser.build(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      title: title,
      content: content,
    );
    await atomicWrite(File(path), md);
  }

  @override
  Future<void> deleteDocument(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// 重命名：仅替换正文首个 `# H1`，路径（uuid）不变。
  @override
  Future<void> renameDocument(String path, String newTitle) async {
    final file = File(path);
    final raw = decodeBytesAuto(await file.readAsBytes());
    final body = FrontMatterParser.parse(raw).body;
    final newBody = _replaceFirstH1(body, newTitle);
    await writeDocument(path, title: newTitle, content: newBody);
  }

  // ---- 扩展 API（ADR-0003 §边界约束 6） ----

  Future<DocMetadata> getMetadata(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Document not found', path);
    }
    final raw = decodeBytesAuto(await file.readAsBytes());
    final stat = await file.stat();
    return _toMeta((doc: _parseEntry(path, raw, stat.modified).doc, path: path));
  }

  Stream<List<DocMetadata>> watchDocuments() async* {
    final dir = Directory(await _docsDirPath());
    if (!await dir.exists()) {
      yield const [];
      await dir.create(recursive: true);
    }
    await for (final _ in dir.watch(
      events: FileSystemEvent.create |
          FileSystemEvent.delete |
          FileSystemEvent.modify |
          FileSystemEvent.move,
    )) {
      yield await _listMetadata();
    }
  }

  @override
  Stream<List<Document>> watchAllDocuments() async* {
    final dir = Directory(await _docsDirPath());
    if (!await dir.exists()) {
      yield const [];
      await dir.create(recursive: true);
    }
    // 首屏立即返回当前列表，后续目录事件重发。
    yield await listDocuments();
    while (true) {
      try {
        await for (final _ in dir.watch(
          events: FileSystemEvent.create |
              FileSystemEvent.delete |
              FileSystemEvent.modify |
              FileSystemEvent.move,
        )) {
          yield await listDocuments();
        }
      } catch (e) {
        debugPrint('[FileRepository] watchAllDocuments error (will retry): $e');
        yield await listDocuments(); // 重连前发一次当前状态
        await Future.delayed(const Duration(seconds: 3)); // 退避
      }
    }
  }

  @override
  Future<String> getDocumentPreview(String id) async {
    final path = await documentPathFor(id);
    final file = File(path);
    if (!await file.exists()) return ''; // 优雅降级
    // 流式读取，找到首非空行即停止（避免大文件全量加载）
    final stream = file.openRead().transform(utf8.decoder).transform(const LineSplitter());
    String? firstLine;
    await for (final line in stream) {
      if (line.trim().isNotEmpty) {
        firstLine = line;
        break;
      }
    }
    final text = firstLine ?? '';
    return text.length > 40
        ? '${text.substring(0, 40)}\u2026'
        : text;
  }

  Future<List<DocMetadata>> searchDocuments(String query) async {
    final q = query.toLowerCase();
    final entries = await _readAll();
    if (q.isEmpty) return entries.map(_toMeta).toList();
    return entries
        .where((e) =>
            e.doc.title.toLowerCase().contains(q) ||
            e.doc.content.toLowerCase().contains(q))
        .map(_toMeta)
        .toList();
  }

  Future<bool> exists(String path) async => File(path).exists();

  // ---- 内部工具 ----

  Future<List<DocMetadata>> _listMetadata() async =>
      (await _readAll()).map(_toMeta).toList();

  String _stem(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    return name.endsWith('.md')
        ? name.substring(0, name.length - 3)
        : name;
  }

  DateTime? _parseDate(String? s) {
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } on FormatException {
      return null;
    }
  }

  String? _extractTitle(String body) {
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (t.startsWith('# ')) return t.substring(2).trim();
    }
    return null;
  }

  String _replaceFirstH1(String body, String newTitle) {
    final lines = body.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('# ')) {
        lines[i] = '# $newTitle';
        return lines.join('\n');
      }
    }
    return '# $newTitle\n\n$body';
  }
}

/// [atomicWrite] 遇可恢复的文件系统错误时的最大尝试次数（含首次）。
const int kAtomicWriteMaxAttempts = 3;

/// [atomicWrite] 重试的基础退避间隔，第 n 次重试等待 n × 该值。
const Duration kAtomicWriteRetryBackoff = Duration(milliseconds: 20);

/// 原子写：先写 `<path>.tmp`，落盘后（删除旧目标）rename 到最终路径。
///
/// 避免进程崩溃 / 写入中断时留下半截 `.md`。Windows 上 `rename`
/// 不能直接覆盖已存在文件，故先删除旧目标再 rename。
///
/// **抗外部干扰**：`.tmp` 落盘到 rename 之间存在一个时间窗，期间可能被
/// 外部进程（磁盘清理工具、杀毒软件实时扫描、同步客户端）删除或占用，
/// 导致 rename 抛 [FileSystemException]（Windows 上典型为
/// `errno = 2 / 32`）。这类故障是瞬时的，整段"写 tmp → 删旧 → rename"
/// 会最多重试 [kAtomicWriteMaxAttempts] 次、按 [kAtomicWriteRetryBackoff]
/// 线性退避。非文件系统异常（如编码错误）不重试，立即上抛。
///
/// 重试语义安全：每次尝试都重新写入完整的 [content]，
/// 不存在写入一半再续写的情况；失败路径始终清理残留 `.tmp`。
///
/// ⚠️ 权衡（delete-then-rename）：每次尝试会先删除已存在的旧目标再 rename，
/// 若 rename 持续失败并耗尽重试上限，旧内容将丢失（新内容也未落盘）。属设计固有
/// 权衡，非本处回归；该行为已由 `atomic_write_test` 固化，便于后续若改为
/// "写临时件、失败时保留旧件"时及时察觉。
Future<void> atomicWrite(File file, String content) async {
  final dir = file.parent;
  await dir.create(recursive: true);
  final tmp = File('${file.path}.tmp');

  for (var attempt = 1; attempt <= kAtomicWriteMaxAttempts; attempt++) {
    try {
      await tmp.writeAsString(content, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
      return;
    } on FileSystemException catch (e, s) {
      await _deleteQuietly(tmp);
      if (attempt == kAtomicWriteMaxAttempts) {
        // 重试耗尽：保留原始栈上抛，便于定位外部干扰源（清理器/杀毒锁定等）。
        Error.throwWithStackTrace(e, s);
      }
      await Future<void>.delayed(kAtomicWriteRetryBackoff * attempt);
    } catch (_) {
      // 非文件系统错误不具备"重试可恢复"性质，直接上抛。
      await _deleteQuietly(tmp);
      rethrow;
    }
  }
}

/// 尽力删除 [file]，忽略删除过程中的任何错误（清理路径不得掩盖原始异常）。
Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // 残留 .tmp 由下次写入覆盖，或由 recovery 流程清理。
  }
}
