/// 文档仓储 Provider（presentation 安全入口，AGENTS.md §4.2）。
///
/// 以 [DocumentRepository] 端口类型暴露 [FileRepository]，presentation 层据此调用
/// 写盘 / 列表等方法而无需 import `core/services/*Service`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/document_repository.dart';
import '../core/services/file_repository.dart';
import '../data/models/document.dart';

export '../core/document_repository.dart' show DocumentRepository;

final fileRepositoryProvider = Provider<DocumentRepository>((ref) => FileRepository());

/// 共享文档列表（全量 [Document] 流）。
///
/// 首页与文件页均消费本 Provider，而非各自直读文件系统，保证两屏数据一致；
/// [FileRepository.watchAllDocuments] 在目录变更时自动重发，使任一屏的创建 /
/// 删除自动刷新另一屏（见 AGENTS.md §4.2 / TC-ARCH-1/2 文件 I/O allowlist）。
final documentListProvider = StreamProvider<List<Document>>((ref) {
  final repo = ref.watch(fileRepositoryProvider);
  return repo.watchAllDocuments();
});

/// 「最近」文档（≤ 3 篇）—— Provider 层过滤，UI 不做业务切片（ADR-0018 D2）。
final recentDocumentsProvider = Provider<List<Document>>((ref) {
  final docs = ref.watch(documentListProvider).valueOrNull ?? [];
  return docs.take(3).toList();
});

/// 「更早」文档（> 3 篇以后）—— Provider 层切片。
final earlierDocumentsProvider = Provider<List<Document>>((ref) {
  final docs = ref.watch(documentListProvider).valueOrNull ?? [];
  return docs.skip(3).toList();
});
