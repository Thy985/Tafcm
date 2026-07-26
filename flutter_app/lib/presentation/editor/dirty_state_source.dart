/// ADR-0013 脏状态源抽象 + 具体跟踪器。
///
/// [DirtyStateSource] 是自动保存服务订阅的端口；[DirtyStateTracker] 把「实时脏计算
/// 函数」桥接为符合该端口的 isDirty / dirtyChanges，避免把 [ValueNotifier] /
/// [StreamController] 等簿记直接堆进 [EditorCoordinator]（守 God Object 闸门：
/// coordinator 文件 ≤ 200 行）。
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

/// 自动保存服务订阅的脏状态源（ADR-0013）。
///
/// - [isDirty]：**实时**脏标记（直接反映 editor 变更，不依赖协调器转发）。
/// - [dirtyChanges]：脏标记**翻转**时发射的事件流（背压：每次翻转仅一事件）。
/// - [markSaved]：保存完成后由持有快照的 save 回调调用（详见 ADR-0013 并发保护），
///   实际清理 live / editor 脏标记的逻辑在协调器自身，不在本端口。
abstract class DirtyStateSource {
  bool get isDirty;
  Stream<bool> get dirtyChanges;
  void markSaved();
}

/// 把脏计算函数桥接为 [DirtyStateSource] 所需的 isDirty / dirtyChanges（ADR-0013）。
///
/// [compute] 实时计算脏标记（如 `() => _live.isDirty`，天然反映 editor 直接变更）；
/// [sync] 在协调器发生任何变更时调用，仅在翻转时经 [dirtyChanges] 发射一次事件。
/// [ValueNotifier] 仅作翻转去重的内部簿记，真正的「源」是 [compute] 返回的实时状态。
///
/// 注：[markSaved] 由协调器自身实现（清理 live / editor 脏标记），本跟踪器不持有
/// 业务状态，故不实现该方法。
class DirtyStateTracker {
  final bool Function() compute;
  final ValueNotifier<bool> _notifier = ValueNotifier(false);
  final StreamController<bool> _ctl =
      StreamController<bool>.broadcast(sync: true);

  DirtyStateTracker(this.compute);

  bool get isDirty => compute();

  Stream<bool> get dirtyChanges => _ctl.stream;

  /// 在协调器变更后调用：计算当前脏标记，仅在翻转时发射一次事件。
  void sync() {
    final d = compute();
    if (_notifier.value != d) {
      _notifier.value = d;
      _ctl.add(d);
    }
  }

  void dispose() => _ctl.close();
}
