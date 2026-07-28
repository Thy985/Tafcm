import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/document.dart';
import '../../providers/file_repository_provider.dart';
import '../../providers/editor_providers.dart';
import '../theme/app_typography.dart';
import '../themes/editor_tokens.dart';
import '../widgets/home_tab_bar.dart';

/// 应用首页（对齐设计稿 `home-v3.html`）。
///
/// 布局：iOS 风格状态栏 → serif 品牌字标 + 搜索/新建 → 「最近」区（打开任意
/// .md 入口 + 最近 3 篇）→ 「更早」区（其余）→ 底部 4 tab 导航。数据经
/// [fileRepositoryProvider] 取真实文档，三主题经 [EditorTokens] / [AppTypography]
/// 注入，无硬编码颜色字面量。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Document> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(fileRepositoryProvider);
    try {
      final docs = await repo.listDocuments();
      if (mounted) {
        setState(() {
          _docs = docs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDoc(Document doc) async {
    final repo = ref.read(fileRepositoryProvider);
    final path = await repo.documentPathFor(doc.id);
    if (mounted) context.go('/editor?path=${Uri.encodeComponent(path)}');
  }

  Future<void> _openAnyMd() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['md'],
    );
    final path = result?.files.single.path;
    if (path != null && mounted) {
      context.go('/editor?path=${Uri.encodeComponent(path)}');
    }
  }

  Future<void> _newDoc() async {
    final repo = ref.read(fileRepositoryProvider);
    final path = await repo.createDocument('未命名文档', '# 未命名文档\n\n');
    if (mounted) context.go('/editor?path=${Uri.encodeComponent(path)}');
  }

  void _onSearch() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('搜索即将上线'), duration: Duration(seconds: 1)),
    );
  }

  void _onThemeCycle() {
    ref.read(themeModeProvider.notifier).cycle();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    final recent = _docs.take(3).toList();
    final earlier = _docs.skip(3).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // 状态栏
                  const SliverToBoxAdapter(child: _StatusBar()),
                  // 头部字标 + 操作
                  SliverToBoxAdapter(
                    child: _Header(
                      onSearch: _onSearch,
                      onNew: _newDoc,
                      onThemeCycle: _onThemeCycle,
                    ),
                  ),
                  // 最近
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
                    child: _OpenAnyMdEntry(onTap: _openAnyMd),
                  ),
                  if (_loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (_docs.isEmpty)
                    const SliverToBoxAdapter(child: _EmptyHint())
                  else ...[
                    _DocList(docs: recent, onTap: _openDoc),
                    // 更早
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
                    _DocList(docs: earlier, onTap: _openDoc),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const HomeTabBar(active: 'home'),
    );
  }
}

/// iOS 风格状态栏（设计稿占位：9:41 + 信号 / Wi-Fi / 电池）。
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface.withOpacity(0.7);
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('9:41',
                style: const TextStyle(
                  fontFamily: AppTypography.mono,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ).copyWith(color: fg)),
            Row(
              children: [
                _signalIcon(fg),
                const SizedBox(width: 6),
                _wifiIcon(fg),
                const SizedBox(width: 6),
                _batteryIcon(fg),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _signalIcon(Color c) => SizedBox(
        width: 17,
        height: 11,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(c, 4.0, 4.0),
            const SizedBox(width: 1.5),
            _bar(c, 6.0, 6.0),
            const SizedBox(width: 1.5),
            _bar(c, 8.5, 8.5),
            const SizedBox(width: 1.5),
            _bar(c, 11.0, 11.0),
          ],
        ),
      );

  Widget _bar(Color c, double h, double full) => Container(
        width: 3,
        height: h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(0.5),
        ),
      );

  Widget _wifiIcon(Color c) => CustomPaint(
        size: const Size(15, 11),
        painter: _WifiPainter(c),
      );

  Widget _batteryIcon(Color c) => SizedBox(
        width: 24,
        height: 11,
        child: Row(
          children: [
            Container(
              width: 20,
              height: 10,
              decoration: BoxDecoration(
                border: Border.all(color: c, width: 1),
                borderRadius: BorderRadius.circular(2.2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(1.5),
                child: Container(
                  width: 15,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
            Container(width: 1.8, height: 4, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(0.6))),
          ],
        ),
      );
}

class _WifiPainter extends CustomPainter {
  final Color color;
  _WifiPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    for (final r in [11.0, 7.0, 3.5]) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(size.width / 2, size.height + 2), radius: r),
        -2.4,
        1.4,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
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

/// 「打开任意 .md 文件」虚线入口（便携查看器）。
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
