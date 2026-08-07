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
import '../widgets/buttons.dart';

/// 应用首页（对齐设计稿 `home-v3.html`）。
///
/// 数据经 [documentListProvider]（Stream）取值，`AsyncValue.when` 覆盖
/// loading/error/data 三态（ADR-0018 Decision 2 统一异步 UI 契约）。
/// 布局：serif 品牌字标 + 搜索/新建 →「最近」区（打开任意 .md + 最近 3 篇）
/// →「更早」区（其余）→ 底栏由 StatefulShellRoute 的 HomeScaffold 统一渲染。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.now});

  /// 当前时间，用于相对时间显示（见 [_relativeTime]）。默认取系统时间；
  /// 测试可注入固定值以保证 golden 基线确定（避免跨运行时 DateTime.now() 漂移）。
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentListProvider);
    final tokens = EditorTokens.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // P1-4 修复（2026-08-03 真机验证）：P0-4 (PR #108) 当初有意 SafeArea(top:false)
      // 让 Header 顶到屏幕最顶，假设系统状态栏透明叠加在纸色背景上。但真机状态栏
      // 不透明（小米 Android 16 实测），遮挡 "FormulaFix" 字标与右上角按钮组。
      // 改回 top:true 让出状态栏，与 editor_shell 焦点模式 SafeArea 修复保持一致。
      // bottom:true 让出 home indicator / 底部手势条。
      body: SafeArea(
        top: true,
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
                _DocList(docs: recent, now: now, onTap: (doc) => _openDoc(ref, doc, context)),
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
                _DocList(docs: earlier, now: now, onTap: (doc) => _openDoc(ref, doc, context)),
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
    // P1 修复（2026-08-06，phase3.5-realdevice-issues 问题 2）：用 push 保留返回栈，
    // 编辑器返回按钮才能 pop 回 /home。原 context.go 替换整个栈导致 maybePop 无页可 pop。
    if (context.mounted) context.push('/editor?path=${Uri.encodeComponent(path)}');
  }

  static Future<void> _openAnyMd(WidgetRef ref, BuildContext context) async {
    // P0 修复（2026-08-04 真机定位）：原用 FileType.custom + allowedExtensions:['md']，
    // file_picker 8.3.7 会把它转成 Intent(type='*/*', EXTRA_MIME_TYPES=['text/markdown'])。
    // 小米 HyperOS 的 SAF 实现对该配置过滤异常 → 弹窗完全空白（logcat 仅记录
    // "User cancelled the picker request"，无错误抛出）。改用 FileType.any 让 SAF
    // 显示所有文件，Dart 层校验 .md 扩展名：非 .md 时提示用户并中止。
    // 验证：am start -a OPEN_DOCUMENT -t 'text/markdown' 能正常显示 .md 文件，
    // 但 -t '*/*' --esa EXTRA_MIME_TYPES 'text/markdown' 在小米上完全空白。
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return; // 用户取消
    if (!path.toLowerCase().endsWith('.md')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('仅支持 .md 文件'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      // P1 修复（2026-08-06，phase3.5-realdevice-issues 问题 2）：push 保留返回栈。
      context.push('/editor?path=${Uri.encodeComponent(path)}');
    }
  }

  static Future<void> _newDoc(WidgetRef ref, BuildContext context) async {
    final repo = ref.read(fileRepositoryProvider);
    final path = await repo.createDocument('未命名文档', '# 未命名文档\n\n');
    // P1 修复（2026-08-06，phase3.5-realdevice-issues 问题 2）：push 保留返回栈。
    if (context.mounted) context.push('/editor?path=${Uri.encodeComponent(path)}');
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
              GhostButton(
                icon: Icons.search,
                onTap: onSearch,
                tooltip: '搜索',
                semanticLabel: '搜索',
              ),
              const SizedBox(width: 4),
              GhostButton(
                icon: Icons.brightness_6,
                onTap: onThemeCycle,
                tooltip: '切换主题',
                semanticLabel: '切换主题',
              ),
              const SizedBox(width: 4),
              GhostButton(
                icon: Icons.add,
                onTap: onNew,
                tooltip: '新建文档',
                semanticLabel: '新建文档',
              ),
            ],
          ),
        ],
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
  final DateTime? now;
  const _DocList({required this.docs, required this.onTap, this.now});

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
    final now = this.now ?? DateTime.now();
    final diff = now.difference(t);
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
