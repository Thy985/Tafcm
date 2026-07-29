import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'home_tab_bar.dart';

/// 底部 4 tab 的持久化外壳（[StatefulShellRoute.indexedStack] 的 builder）。
///
/// 各分支（首页 / 文件 / 阅读 / 我的）以 [IndexedStack] 常驻；切换 tab 时仅切换
/// 可见分支、保留各自 Navigator 与滚动位置。[HomeBottomBar] 统一渲染底部导航。
class HomeScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const HomeScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: navigationShell,
        bottomNavigationBar: HomeBottomBar(navigationShell: navigationShell),
      );
}
