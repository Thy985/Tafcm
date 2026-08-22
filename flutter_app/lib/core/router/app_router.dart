import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../presentation/screens/editor_screen.dart';
import '../../presentation/screens/file_manager_screen.dart';
import '../../presentation/screens/document_list_screen.dart';
import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/placeholder_screens.dart';
import '../../presentation/widgets/home_shell.dart';
import '../../presentation/editor/editor_page.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/external_file_service.dart';
import '../../providers/last_opened_path_provider.dart';

/// 应用路由表。
///
/// **Phase 3.1-A PR #2 起**：
/// - `/editor` 默认指向新 [EditorPage]（Phase 3.0 production 路径）
/// - `/editor-legacy` 指向旧 [EditorScreen]（fallback，迁移期保留）
/// - `/editor3` 已移除（合并到 `/editor`）
///
/// 旧 UI 代码保留一个 release 周期，收集用户反馈后再决定是否完全删除
/// （按 [phase3.1-task-contract.md v2.0 §3.4](../../docs/contracts/phase3.1-task-contract.md)）。
final appRouter = GoRouter(
  // Phase 3.4.2：启动先经 BootstrapScreen 决定恢复上次文件还是进入文件管理页。
  initialLocation: '/',
  errorBuilder: (context, state) => _ErrorScreen(error: state.error?.toString()),
  routes: [
    // Phase 3.4.2：启动引导——读取"上次打开文件"偏好，恢复或进入 /files。
    GoRoute(
      path: '/',
      builder: (context, state) => const BootstrapScreen(),
    ),
    // Phase 3.5 首页 / 文件 / 阅读 / 我的：StatefulShellRoute 持久化各 tab 状态。
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/files', builder: (context, state) => const FileManagerScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/reader', builder: (context, state) => const ReaderPlaceholderScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/me', builder: (context, state) => const MePlaceholderScreen()),
        ]),
      ],
    ),
    GoRoute(
      path: '/documents',
      builder: (context, state) => const DocumentListScreen(),
    ),
    // Phase 3.1-A PR #2：默认入口指向新 EditorPage（production 路径）。
    // Phase 3.4.2：支持 ?path=<encoded> 打开真实 .md 文件（文件树 / 重启恢复传入）。
    // P0 修复（2026-08-04）：支持 ?externalUri=<encoded> 打开外部应用（微信等）
    // 通过 ACTION_VIEW 传来的 content:// URI。与 ?path= 互斥，externalUri 优先。
    GoRoute(
      path: '/editor',
      builder: (context, state) {
        final path = state.uri.queryParameters['path'];
        final externalUri = state.uri.queryParameters['externalUri'];
        final seedSelector = state.extra is int ? state.extra as int : 0;
        return EditorPage(
          filePath: path,
          externalUri: externalUri,
          seedSelector: seedSelector,
        );
      },
    ),
    // Phase 3.1-A PR #2：旧 EditorScreen 作为 fallback 路由（迁移期保留）
    // 入口隐藏在 EditorAppBar 设置中，普通用户不会发现。
    // Phase 3.17 完成后移除此路由 + editor_screen.dart 文件。
    GoRoute(
      path: '/editor-legacy',
      builder: (context, state) {
        final openPath = state.extra as String?;
        // DEBT-035：EditorScreen 已标 @Deprecated（WYSIWYG 迁移），
        // fallback 路由是保留期内唯一合法引用，忽略 deprecation 警告。
        // ignore: deprecated_member_use_from_same_package
        return EditorScreen(initialPath: openPath);
      },
    ),
  ],
);

class _ErrorScreen extends StatelessWidget {
  final String? error;

  const _ErrorScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                '页面加载失败',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.darkTextSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.home),
                label: const Text('返回首页'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 启动引导屏（Phase 3.4.2）。
///
/// 优先级（P0 修复 2026-08-04）：
/// 1. **外部 URI**（冷启动被外部应用拉起）：检查 [ExternalFileService.initialUri]，
///    非空则跳 `/editor?externalUri=...`，跳过 SharedPreferences。
/// 2. **上次打开文件**（[kLastOpenedPathPrefKey]）：恢复到上次编辑的文件。
/// 3. **上次所在 tab**（`last_shell_branch_index`）：恢复到 home/files/reader/me。
///
/// 仅作一次性路由决策，不含业务状态。外部 URI 优先于"上次打开文件"——
/// 用户主动从微信等外部应用拉起本应用时，意图明确是打开新文件，不应被旧文件覆盖。
class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. 优先检查冷启动外部 URI（已在 main() 中通过 initialize() 填充）。
    final externalUri = ExternalFileService.instance.initialUri;
    if (externalUri != null && externalUri.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        debugPrint('Bootstrap: navigating to external URI: $externalUri');
        context.go('/editor?externalUri=${Uri.encodeComponent(externalUri)}');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. 无外部 URI → 走 SharedPreferences 恢复上次状态。
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snap) {
        if (snap.hasError) {
          // SharedPreferences 不可用（平台异常等）：兜底进入 /files，
          // 避免加载 spinner 因 future 永不成功而永久停留。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/home');
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasData) {
          final last = snap.data!.getString(kLastOpenedPathPrefKey);
          final lastBranch = snap.data!.getInt('last_shell_branch_index');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            if (last != null && last.isNotEmpty) {
              context.go('/editor?path=${Uri.encodeComponent(last)}');
            } else {
              _goToBranch(context, lastBranch ?? 0);
            }
          });
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

/// 恢复到指定 Shell branch（ADR-0018 Decision 4）。
const _branchRoutes = ['/home', '/files', '/reader', '/me'];
void _goToBranch(BuildContext context, int index) {
  context.go(index >= 0 && index < _branchRoutes.length
      ? _branchRoutes[index]
      : '/home');
}
