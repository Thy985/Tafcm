/// 上次打开文件路径的持久化（Phase 3.4.2 文件树，契约链3 强制"打开文件一致"）。
///
/// 写入 SharedPreferences，App 重启后由 app_router 的 BootstrapScreen 读取并恢复
/// 到该文件。与 [DarkModeNotifier] 同构（SharedPreferences 单一持久化底座）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_providers.dart' show sharedPreferencesProvider;

/// SharedPreferences 键：上次打开的 .md 文件路径。
const String kLastOpenedPathPrefKey = 'formulafix.lastOpenedPath';

final lastOpenedPathProvider =
    StateNotifierProvider<LastOpenedPathNotifier, String?>(
  (ref) => LastOpenedPathNotifier(ref.watch(sharedPreferencesProvider).valueOrNull),
);

/// 记忆"上次打开文件"路径（null = 清除）。
///
/// 通过 [sharedPreferencesProvider] 持久化，避免引入新的全局静态状态
/// （AGENTS.md §6.1 / 契约 §6.5 架构守门）。
class LastOpenedPathNotifier extends StateNotifier<String?> {
  final SharedPreferences? _prefs;

  LastOpenedPathNotifier(this._prefs)
      : super(_prefs?.getString(kLastOpenedPathPrefKey));

  void set(String? path) {
    if (path == state) return;
    state = path;
    if (path == null) {
      _prefs?.remove(kLastOpenedPathPrefKey);
    } else {
      _prefs?.setString(kLastOpenedPathPrefKey, path);
    }
  }
}
