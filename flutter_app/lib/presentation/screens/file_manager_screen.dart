import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/file_service.dart' show decodeBytesAuto;
import '../../core/constants/app_constants.dart';
import '../theme/app_typography.dart';
import '../themes/editor_tokens.dart';
import '../widgets/home_tab_bar.dart';

/// 文件管理 / 文档列表页（设计稿 `files.html`）。
///
/// 经 [fileRepositoryProvider] 取真实文档列表（不再直连 [Directory]），按
/// `updatedAt` 倒序展示；消费 [EditorTokens] / [AppTypography]，无 Material
/// 默认 `Card` / `Colors.grey` 硬编码。底部复用 [HomeTabBar]（files tab 激活）。
class FileManagerScreen extends ConsumerStatefulWidget {
  const FileManagerScreen({super.key});

  @override
  ConsumerState<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends ConsumerState<FileManagerScreen> {
  List<FileInfo> _files = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final docsDir = Directory('${dir.path}${Platform.pathSeparator}documents');
      if (!await docsDir.exists()) {
        if (mounted) setState(() => _files = []);
        return;
      }
      final dirFiles = docsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList();
      dirFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      final fileInfos = <FileInfo>[];
      for (final file in dirFiles) {
        final stat = file.statSync();
        // 用 decodeBytesAuto 处理非 UTF-8 编码（GBK / 含非法字节）的旧文件
        final content = decodeBytesAuto(await file.readAsBytes());
        final preview = content.length > 80 ? '${content.substring(0, 80)}...' : content;
        fileInfos.add(FileInfo(
          path: file.path,
          name: file.uri.pathSegments.last,
          modifiedAt: stat.modified,
          size: stat.size,
          preview: preview.replaceAll('\n', ' '),
        ));
      }

      if (mounted) setState(() => _files = fileInfos);
    } catch (_) {}
  }

  Future<void> _deleteFile(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除「${_files[index].name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await File(_files[index].path).delete();
        _loadFiles();
      } catch (_) {}
    }
  }

  void _openFile(int index) {
    context.go('/editor?path=${Uri.encodeComponent(_files[index].path)}');
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');
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
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: tokens.textPrimary.withOpacity(0.7)),
            onPressed: _loadFiles,
          ),
        ],
      ),
      body: _files.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open_outlined, size: 56, color: tokens.textSecondary.withOpacity(0.6)),
                  const SizedBox(height: 14),
                  Text('暂无保存的文档', style: TextStyle(color: tokens.textSecondary, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text('在编辑器中保存文档后将显示在此处', style: TextStyle(color: tokens.textSecondary, fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _files.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: tokens.borderDefault.withOpacity(0.5)),
              itemBuilder: (context, index) {
                final file = _files[index];
                final dateStr = dateFmt.format(file.modifiedAt);
                return InkWell(
                  onTap: () => _openFile(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.description_outlined, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppTypography.serif,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textPrimary,
                                  )),
                              const SizedBox(height: 2),
                              Text('$dateStr  ·  ${_formatSize(file.size)}  ·  ${file.preview}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                          onPressed: () => _deleteFile(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: const HomeTabBar(active: 'files'),
    );
  }
}

class FileInfo {
  final String path;
  final String name;
  final DateTime modifiedAt;
  final int size;
  final String preview;

  FileInfo({
    required this.path,
    required this.name,
    required this.modifiedAt,
    required this.size,
    required this.preview,
  });
}
