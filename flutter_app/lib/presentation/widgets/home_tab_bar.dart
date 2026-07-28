import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../themes/editor_tokens.dart';

/// 首页底部 4 tab 导航栏（对齐设计稿 `home-v3.html` 底部 tab bar）。
///
/// 设计语言：固定在底部、卡片背景 + 半透明模糊、顶部分隔线；4 列等宽网格，
/// 每列图标 + 11sp 标签；当前 tab 用主题 `colorScheme.primary`，其余用
/// `EditorTokens.textSecondary`。底部附带 iOS home indicator 小横条。
///
/// 复用点：首页 / 文件 / 阅读 / 我的 四屏共用同一导航，避免重复实现。
class HomeTabBar extends StatelessWidget {
  /// 当前激活的 tab key（home / files / reader / me）。
  final String active;

  const HomeTabBar({super.key, required this.active});

  static const double _height = 64;

  void _onTap(BuildContext context, String key) {
    if (key == active) return;
    switch (key) {
      case 'home':
        context.go('/home');
      case 'files':
        context.go('/files');
      case 'reader':
        context.go('/reader');
      case 'me':
        context.go('/me');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = EditorTokens.of(context);
    const items = [
      _TabItem(key: 'home', label: '首页', icon: Icons.home_outlined),
      _TabItem(key: 'files', label: '文件', icon: Icons.folder_outlined),
      _TabItem(key: 'reader', label: '阅读', icon: Icons.menu_book_outlined),
      _TabItem(key: 'me', label: '我的', icon: Icons.person_outline),
    ];
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.95),
        border: Border(
          top: BorderSide(color: tokens.borderDefault.withOpacity(0.8)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _height,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    for (final item in items)
                      Expanded(
                        child: _TabButton(
                          item: item,
                          active: item.key == active,
                          onTap: () => _onTap(context, item.key),
                        ),
                      ),
                  ],
                ),
              ),
              // iOS home indicator
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                width: 128,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String key;
  final String label;
  final IconData icon;
  const _TabItem({required this.key, required this.label, required this.icon});
}

class _TabButton extends StatelessWidget {
  final _TabItem item;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
