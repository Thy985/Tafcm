import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/services/formula_svg_service.dart';
import '../../core/services/mermaid_service.dart';

class MermaidRendererHost extends StatefulWidget {
  const MermaidRendererHost({super.key});

  @override
  State<MermaidRendererHost> createState() => _MermaidRendererHostState();
}

class _MermaidRendererHostState extends State<MermaidRendererHost> {
  InAppWebViewController? _controller;

  @override
  void initState() {
    super.initState();
    // PR-D（页面加载生命周期专项）：监听 renderer 重置 → reload WebView，
    // 恢复页面加载状态。否则 resetRenderer 后 _pageLoaded 永久 false，
    // FormulaSvgService._dispatchWaiting 门禁永久拦截，导出卡死（3/95）。
    MermaidService.addRendererResetCallback(_handleRendererReset);
  }

  /// PR-D + D2：renderer 重置后恢复 WebView。
  ///
  /// D2 修复（状态机审计缺陷 D2）：resetRenderer 已把 `MermaidService._controller`
  /// 置 null——仅 reload 不会重新触发 onWebViewCreated → attachController 不再
  /// 被调用 → `_controller` 永久 null → `FormulaSvgService._dispatchWaiting`
  /// 门禁 1（attachedController == null）永久拦截。因此 reload **前**必须
  /// 重新 attachController 恢复 `_controller/_isReady`，形成完整恢复链路：
  /// Reset → Attached → Loaded（reload→onLoadStop）→ Ready（markPageLoaded）。
  void _handleRendererReset() {
    final controller = _controller;
    if (controller == null) return;
    debugPrint('MermaidRendererHost: renderer reset, re-attaching + reloading WebView...');
    try {
      // D2：先恢复 controller/isReady（reload 不会重新触发 onWebViewCreated）。
      MermaidService.attachController(controller);
      // 再 reload 触发 onLoadStop → markPageLoaded → _pageLoaded=true。
      controller.reload();
    } catch (e) {
      debugPrint('MermaidRendererHost: reset recovery failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 关键修复：即使 isReady=false 也必须挂载 WebView，否则永远无法触发
    // onWebViewCreated → attachController → isReady=true。这是典型的"先有鸡还是
    // 先有蛋"死锁——必须无条件下渲染 InAppWebView。
    return SizedBox(
      width: 800,
      height: 400,
      // 加载本地资产目录下的 HTML 模板 (assets/mermaid_renderer.html)。
      // 该文件内的 `<script src="js/tex-svg.js">` / `<script src="js/mermaid.min.js">`
      // 会以 HTML 所在目录为基准解析为 Flutter 打包的 `assets/js/...`，
      // 不再依赖任何 CDN / 平台硬编码路径。
      // 平台映射 (由 flutter_inappwebview 内部解析):
      //   - Android: 打包到 APK assets 目录，WebView 通过 file:// 协议加载
      //   - Windows: 提取到 <exeDir>/data/flutter_assets/ 后用 file:// 加载
      //   - Web:     由 flutter_inappwebview_web 通过 iframe 资源服务代理
      child: InAppWebView(
        key: const ValueKey('mermaid-renderer-webview'),
        initialFile: MermaidService.rendererAssetPath,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: true,
          verticalScrollBarEnabled: false,
          horizontalScrollBarEnabled: false,
        ),
        onWebViewCreated: (controller) {
          // 立即 attach controller，使 renderToSvg 知道 WebView 已挂载。
          // 即使 JS 还在加载 JS 资源，attachController 已经让请求能排队。
          _controller = controller; // PR-D：保存引用，reset 后 reload 用
          MermaidService.attachController(controller);
        },
        onConsoleMessage: (controller, consoleMessage) {
          final msg = consoleMessage.message;
          MermaidService.handleConsoleMessage(msg);
          FormulaSvgService.handleConsoleMessage(msg);
        },
        onRenderProcessGone: (controller, gone) {
          // WebView 渲染进程崩溃（GPU worker thread exit 等），
          // 此时 SVG 渲染已不可用，需重置状态让导出回退到 PNG-only 模式。
          MermaidService.resetRenderer();
        },
        onLoadStop: (controller, url) {
          // 关键：页面 + 子资源（tex-svg.js / mermaid.min.js）真正加载完毕
          // 才会触发此回调。在 onWebViewCreated 之后、JS 资源加载完成之前，
          // window.renderMermaid 还不存在，若此时调用 evaluateJavascript
          // 会静默失败 → 30s 后 → MermaidRenderException('render timeout')。
          // 因此必须在 onLoadStop 之后才能把待发请求 dispatch 出去。
          MermaidService.markPageLoaded();
        },
        onLoadStart: (controller, url) {
          // D3 埋点接线：页面开始加载（inappwebview v6 的 onPageStarted 已
          // 更名为 onLoadStart——区分"从未加载"与"加载中"）。
          MermaidService.pageLoadStart();
        },
        onReceivedError: (controller, request, error) {
          // D3 埋点接线：加载失败不再静默（状态机感知 + 可观测）。
          MermaidService.pageLoadError('${request.url}: ${error.description}');
        },
        onReceivedHttpError: (controller, request, errorResponse) {
          debugPrint('MermaidRendererHost: HTTP error ${request.url}: '
              '${errorResponse.statusCode}');
        },
      ),
    );
  }
}
