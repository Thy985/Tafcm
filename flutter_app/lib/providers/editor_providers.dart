import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/observability/observability_service.dart';
import '../presentation/theme/app_theme.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

/// 应用主题模式（Phase 3.4 Slice 3 / ADR-0015）。
///
/// 三向：浅色 / 夜间 / 护眼(sepia)。持久化到 [SharedPreferences]，
/// 并兼容迁移旧 `pref_dark_mode`（bool）。
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, AppThemeMode>((ref) {
  final prefsAsync = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefsAsync.valueOrNull);
});

class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  final SharedPreferences? _prefs;
  static const _key = 'pref_theme_mode';
  static const _legacyKey = 'pref_dark_mode';

  ThemeModeNotifier(this._prefs) : super(_initial(_prefs)) {
    // 迁移成功后清理废弃键，避免每次冷启动都读取旧值。
    // 仅在键仍存在时移除，避免无意义的写盘。
    if (_prefs?.containsKey(_legacyKey) ?? false) {
      _prefs!.remove(_legacyKey);
    }
  }

  static AppThemeMode _initial(SharedPreferences? prefs) {
    // 兼容迁移：旧版仅存 dark 布尔。
    if (prefs?.getBool(_legacyKey) ?? false) return AppThemeMode.dark;
    final v = prefs?.getString(_key);
    if (v != null) {
      final matched = AppThemeMode.values.where((e) => e.name == v);
      if (matched.isNotEmpty) return matched.first;
    }
    return AppThemeMode.light;
  }

  /// 显式设置主题模式。
  void setMode(AppThemeMode mode) {
    state = mode;
    _prefs?.setString(_key, mode.name);
  }

  /// 在 浅色 → 夜间 → 护眼 间循环切换（供 AppBar 图标点击）。
  void cycle() {
    const values = AppThemeMode.values;
    final next = values[(values.indexOf(state) + 1) % values.length];
    setMode(next);
  }
}

/// 向后兼容视图：legacy 路径（[EditorScreen] / 预览渲染）仍以 bool 判深色。
///
/// [themeModeProvider] 为唯一真源；此 Provider 仅作只读派生，不持有状态。
/// 旧 `pref_dark_mode` 写入逻辑已废弃（由 [ThemeModeNotifier] 接管）。
final darkModeProvider = Provider<bool>((ref) {
  return ref.watch(themeModeProvider).isDark;
});

final previewModeProvider = StateProvider<bool>((ref) => false);

final isExportingProvider = StateProvider<bool>((ref) => false);

final editorContentProvider = StateNotifierProvider<EditorContentNotifier, String>((ref) {
  return EditorContentNotifier();
});

/// 编辑器文本缓冲区（纯内存，不含持久化）。
///
/// 草稿持久化已在 Phase 1 由 ADR-0003 废除：不再写入
/// `SharedPreferences['pref_last_content']`，改为编辑器对当前打开的
/// .md 文件做防抖自动保存（见 [EditorScreen]）。
class EditorContentNotifier extends StateNotifier<String> {
  EditorContentNotifier() : super('');

  void setContent(String content) => state = content;

  void clear() => state = '';
}

// ============ Observability（Phase 3.7） ============

/// 编辑器可观测服务（LIGHT 模式，默认开启）。
///
/// 持有 [CommandTracer]、[TransactionTracer]、[InteractionTracer]、
/// [ErrorSnapshotter] 等，通过 [EditorCoordinator] 可选注入。
final observabilityProvider = Provider<ObservabilityService>((ref) {
  return ObservabilityService.light();
});
