import 'package:flutter/material.dart';

import '../widgets/home_tab_bar.dart';

/// 阅读 tab 占位页（设计稿 `reader.html` 尚未实现，Phase 3.5+ 跟进）。
///
/// 当前仅提供与首页一致的底部导航 + 占位空状态，保证 4 tab 导航闭环可用，
/// 不阻塞真机验收流程。真实阅读器（沉浸式阅读 / 目录 / 主题切换）后续落地。
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
      bottomNavigationBar: const HomeTabBar(active: 'reader'),
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
      bottomNavigationBar: const HomeTabBar(active: 'me'),
    );
  }
}
