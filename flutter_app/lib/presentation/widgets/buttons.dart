/// 令牌化按钮组件集（UI 修复 PR-F / P2-1）。
///
/// 对齐 design-system/tokens.json 的 `button.*` 规格，**颜色严格取 [EditorTokens]
/// 注入的 tokens 精确值**（[EditorTokens.surfaceMuted] / [EditorTokens.brandPrimary]
/// / [EditorTokens.brandPrimaryForeground] / [EditorTokens.textPrimary] /
/// [EditorTokens.textSecondary]），**不**使用 M3 重映射的 `colorScheme.primary` /
/// `surfaceContainerHighest` / `onPrimary`（避免落库像素偏离设计令牌）。
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

  /// 无障碍标签；提供时包裹 [Semantics]（纯图标按钮无可见文字，需显式语义）。
  final String? semanticLabel;

  const GhostButton({
    required this.icon,
    this.onTap,
    this.size = 36,
    this.iconSize = 18,
    this.tooltip,
    this.semanticLabel,
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
    final wrapped =
        tooltip == null ? ink : Tooltip(message: tooltip!, child: ink);
    return semanticLabel == null
        ? wrapped
        : Semantics(label: semanticLabel, button: true, child: wrapped);
  }
}

/// 开关（tokens.button.toggle）：40×24 轨道、圆角 12、thumb 20。
///
/// `value` 为当前状态；`onChanged` 为 null 时禁用。轨道色随主题
/// （开 = [EditorTokens.brandPrimary]，关 = [EditorTokens.surfaceMuted]），
/// thumb 用 tokens.toggle.thumbColor（#FFFFFF）。
///
/// 无障碍：包裹 [Semantics]（`toggled` + `label` + 中文化 `value`），并以
/// [FocusableActionDetector] 接入 Enter/Space 键盘激活。app-wide 开关原语
/// 的单一所有权见 UI_FIX_PLAN「PR-Fb 颜色源」决策（与 [AppBottomSheetSwitch]
/// 收敛为统一原语属后续项）。
class AppToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  /// 无障碍标签；提供时作为 switch role 的语义名。
  final String? semanticLabel;

  const AppToggle({
    required this.value,
    this.onChanged,
    this.width = 40,
    this.height = 24,
    this.semanticLabel,
    super.key,
  });

  @override
  State<AppToggle> createState() => _AppToggleState();
}

class _AppToggleState extends State<AppToggle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = EditorTokens.of(context);
    final enabled = widget.onChanged != null;
    final trackColor =
        widget.value ? tokens.brandPrimary : tokens.surfaceMuted;
    const thumbColor = Colors.white; // tokens.toggle.thumbColor = #FFFFFF
    return Semantics(
      label: widget.semanticLabel,
      toggled: widget.value,
      value: widget.value ? '开' : '关',
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (enabled) widget.onChanged!(!widget.value);
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.height / 2),
              color: trackColor,
              // 键盘焦点环（UI affordance，非 token 颜色）。
              border: _focused && enabled
                  ? Border.all(color: tokens.brandPrimary, width: 2)
                  : null,
            ),
            padding: const EdgeInsets.all(2),
            child: Align(
              alignment:
                  widget.value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: widget.height - 4,
                height: widget.height - 4,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: thumbColor),
              ),
            ),
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
    final tokens = EditorTokens.of(context);
    // 输入 / 占位字号 14 = tokens.searchPill.placeholderSize；spec 仅定义
    // placeholderSize，输入同值（PR-Fb 若引入 inputSize token 再改）。
    const textFontSize = 14.0;
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: textFontSize, color: tokens.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: tokens.surfaceMuted, // tokens.searchPill.background
          prefixIcon: Icon(
            Icons.search,
            size: 16,
            color: tokens.textSecondary, // mutedForeground，避免魔法 alpha
          ),
          hintText: hintText,
          hintStyle:
              TextStyle(fontSize: textFontSize, color: tokens.textSecondary),
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

/// 浮动操作按钮（tokens.button.fab）：56 圆形、[EditorTokens.brandPrimary] 背景。
///
/// 包裹 [FloatingActionButton]（默认圆形、elevation 6）；背景 / 前景严格取
/// [EditorTokens.brandPrimary] / [EditorTokens.brandPrimaryForeground]（tokens
/// 精确值，非 M3 `colorScheme`）。`elevation` 无法表达 `shadow.lg` 模糊/扩散半径，
/// 像素保真见 build 注释（PR-Fb 改用自定义 BoxShadow）。图标 26。
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
    final tokens = EditorTokens.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: tokens.brandPrimary, // tokens.button.fab.background
        foregroundColor:
            tokens.brandPrimaryForeground, // tokens.button.fab.foreground
        // elevation 无法表达 tokens.shadow.lg 的模糊/扩散半径（0 12px 40px）。
        // 像素保真需 PR-Fb 改用自定义 BoxShadow 覆盖 FAB 阴影。
        elevation: 6,
        child: Icon(icon, size: 26),
      ),
    );
  }
}
