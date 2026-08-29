import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../providers/shell_branch_provider.dart';
import '../theme/app_typography.dart';
import '../themes/editor_tokens.dart';

/// 首页底部 4 tab 导航栏（对齐设计稿 `home-v3.html`）。
///
/// 由 [StatefulShellRoute] 的 [StatefulNavigationShell] 驱动：切换 tab 时调用
/// [StatefulNavigationShell.goBranch]，各分支（首页 / 文件 / 阅读 / 我的）以
/// [IndexedStack] 常驻，保持其 Navigator 与滚动位置，避免 `context.go()` 重建
/// 整页导致的状态丢失（见评审 1.2）。
///
/// 设计语言：固定在底部、卡片背景 + 半透明、顶部分隔线；列等宽；当前 tab 用
/// `colorScheme.primary`，其余用 `colorScheme.onSurfaceVariant`。
///
/// P0-4（2026-08-29）：移除自绘 iOS home indicator 小横条——设备装饰应由系统
/// 提供，APP 不复制（UI_FIX_PLAN P0-4 设计还原铁律；iOS 上与系统手势条双重
/// 叠加，Android 上是一根无意义装饰条）。
class HomeBottomBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const HomeBottomBar({super.key, required this.navigationShell});

  static const double _height = 64;

  static const List<_TabItem> _items = [
    _TabItem(label: '首页', icon: Icons.home_outlined),
    _TabItem(label: '文件', icon: Icons.folder_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = EditorTokens.of(context);
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
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _TabButton(
                    item: _items[i],
                    active: navigationShell.currentIndex == i,
                    onTap: () {
                      saveShellBranch(i);
                      navigationShell.goBranch(i);
                    },
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
  final String label;
  final IconData icon;
  const _TabItem({required this.label, required this.icon});
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
              fontSize: AppTypography.tabLabel,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
