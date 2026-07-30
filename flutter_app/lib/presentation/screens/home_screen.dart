import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/document.dart';
import '../../providers/file_repository_provider.dart';
import '../../providers/editor_providers.dart';
import '../theme/app_typography.dart';
import '../themes/editor_tokens.dart';

/// 应用首页（对齐设计稿 `home-v3.html`）。
///
/// 数据经 [documentListProvider]（Stream）取值，`AsyncValue.when` 覆盖
/// loading/error/data 三态（ADR-0018 Decision 2 统一异步 UI 契约）。
/// 布局：serif 品牌字标 + 搜索/新建 →「最近」区（打开任意 .md + 最近 3 篇）
/// →「更早」区（其余）→ 底栏由 StatefulShellRoute 的 HomeScaffold 统一渲染。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentListProvider);
    final tokens = EditorTokens.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 设计还原铁律（P0-4 / ADR-0020 衍生）：不抄设计稿的设备装饰（状态栏/home
      // indicator/刘海）。首页用自绘 _Header（非 AppBar），故顶部不套 SafeArea，
      // 内容直接顶到屏幕最顶；系统状态栏由 OS 提供并透明叠加在纸色背景上，视觉
      // 上仅一个系统状态栏。bottom 仍 true：让出 home indicator / 底部手势条。
      body: SafeArea(
        top: false,
        bottom: true,
        child: docsAsync.when(
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
          data: (_) => _buildBody(context, ref, tokens),
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, WidgetRef ref, EditorTokens tokens) {
    final recent = ref.watch(recentDocumentsProvider);
    final earlier = ref.watch(earlierDocumentsProvider);
    final docs = ref.watch(documentListProvider).valueOrNull ?? [];

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  onSearch: () => _onSearch(context),
                  onNew: () => _newDoc(ref, context),
                  onThemeCycle: () => ref.read(themeModeProvider.notifier).cycle(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Text('最近',
                      style: TextStyle(
                        fontFamily: AppTypography.serif,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: tokens.textSecondary,
                      )),
                ),
              ),
              SliverToBoxAdapter(
                child: _OpenAnyMdEntry(onTap: () => _openAnyMd(ref, context)),
              ),
              if (docs.isEmpty)
                const SliverToBoxAdapter(child: _EmptyHint())
              else ...[
                _DocList(docs: recent, onTap: (doc) => _openDoc(ref, doc, context)),
                if (earlier.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                      child: Text('更早',
                          style: TextStyle(
                            fontFamily: AppTypography.serif,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: tokens.textSecondary,
                          )),
                    ),
                  ),
                _DocList(docs: earlier, onTap: (doc) => _openDoc(ref, doc, context)),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _openDoc(WidgetRef ref, Document doc, BuildContext context) async {
    final repo = ref.read(fileRepositoryProvider);
    final path = await repo.documentPathFor(doc.id);
    if (context.mounted) context.go('/editor?path=${Uri.encodeComponent(path)}');
  }

  static Future<void> _openAnyMd(WidgetRef ref, BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['md'],
    );
    final path = result?.files.single.path;
    if (path != null && context.mounted) {
      context.go('/editor?path=${Uri.encodeComponent(path)}');
    }
  }

  static Future<void> _newDoc(WidgetRef ref, BuildContext context) async {
    final repo = ref.read(fileRepositoryProvider);
    final path = await repo.createDocument('未命名文档', '# 未命名文档\n\n');
    if (context.mounted) context.go('/editor?path=${Uri.encodeComponent(path)}');
  }

  static void _onSearch(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('搜索即将上线'), duration: Duration(seconds: 1)),
    );
  }
}
/// 头部：serif 品牌字标 + 搜索 / 新建 圆形按钮。
class _Header extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onNew;
  final VoidCallback onThemeCycle;
  const _Header({
    required this.onSearch,
    required this.onNew,
    required this.onThemeCycle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('FormulaFix',
              style: TextStyle(
                fontFamily: AppTypography.serif,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
                letterSpacing: -0.3,
              )),
          Row(
            children: [
              _RoundButton(icon: Icons.search, onTap: onSearch),
              const SizedBox(width: 4),
              _RoundButton(icon: Icons.brightness_6, onTap: onThemeCycle),
              const SizedBox(width: 4),
              _RoundButton(icon: Icons.add, onTap: onNew),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: tokens.textPrimary.withOpacity(0.7)),
        ),
      ),
    );
  }
}

/// 「打开任意 .md 文件」实线入口（便携查看器）。
class _OpenAnyMdEntry extends StatelessWidget {
  final VoidCallback onTap;
  const _OpenAnyMdEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.borderDefault, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.file_open_outlined, size: 18, color: tokens.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('打开任意 .md 文件',
                    style: TextStyle(fontSize: 13, color: tokens.textPrimary.withOpacity(0.8))),
              ),
              Text('即开即看', style: TextStyle(fontSize: 11, color: tokens.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 文档列表（borderless 行，对齐设计稿列表项）。
class _DocList extends StatelessWidget {
  final List<Document> docs;
  final void Function(Document) onTap;
  const _DocList({required this.docs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final doc = docs[i];
          final preview = doc.content.replaceAll('\n', ' ').trim();
          final snippet = preview.length > 40 ? '${preview.substring(0, 40)}…' : preview;
          return InkWell(
            onTap: () => onTap(doc),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: tokens.borderDefault.withOpacity(0.5)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        Text(snippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_relativeTime(doc.updatedAt),
                      style: TextStyle(fontSize: 11, color: tokens.textSecondary)),
                ],
              ),
            ),
          );
        },
        childCount: docs.length,
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${(diff.inDays / 30).floor()}个月前';
  }
}

/// 空状态提示（无文档时）。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.description_outlined, size: 48, color: tokens.textSecondary.withOpacity(0.6)),
          const SizedBox(height: 12),
          Text('还没有文档',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tokens.textPrimary)),
          const SizedBox(height: 4),
          Text('点右上角 + 新建，或打开任意 .md 文件',
              style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
        ],
      ),
    );
  }
}
