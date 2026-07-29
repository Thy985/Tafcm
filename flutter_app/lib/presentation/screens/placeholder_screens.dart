import 'package:flutter/material.dart';

/// 阅读 tab 占位页（设计稿 `reader.html` 尚未实现，Phase 3.5+ 跟进）。
///
/// 底部导航由 StatefulShellRoute 的 HomeScaffold 统一提供，本页不渲染。
class ReaderPlaceholderScreen extends StatelessWidget {
  const ReaderPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('阅读')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('阅读器即将上线', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text('从首页打开文档开始阅读', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// 我的 tab 占位页（设计稿 `profile.html` 尚未实现，Phase 3.5+ 跟进）。
class MePlaceholderScreen extends StatelessWidget {
  const MePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('个人中心即将上线', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
