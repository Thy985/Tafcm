/// LocalizedAppBar：字段级 notifier 订阅的 AppBar 包装（#246）。
///
/// **依赖方向**（Hard Rule 8）：chrome 层只 import editor_coordinator.dart，
/// 不 import blocks/ / panels/。本文件仅做订阅转发，不含任何 UI 逻辑。
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// #246：把三个字段级 notifier 的订阅包成 [PreferredSizeWidget]。
///
/// [Scaffold.appBar] 的类型是 `PreferredSizeWidget?`，而
/// [ValueListenableBuilder] 不是 PreferredSizeWidget —— 直接内联三个
/// `ValueListenableBuilder` 会编译失败（CI 实测：
/// `argument_type_not_assignable`）。
///
/// 本类做两件事：
/// 1. 提供 `PreferredSizeWidget` 契约（转发 [child] 的 preferredSize）
/// 2. 集中订阅 title / dirty / undoRedo 三个 notifier，把三个值一起交给
///    [builder]，避免调用点出现三层嵌套的 `ValueListenableBuilder`
///
/// 语义与内联版完全一致：任一 notifier 变化才重建 [child]（即 AppBar），
/// 其余层（视口 / chrome）不参与。
class LocalizedAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final ValueListenable<String> titleListenable;
  final ValueListenable<bool> dirtyListenable;
  final ValueListenable<bool> undoRedoListenable;

  /// 构造 AppBar 子节点。三个参数为对应 notifier 的当前值快照。
  final Widget Function(
    BuildContext context,
    String title,
    bool isDirty,
    bool canUndoRedo,
  ) builder;

  const LocalizedAppBar({
    // 无 key：调用点固定传 `null`（Scaffold.appBar 由 position 定位，
    // 不需要 widget 级 key）。带 `super.key` 会被 analyzer 判为
    // unused_element_parameter（CI 用 --fatal-warnings）。
    required this.titleListenable,
    required this.dirtyListenable,
    required this.undoRedoListenable,
    required this.builder,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: titleListenable,
      builder: (context, title, _) =>
          ValueListenableBuilder<bool>(
        valueListenable: dirtyListenable,
        builder: (context, isDirty, _) =>
            ValueListenableBuilder<bool>(
          valueListenable: undoRedoListenable,
          builder: (context, canUndoRedo, _) =>
              builder(context, title, isDirty, canUndoRedo),
        ),
      ),
    );
  }
}
