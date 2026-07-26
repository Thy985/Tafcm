/// 文档仓储 Provider（presentation 安全入口，AGENTS.md §4.2）。
///
/// 以 [DocumentRepository] 端口类型暴露 [FileRepository]，presentation 层据此调用
/// 写盘 / 列表等方法而无需 import `core/services/*Service`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/document_repository.dart';
import '../core/services/file_repository.dart';

export '../core/document_repository.dart' show DocumentRepository;

final fileRepositoryProvider = Provider<DocumentRepository>((ref) => FileRepository());
