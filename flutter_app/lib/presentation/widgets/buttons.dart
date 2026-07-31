/// 令牌化按钮组件集（UI 修复 PR-F / P2-1）。
///
/// 对齐 design-system/tokens.json 的 `button.*` 规格，全部接
/// [EditorTokens]（前景 / 次级前景）与 [ThemeData.colorScheme]
/// （brand.primary / surface.muted / onPrimary），**无硬编码颜色字面量**，
/// 随浅色 / 夜间 / 护眼三主题切换。
///
/// 注：本文件仅落地"组件实现"（关闭 `AppToggle/SearchPill/GhostButton/AppFab`
/// 0 实现缺口）。将 `_RoundButton` 收敛为 [GhostButton]、[SearchPill] 接入首页
/// 搜索栏等"接线"改动会改像素、需 WSL 重新生成 golden 基线，属延后项 PR-Fb。
library;

import 'package:flutter/material.dart';

import '../themes/editor_tokens.dart';

/// 幽灵按钮（tokens.button.ghost）：透明背景、圆形、次级前景色。
///
/// 用于首页顶栏的图标操作（搜索 / 主题切换 / 新建）。默认尺寸 36、
/// 图标 18，半径 50%（圆形），与 `tokens.json` `button.ghost` 一致。
class GhostButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final String? tooltip;

  const GhostButton({
    required this.icon,
    this.onTap,
    this.size = 36,
    this.iconSize = 18,
    this.tooltip,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    final child = SizedBox(
      width: size,
      height: size,
      child: Icon(icon, size: iconSize, color: tokens.textSecondary),
    );
    final ink = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: onTap,
        child: child,
      ),
    );
    return tooltip == null
        ? ink
        : Tooltip(message: tooltip!, child: ink);
  }
}

/// 开关（tokens.button.toggle）：40×24 轨道、圆角 12、thumb 20。
///
/// `value` 为当前状态；`onChanged` 为 null 时禁用。轨道色随主题
/// （开 = `colorScheme.primary`，关 = `colorScheme.surfaceContainerHighest`），
/// thumb 用 `colorScheme.onPrimary`。
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  const AppToggle({
    required this.value,
    this.onChanged,
    this.width = 40,
    this.height = 24,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trackColor = value ? scheme.primary : scheme.surfaceContainerHighest;
    final thumbColor = scheme.onPrimary;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          color: trackColor,
        ),
        padding: const EdgeInsets.all(2),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: height - 4,
            height: height - 4,
            decoration: BoxDecoration(shape: BoxShape.circle, color: thumbColor),
          ),
        ),
      ),
    );
  }
}

/// 搜索胶囊（tokens.button.searchPill）：高 44、pill 圆角、muted 背景。
///
/// 接 [TextField]（可选 [controller] / [onChanged] / [onSubmitted]）。
/// 占位符与输入字号 14、前缀图标 16，均取自 `tokens.json` `button.searchPill`。
class SearchPill extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hintText;
  final double height;

  const SearchPill({
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hintText = 'Search',
    this.height = 44,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = EditorTokens.of(context);
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: 14, color: tokens.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          prefixIcon: Icon(
            Icons.search,
            size: 16,
            color: scheme.onSurface.withOpacity(0.6),
          ),
          hintText: hintText,
          hintStyle: TextStyle(fontSize: 14, color: tokens.textSecondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(height / 2),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }
}

/// 浮动操作按钮（tokens.button.fab）：56 圆形、brand.primary 背景。
///
/// 包裹 [FloatingActionButton]（默认圆形、elevation 6 ≈ `shadow.lg`），
/// 背景 `colorScheme.primary`、前景 `colorScheme.onPrimary`、图标 26。
class AppFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  const AppFab({
    required this.icon,
    this.onPressed,
    this.size = 56,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 6,
        child: Icon(icon, size: 26),
      ),
    );
  }
}
