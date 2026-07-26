/// FileTreePanel：文件树侧栏（Phase 3.4.2）。
///
/// 列出 .md 文档（列表由 EditorShell 经 [documentsProvider] 传入，单一领域来源
/// [DocumentRepository]，不直读 File），点击触发 onOpenFile(doc.id) 由 EditorShell
/// 负责解析路径并打开文档。
///
/// **纯展示层**（Human Owner 决策，契约 §9.3）：
/// - 不直接读文件 / 不碰 AST / 不调 DocumentEditor
/// - FileManagerScreen 保留作 `/files` 独立浏览入口；两者共享 DocumentRepository，
///   不复制文件管理逻辑（领域逻辑单一）。
/// - UI 两处入口，领域逻辑单一。
///
/// 依赖方向：仅 import [data/models/document.dart]（与 TocPanel 一致），不 import
/// chrome/ / blocks/ / providers/。
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/document.dart';

/// 文件树侧栏：列出文档，点击触发 onOpenFile(doc.id)。
class FileTreePanel extends StatelessWidget {
  /// 文档列表（由 EditorShell 经 documentsProvider 传入）。
  final List<Document> documents;

  /// 当前打开文档的路径（用于高亮）；为 null 不高亮。
  final String? currentPath;

  /// 点击某文档的回调，参数为该文档的 [Document.id]（路径由 EditorShell 解析）。
  final ValueChanged<String>? onOpenFile;

  const FileTreePanel({
    super.key,
    required this.documents,
    this.currentPath,
    this.onOpenFile,
  });

  /// 从当前路径推导文档 id（uuid 文件名 stem），用于高亮匹配。
  String? _currentId() {
    if (currentPath == null) return null;
    final name = currentPath!.split(RegExp(r'[/\\]')).last;
    return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
  }

  String _formatDate(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm').format(dt);

  @override
  Widget build(BuildContext context) {
    final currentId = _currentId();
    final linkColor = Theme.of(context).colorScheme.primary;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Text('文件', style: Theme.of(context).textTheme.titleLarge),
          ),
          const Divider(height: 1),
          Expanded(
            child: documents.isEmpty
                ? const Center(
                    child: Text('（暂无文档）', style: TextStyle(fontSize: 14)),
                  )
                : ListView.builder(
                    itemCount: documents.length,
                    itemBuilder: (context, index) {
                      final doc = documents[index];
                      final isCurrent = doc.id == currentId;
                      return ListTile(
                        leading: Icon(
                          Icons.description,
                          color: isCurrent ? linkColor : null,
                        ),
                        title: Text(
                          doc.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _formatDate(doc.updatedAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: isCurrent,
                        selectedTileColor: linkColor.withValues(alpha: 0.12),
                        onTap: () => onOpenFile?.call(doc.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
