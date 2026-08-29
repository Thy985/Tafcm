import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/observability/observability_service.dart';
import 'core/router/app_router.dart';
import 'core/services/external_file_service.dart';
import 'core/services/formula_pdf_renderer.dart';
import 'core/services/formula_svg_service.dart';
import 'core/services/mermaid_service.dart';
import 'core/services/storage_migration.dart';

import 'presentation/theme/app_theme.dart';
import 'presentation/widgets/mermaid_host.dart';
import 'providers/editor_providers.dart';

/// App 版本号（与 pubspec.yaml `version` 保持一致）。
///
/// P0 修复（2026-08-04）：用于 [ErrorSnapshotter.setAppInfo]。
/// 不引入 package_info_plus 依赖（避免包体积增长），版本号变更时
/// 同步更新此处即可。Phase 3+ 接入动态版本读取时替换为
/// `await PackageInfo.fromPlatform()`。
const String kAppVersion = '0.1.0+1';

/// 全局可观测服务实例。
///
/// P0 修复（2026-08-04）：在 [main] 启动前创建，用于安装全局错误钩子
/// （[FlutterError.onError] / [runZonedGuarded]）。通过
/// [ProviderScope.overrides] 注入 Riverpod，使 [observabilityProvider]
/// 拿到的就是全局实例——全局错误捕获的 ErrorSnapshot 与用户导出的
/// 诊断 zip 来自同一实例，确保错误不丢失。
final ObservabilityService globalObservability = ObservabilityService.light();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // P0 修复（2026-08-04）：B-3 设置 App 环境信息（dart:io Platform）。
  // 不引入 device_info_plus，用 Platform API 获取基本 OS 信息即可。
  // 完整设备型号（如"Redmi K30"）留待 Phase 3+ 接入 device_info_plus。
  globalObservability.errorSnapshotter?.setAppInfo(
    version: kAppVersion,
    device: Platform.operatingSystem,
    os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );

  // P1 修复（2026-08-04, B-6）：注入 WebView 渲染错误回调。
  // MermaidService / FormulaSvgService 是 core 层静态类，不能直接 import
  // observability（AGENTS.md §6.1.1）。这里通过 attachErrorCallback 把
  // globalObservability.captureError 注入到两个服务，让 Mermaid / LaTeX
  // 渲染失败可观测。
  void reportWebViewError(
    String type,
    String message,
    Map<String, Object?>? params,
  ) {
    globalObservability.captureError(
      type: type,
      message: message,
      commandName: 'WebViewRenderer',
      commandParams: params,
    );
    debugPrint('[OBS] WebView error: $type | $message | params=$params');
  }

  MermaidService.attachErrorCallback(reportWebViewError);
  FormulaSvgService.attachErrorCallback(reportWebViewError);


  // P0 修复（2026-08-04）：B-2 安装全局错误钩子（Flutter 框架异常）。
  // 捕获 widget build / layout / painting 异常，release 模式下不再静默丢失。
  // 仍调用 FlutterError.presentError 保持默认红屏行为（debug 模式可见）。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    globalObservability.captureError(
      type: 'GlobalError',
      message: details.exceptionAsString(),
    );
    debugPrint('[OBS] Global FlutterError: ${details.exception}'
        '\n${details.stack}');
  };

  // P0 修复（2026-08-04）：B-2 安装全局错误钩子（async / Isolate 异常）。
  // runZonedGuarded 捕获：
  // - 未 await 的 Future 异常
  // - Zone 内未捕获的同步异常
  // - Isolate 异常（通过 PlatformDispatcher.onError 转发）
  // 原main() 中的 await 调用移入 zone 内，确保其异常也被捕获。
  runZonedGuarded<Future<void>>(
    () async {
      // P0 修复（2026-08-04）：注册外部文件 MethodChannel 并查询冷启动 URI。
      // 必须 await：内部会反向调用 getInitialUri 取回 MainActivity 缓存的
      // pendingUri，填充到 ExternalFileService.instance.initialUri 供
      // BootstrapScreen 同步读取。
      await ExternalFileService.instance.initialize();
      // 启动时执行一次性存储迁移（JSON 文档库 → .md 单一真相源）。
      // 失败不阻塞启动，仅记录日志，旧数据保留为 .bak。
      try {
        await StorageMigration.migrateIfNeeded();
      } catch (e) {
        debugPrint('Storage migration skipped: $e');
      }
      runApp(
        ProviderScope(
          overrides: [
            // P0 修复（2026-08-04）：全局 observability 实例注入 Riverpod，
            // 使 observabilityProvider 拿到的就是已安装错误钩子的实例。
            observabilityProvider.overrideWithValue(globalObservability),
          ],
          child: const TafcmApp(),
        ),
      );
    },
    (error, stack) {
      globalObservability.captureError(
        type: 'GlobalError',
        message: '$error',
      );
      debugPrint('[OBS] Global zone error: $error\n$stack');
    },
  );
}

class TafcmApp extends ConsumerStatefulWidget {
  const TafcmApp({super.key});

  @override
  ConsumerState<TafcmApp> createState() => _TafcmAppState();
}

class _TafcmAppState extends ConsumerState<TafcmApp> {
  /// 热启动监听订阅：应用已在后台时，外部应用再次通过 ACTION_VIEW 拉起本应用，
  /// MainActivity.onNewIntent → invokeMethod → uriStream 推送 URI。
  /// 此处监听并跳转到 /editor?externalUri=... 替换当前页面。
  StreamSubscription<String>? _externalUriSub;

  @override
  void initState() {
    super.initState();
    _externalUriSub = ExternalFileService.instance.uriStream.listen((uri) {
      debugPrint('TafcmApp: warm-start external URI received: $uri');
      // 用 appRouter.go 而非 context.go：listener 回调时 context 可能未挂载。
      // appRouter 是全局单例，go() 会触发顶层 Navigator 重建。
      appRouter.go('/editor?externalUri=${Uri.encodeComponent(uri)}');
    });
  }

  @override
  void dispose() {
    _externalUriSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Tafcm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(mode),
      routerConfig: appRouter,
      builder: (context, child) {
        return FormulaRenderHost(
          child: Stack(
            children: [
              if (child != null) child,
              const Positioned(
                left: -10000,
                top: -10000,
                child: MermaidRendererHost(),
              ),
            ],
          ),
        );
      },
    );
  }
}
