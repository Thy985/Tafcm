/// Shell 会话恢复：启动时恢复上次 tab（ADR-0018 Decision 4）。
///
/// [goBranch] 时持久化 branch index，启动时读取；
/// 决策链：last-opened doc > lastShellBranch > branch 0（首页）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLastShellBranchKey = 'last_shell_branch_index';

/// 上次活跃的 Shell branch index（持久化到 SharedPreferences）。
final lastShellBranchProvider = FutureProvider<int>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_kLastShellBranchKey) ?? 0;
});

/// 保存当前 Shell branch index（由 [HomeBottomBar.onTap] 调用）。
Future<void> saveShellBranch(int index) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastShellBranchKey, index);
}
