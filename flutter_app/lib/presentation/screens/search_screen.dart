/// SearchScreen：全局搜索屏（P0-1 搜索接线，EXTERNAL-PROJECTS-EMPOWERMENT-PLAN §4.1）。
///
/// 职责：
/// - 顶部 [SearchPill] 输入，300ms 防抖后调 [DocumentRepository.searchDocuments]
/// - 结果列表复用首页 `_DocList` 的行样式（title + 命中片段），点击进 `/editor`
/// - 三态：初始提示（空查询）/ 加载 / 无结果 / 结果（UI 状态机，无业务 Provider）
///
/// 依赖方向：presentation → providers（fileRepositoryProvider 端口），不直连 core/services。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../themes/editor_tokens.dart';
import '../widgets/buttons.dart';
import '../../providers/file_repository_provider.dart';

/// 命中片段抽取窗口：匹配点前后各保留的字符数。
const int _kSnippetContext = 24;

/// 搜索防抖时长（规划 §4.1：输入防抖 300ms）。
const Duration _kDebounce = Duration(milliseconds: 300);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  /// null = 尚未输入（初始态）；非 null = 最近一次查询的结果集。
  List<_SearchHit>? _results;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(_kDebounce, () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(fileRepositoryProvider);
      final docs = await repo.searchDocuments(query);
      // 路径不在 Document 上（ADR-0003：由 id 推导），与首页 _openDoc 同款。
      final hits = <_SearchHit>[];
      for (final d in docs) {
        final path = await repo.documentPathFor(d.id);
        hits.add(_SearchHit.fromData(
          path: path,
          title: d.title,
          content: d.content,
          query: query,
        ));
      }
      if (!mounted) return;
      setState(() {
        _results = hits;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 搜索失败按空结果处理（repository 不抛业务异常的契约外兜底）。
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: SearchPill(
              controller: _controller,
              onChanged: _onChanged,
              hintText: '搜索标题或正文',
            ),
          ),
          Expanded(child: _buildBody(tokens)),
        ],
      ),
    );
  }

  Widget _buildBody(EditorTokens tokens) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final results = _results;
    if (results == null) {
      return _Hint(
        icon: Icons.search,
        text: '输入关键词搜索文档标题与正文',
        color: tokens.textSecondary,
      );
    }
    if (results.isEmpty) {
      return _Hint(
        icon: Icons.search_off,
        text: '没有匹配的文档',
        color: tokens.textSecondary,
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final hit = results[i];
        return InkWell(
          onTap: () => context.go('/editor?path=${Uri.encodeComponent(hit.path)}'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.borderDefault),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  hit.snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 空态 / 初始态提示。
class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Hint({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: color),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

/// 一条搜索命中：标题 + 高亮命中片段。
class _SearchHit {
  final String path;
  final String title;
  final TextSpan snippet;

  const _SearchHit({
    required this.path,
    required this.title,
    required this.snippet,
  });

  /// 从文档数据抽取首个命中片段（匹配点前后 ±[_kSnippetContext] 字符，
  /// 与首页预览同款截取思路），命中词加粗着色。title/content 经
  /// `searchDocuments`（Repository 端口）取得，path 经 `documentPathFor` 推导。
  factory _SearchHit.fromData({
    required String path,
    required String title,
    required String content,
    required String query,
  }) {
    final text = content.replaceAll('\n', ' ').trim();
    final lowerText = text.toLowerCase();
    final idx = lowerText.indexOf(query.toLowerCase());
    // 正文未命中（标题命中）→ 直接取正文开头作片段。
    final start = idx < 0 ? 0 : (idx - _kSnippetContext).clamp(0, text.length);
    final end = idx < 0
        ? text.length.clamp(0, _kSnippetContext * 2)
        : (idx + query.length + _kSnippetContext).clamp(0, text.length);
    final fragment = text.substring(start, end);

    final spans = <TextSpan>[];
    if (idx < 0) {
      spans.add(TextSpan(text: fragment.isEmpty ? '（正文为空）' : fragment));
    } else {
      final matchStart = idx - start;
      final matchEnd = matchStart + query.length;
      if (matchStart > 0) {
        spans.add(TextSpan(text: fragment.substring(0, matchStart)));
      }
      spans.add(TextSpan(
        text: fragment.substring(matchStart, matchEnd),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      if (matchEnd < fragment.length) {
        spans.add(TextSpan(text: fragment.substring(matchEnd)));
      }
    }
    return _SearchHit(
      path: path,
      title: title,
      snippet: TextSpan(children: spans),
    );
  }
}
