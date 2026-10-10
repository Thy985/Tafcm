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
import '../widgets/doc_list_subtitle.dart';
import '../../data/models/document.dart';
import 'doc_actions.dart';

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
        // issue #338：文件页是应用的主实体列表页，却不能在自身发起新建/导入，
        // 用户必须跨 Tab 回首页才能发起。补 AppBar 操作入口（与首页 _Header 一致）。
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入 .md 文件',
            onPressed: () => openAnyMd(ref, context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建文档',
            onPressed: () => newDoc(ref, context),
          ),
        ],
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
                    Text('暂无保存的文件',
                        style: TextStyle(color: tokens.textSecondary, fontSize: 15)),
                    const SizedBox(height: 6),
                    Text('点右上角按钮新建，或导入已有的 .md',
                        style: TextStyle(color: tokens.textSecondary, fontSize: 13)),
                  ],
                ),
              )
            : SafeArea(
                top: false,
                bottom: true,
                child: ListView.separated(
                  itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: tokens.borderDefault.withOpacity(0.5)),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  // issue #333-C：同名碰撞时副标题加创建时间前缀（种子文档
                  // 标题不重复 → 不触发 → golden 不变；真实同名才出现）。
                  final subtitle = disambiguatedSubtitle(doc, docs, _preview(doc));
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
                                Text(subtitle,
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
                ),
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
    // P1 修复（2026-08-09）：用 context.go 替代 context.push，使 /editor 脱离
    // StatefulShellRoute，消除编辑器底部常驻的 HomeBottomBar（首页/文件/阅读/我的）。
    // 返回按钮在 canPop()=false 时兜底 go('/home')，回到首页。
    if (context.mounted) context.go('/editor?path=${Uri.encodeComponent(path)}');
  }

  Future<void> _deleteDoc(WidgetRef ref, Document doc, BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除「${doc.title}」（创建于 ${formatDateTimeShort(doc.createdAt)}）吗？'),
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
