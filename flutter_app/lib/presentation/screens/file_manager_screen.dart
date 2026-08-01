/// 文件管理 / 文档列表页（设计稿 `files.html`）。
///
/// 经 [fileRepositoryProvider] + [documentListProvider] 取文档列表（不再
/// 直连 [Directory]），按 `updatedAt` 倒序展示；消费 [EditorTokens]，底部无
/// TabBar（Shell 层统一渲染，见 ADR-0018）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/file_repository_provider.dart';
import '../theme/app_typography.dart';
import '../themes/editor_tokens.dart';
import '../../data/models/document.dart';

class FileManagerScreen extends ConsumerWidget {
  const FileManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentListProvider);
    final tokens = EditorTokens.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('文件',
            style: TextStyle(
              fontFamily: AppTypography.serif,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            )),
      ),
      body: docsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载失败', style: TextStyle(color: tokens.textSecondary)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(documentListProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (docs) => docs.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open_outlined,
                        size: 56, color: tokens.textSecondary.withOpacity(0.6)),
                    const SizedBox(height: 14),
                    Text('暂无保存的文档',
                        style: TextStyle(color: tokens.textSecondary, fontSize: 15)),
                    const SizedBox(height: 6),
                    Text('在编辑器中保存文档后将显示在此处',
                        style: TextStyle(color: tokens.textSecondary, fontSize: 13)),
                  ],
                ),
              )
<<<<<<< HEAD
            : SafeArea(
                top: false,
                bottom: true,
                child: ListView.separated(
                  itemCount: docs.length,
=======
            : ListView.separated(
                itemCount: docs.length,
>>>>>>> f60831d (补 0010-SKIPPED 编号纪律占位，新增 ADR-0021 Repository Integrity Strategy v1.4)
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: tokens.borderDefault.withOpacity(0.5)),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final preview = _preview(doc);
                  return InkWell(
                    onTap: () => _openDoc(ref, doc, context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.description_outlined,
                              color: tokens.textPrimary.withOpacity(0.6)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(doc.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppTypography.serif,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: tokens.textPrimary,
                                    )),
                                const SizedBox(height: 2),
                                Text(preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12, color: tokens.textSecondary)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: tokens.textPrimary.withOpacity(0.4)),
                            onPressed: () => _deleteDoc(ref, doc, context),
                          ),
                        ],
                      ),
                    ),
                  );
                },
<<<<<<< HEAD
                ),
=======
>>>>>>> f60831d (补 0010-SKIPPED 编号纪律占位，新增 ADR-0021 Repository Integrity Strategy v1.4)
              ),
      ),
    );
  }

  String _preview(Document doc) {
    final lines = doc.content.split('\n');
    final first = lines.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return first.length > 60 ? '${first.substring(0, 60)}...' : first;
  }

  Future<void> _openDoc(WidgetRef ref, Document doc, BuildContext context) async {
    final repo = ref.read(fileRepositoryProvider);
    final path = await repo.documentPathFor(doc.id);
    if (context.mounted) context.go('/editor?path=${Uri.encodeComponent(path)}');
  }

  Future<void> _deleteDoc(WidgetRef ref, Document doc, BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除「${doc.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final repo = ref.read(fileRepositoryProvider);
      final path = await repo.documentPathFor(doc.id);
      await repo.deleteDocument(path);
    }
  }
}
