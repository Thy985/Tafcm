/// EditorAutoFocus：文档加载后自动聚焦首块（issue #340-C）。
///
/// **为何独立成文件**：[EditorPage] 已触及 TC-ARCH-7 的 400 行上限，
/// 且「加载完成 → 聚焦首块」是跨三条加载路径（种子 / 文件 / 外部 URI）
/// 共用的关注点，抽为可测试的纯函数便于独立守门。
///
/// **为何不能在 initState 直接聚焦**：加载路径是异步的，initState 时 widget 树
/// 尚未构建、coordinator 的 viewState 也不存在，此时调
/// [EditorCoordinator.setFocus] 会被丢弃。本文件由
/// [WidgetsBindingObserver.didChangeDependencies] 驱动——三条加载路径最终都在
/// `finally` 中置 `_ready`，框架随后触发依赖回调，那时树与 coordinator 皆就绪。
library;

import 'package:flutter/foundation.dart';

import 'editor_coordinator.dart';

/// 文档就绪后自动聚焦首个可编辑块。
///
/// [pending] 由调用方持有的一次性标志（加载路径置 `true`，触发后置 `false`），
/// 保证只在树就绪后补聚焦一次。
///
/// **不覆盖已有焦点**：导航返回同一页时若用户已有焦点，保留原焦点。
/// **只读路径**（外部 URI 查看模式）仍聚焦首块以便定位，但编辑命令 no-op。
///
/// 返回是否执行了 [EditorCoordinator.setFocus]。未挂起 / 无块时不改动
/// [pending]，交由调用方在下一帧重试。
bool autoFocusFirstBlockIfPending({
  required EditorCoordinator coordinator,
  required bool pending,
  required ValueChanged<bool> setPending,
}) {
  if (!pending) return false;
  final ids = coordinator.allIds;
  if (ids.isEmpty) return false;
  setPending(false);
  if (coordinator.focusedId == null) coordinator.setFocus(ids.first);
  return true;
}
