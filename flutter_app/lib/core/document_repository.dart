/// 文档仓储端口（AGENTS.md §4.2：presentation 经 providers/ 访问，禁止直连 core/services）。
///
/// [FileRepository] 实现本端口；[fileRepositoryProvider]（位于 providers/）以本类型
/// 暴露，使 presentation 层无需 import `core/services/*Service` 即可写盘 / 列表。
library;

import '../data/models/document.dart';

/// 文档 I/O 的抽象端口（单一入口，业务层禁止直写 [File]）。
abstract class DocumentRepository {
  /// 由文档 id 推导规范化路径。
  Future<String> documentPathFor(String id);

  /// 列出全部文档元数据。
  Future<List<Document>> listDocuments();

  /// 读取指定路径的文档。
  Future<Document> readDocument(String path);

  /// 新建文档：生成 uuid 文件名，返回路径。
  Future<String> createDocument(String title, String content);

  /// 写入（upsert）：保留已有 id / createdAt，刷新 updatedAt。
  Future<void> writeDocument(String path,
      {required String title, required String content});

  /// 删除指定路径的文档。
  Future<void> deleteDocument(String path);

  /// 重命名：仅替换正文首个 `# H1`，路径（uuid）不变。
  Future<void> renameDocument(String path, String newTitle);

  /// 监听文档列表（全量 [Document]），目录变更时自动重发。
  ///
  /// 供首页 / 文件页共享（见 `documentListProvider`），使任一屏的创建 / 删除经
  /// 文件系统事件自动刷新另一屏，避免两屏各持一份数据源导致的不一致。
  Stream<List<Document>> watchAllDocuments();

  /// 获取文档预览片段（≤ 40 字符），不加载全量 AST。
  Future<String> getDocumentPreview(String id);
}
