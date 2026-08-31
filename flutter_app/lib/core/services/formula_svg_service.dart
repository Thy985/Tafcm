import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../observability/ring_buffer.dart' show RingBuffer;
import '../parser/formula_extractor.dart' show FormulaExtractor;
import 'mermaid_service.dart' show MermaidErrorCallback, MermaidService;

/// MathJax 渲染 LaTeX 为 SVG 字符串服务（与 MermaidService 共享 WebView）。
///
/// 互补于 [FormulaPdfRenderer]（位图路径）：
///  - 本服务输出 SVG 字符串，可在 PDF 中作为矢量嵌入（[pw.SvgImage]）
///  - 当 WebView 未就绪时，调用方应降级到 PNG 路径
///
/// ## 与 WebView 的通信协议 (v2)
/// 旧协议用 `console.log('LATEX_OK|<id>|<len>|<svg>')` 拼回 SVG，如果 SVG
/// 本身含 `|` 字符（MathJax 内部可能产生），`parts.sublist(3).join('|')` 会丢字符。
///
/// 新协议：
///   1. JS 把 SVG 写入 `<div id="payload-{id}">`（display: none）
///   2. JS 通过 `console.log('LATEX_OK|<id>')` 通知 Dart 渲染完成
///   3. Dart 收到后用 `controller.evaluateJavascript(...)` 读取 innerHTML
///   4. 失败时 fallback 到 base64 编码的 console 协议 `LATEX_OK|<id>|b64:<base64>`
///      避免 `|` 字符引发的解码歧义
class FormulaSvgService {
  FormulaSvgService._();

  static const Duration _renderTimeout = Duration(seconds: 10);
  static const int _maxConcurrent = 4;
  static const int _maxCacheEntries = 256;
  static const int _maxCacheBytes = 32 * 1024 * 1024; // 32 MB

  /// PR-C：连续超时阈值。单公式超时先降级（PNG/文本），连续超过
  /// 该次数才重置 WebView——避免一次超时级联清空整批（历史 198 公式
  /// 123 timeout = resetRenderer 级联放大：1 个超时清空所有等待/活动请求）。
  static const int _maxConsecutiveTimeoutsBeforeReset = 3;
  static int _consecutiveTimeouts = 0;

  static final LinkedHashMap<String, String> _cache = LinkedHashMap();
  static int _totalCacheBytes = 0;
  static int _requestCounter = 0;

  static final List<_PendingLatex> _waiting = [];
  static final Map<String, _PendingLatex> _active = {};

  /// P0-5：渲染 telemetry（最近 512 条）。瓶颈分析用：
  /// `formula_id / latex_length / queue_wait_ms / render_ms / total_ms / result`。
  /// 不记 latex 原文（避免敏感内容外泄，AGENTS.md 诊断数据最小化原则）。
  static final RingBuffer<FormulaRenderTelemetry> _telemetry =
      RingBuffer<FormulaRenderTelemetry>(512);

  static List<FormulaRenderTelemetry> get telemetryEntries => _telemetry.toList();

  static void clearTelemetry() => _telemetry.clear();

  /// PR-C：telemetry 聚合报告（导出结束后调用，debugPrint 输出到 logcat）。
  ///
  /// 真机采集用：logcat 里 grep `FormulaTelemetry` 一行即可拿到
  /// 样本数 / result 分布（success/timeout/error → timeout_rate）/
  /// queue_wait / render / total 的 P50/P95/P99 + 均值，
  /// 以及瓶颈判定（queue_wait 均值 > 2× render 均值 → 排队瓶颈；
  /// 否则单个公式渲染本身慢）。不记 latex 原文（诊断数据最小化）。
  static String telemetrySummary() {
    final entries = _telemetry.toList();
    if (entries.isEmpty) {
      return 'FormulaTelemetry: empty (no renders recorded)';
    }
    final byResult = <String, int>{};
    for (final e in entries) {
      byResult[e.result] = (byResult[e.result] ?? 0) + 1;
    }
    List<int> sortedBy(int Function(FormulaRenderTelemetry) pick) {
      final v = entries.map(pick).toList()..sort();
      return v;
    }

    double pct(List<int> sorted, double p) {
      if (sorted.isEmpty) return 0;
      return sorted[((sorted.length - 1) * p).round()].toDouble();
    }

    double avg(List<int> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

    final qw = sortedBy((e) => e.queueWaitMs);
    final rn = sortedBy((e) => e.renderMs);
    final tot = sortedBy((e) => e.totalMs);
    final qwAvg = avg(qw);
    final rnAvg = avg(rn);
    final bottleneck = qwAvg > rnAvg * 2
        ? 'QUEUE-bound (queue_wait > 2x render)'
        : 'RENDER-bound (single formula slow)';
    return 'FormulaTelemetry: ${entries.length} samples | result=$byResult | '
        'queue_wait p50=${pct(qw, .5)} p95=${pct(qw, .95)} p99=${pct(qw, .99)} avg=${qwAvg.toStringAsFixed(1)}ms | '
        'render p50=${pct(rn, .5)} p95=${pct(rn, .95)} p99=${pct(rn, .99)} avg=${rnAvg.toStringAsFixed(1)}ms | '
        'total p50=${pct(tot, .5)} p95=${pct(tot, .95)} p99=${pct(tot, .99)}ms | $bottleneck';
  }

  /// 记录一次渲染请求的完整生命周期指标。
  ///
  /// [enqueuedAt] 入队时刻、[dispatchedAt] 开始 evaluate 时刻、[completedAt]
  /// 终态时刻；三者差分别量化排队等待 / 实际渲染 / 端到端耗时。
  static void _recordTelemetry(
    _PendingLatex p,
    DateTime completedAt, {
    required String result,
  }) {
    final dispatched = p.dispatchedAt ?? p.enqueuedAt;
    _telemetry.add(FormulaRenderTelemetry(
      formulaId: p.requestId,
      latexLength: p.latex.length,
      displayMode: p.displayMode,
      queueWaitMs: dispatched.difference(p.enqueuedAt).inMilliseconds,
      renderMs: completedAt.difference(dispatched).inMilliseconds,
      totalMs: completedAt.difference(p.enqueuedAt).inMilliseconds,
      result: result,
    ));
  }

  /// P1 B-6：错误回调。与 [MermaidService] 共享同一回调类型，
  /// 由 main.dart 统一注入 observability.captureError。
  static MermaidErrorCallback? _onError;

  /// P1 B-6：注入错误回调（由 main.dart 调用）。
  static void attachErrorCallback(MermaidErrorCallback? callback) {
    _onError = callback;
  }

  /// P1 B-6：报告错误（内部汇聚点）。
  ///
  /// 不传 latex 原文（可能含敏感文档内容），仅传 requestId / latex 长度 /
  /// displayMode 用于诊断"公式是否过大 / 是否为 display 模式渲染失败"。
  static void _reportError(
    String type,
    String message, {
    Map<String, Object?>? params,
  }) {
    _onError?.call(type, message, params);
  }

  /// 渲染 LaTeX 为 SVG 字符串。结果按 (latex, displayMode) 缓存。
  /// 多次并发调用会自动排队，并发上限 [_maxConcurrent]。
  /// 失败时抛 [FormulaSvgException]。
  static Future<String> renderToSvg(
    String latex, {
    bool displayMode = false,
  }) async {
    final key = _cacheKey(latex, displayMode);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }

    final controller = MermaidService.attachedController;
    if (controller == null) {
      throw FormulaSvgException(
        'MermaidRendererHost is not mounted. Mount it before calling renderToSvg.',
      );
    }

    // 关键：等 HTML + tex-svg.js 真正加载完。否则 window.renderLatex 不存在，
    // evaluateJavascript 静默失败，30s 后才超时。
    _ensurePageLoadedCallbackRegistered();
    final pageReady = await MermaidService.awaitPageLoaded();
    if (!pageReady) {
      // 专项 2：页面未就绪（离屏 WebView onLoadStop 不可靠）→ 快速降级，
      // 不排队无限等待（PNG/文本 fallback 由 buildFormulaPlan 兜底）。
      throw FormulaSvgException('LaTeX SVG render timeout: page not loaded within 8s');
    }
    if (MermaidService.attachedController == null) {
      throw FormulaSvgException('WebView reset during page-load wait');
    }

    final completer = Completer<String>();
    final requestId = 'l${++_requestCounter}';
    final pending = _PendingLatex(
      requestId: requestId,
      completer: completer,
      latex: latex,
      displayMode: displayMode,
      // P0-5：入队时刻（telemetry queue_wait 起点）。
      enqueuedAt: DateTime.now(),
    );
    _waiting.add(pending);
    _active[requestId] = pending;
    _dispatchWaiting();

    try {
      final svg = await completer.future.timeout(_renderTimeout);
      _cachePut(key, svg);
      return svg;
    } on TimeoutException {
      _active.remove(requestId);
      _waiting.remove(pending);
      _recordTelemetry(pending, DateTime.now(), result: 'timeout');
      throw FormulaSvgException('LaTeX SVG render timeout');
    } catch (e) {
      _active.remove(requestId);
      _waiting.remove(pending);
      _recordTelemetry(pending, DateTime.now(), result: 'error');
      rethrow;
    }
  }

  /// 预渲染一组 LaTeX。失败的项目会跳过（不抛错），调用方需检查 [cachedSvg]。
  /// 并发执行以提高性能。
  ///
  /// [onEachCompleted]（3.4.4 Slice 7）：每个公式完成渲染（含缓存命中）后回调，
  /// 参数为 `(completed, total)`。`total` 是入参公式集合的大小（含缓存命中）。
  /// UI 层据此更新 LinearProgressIndicator，实现"当前公式计数"进度可视化。
  static Future<void> preRenderAll(
    Iterable<String> formulas, {
    bool displayMode = false,
    void Function(int completed, int total)? onEachCompleted,
  }) async {
    final list = formulas.toList();
    final total = list.length;
    var completed = 0;
    final futures = <Future>[];
    for (final latex in list) {
      final key = _cacheKey(latex, displayMode);
      if (_cache.containsKey(key)) {
        completed++;
        onEachCompleted?.call(completed, total);
        continue;
      }
      futures.add(_preRenderOne(latex, displayMode: displayMode).then((_) {
        completed++;
        onEachCompleted?.call(completed, total);
      }));
    }
    // 并发等待所有任务，允许部分失败
    await Future.wait(futures, eagerError: false);
  }

  static Future<void> _preRenderOne(String latex, {required bool displayMode}) async {
    try {
      await renderToSvg(latex, displayMode: displayMode);
    } catch (e) {
      // 失败跳过，让调用方用 PNG 兜底
    }
  }

  /// 同步获取缓存的 SVG 字符串。
  static String? cachedSvg(String latex, {bool displayMode = false}) {
    final key = _cacheKey(latex, displayMode);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    return null;
  }

  static void _dispatchWaiting() {
    final controller = MermaidService.attachedController;
    if (controller == null) return;
    if (!MermaidService.isPageLoaded) return; // 等 onLoadStop
    while (_active.length < _maxConcurrent && _waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      _evaluate(controller, next);
    }
  }

  static bool _pageLoadedCallbackRegistered = false;

  /// 注册一次性的页面加载回调——当 MermaidService 报告页面真正加载完成后
  /// 立即 dispatch 自己的 _waiting 队列。多次调用 [renderToSvg] 共享同一个
  /// 回调。
  static void _ensurePageLoadedCallbackRegistered() {
    if (_pageLoadedCallbackRegistered) return;
    _pageLoadedCallbackRegistered = true;
    MermaidService.addPageLoadedCallback(_onPageLoaded);
  }

  static void _onPageLoaded() {
    _dispatchWaiting();
  }

  static Future<void> _evaluate(
    InAppWebViewController controller,
    _PendingLatex p,
  ) async {
    // P0-5：dispatch 时刻（telemetry queue_wait 终点 / render 起点）。
    p.dispatchedAt = DateTime.now();
    final script =
        'window.renderLatex(${_js(p.requestId)}, ${_js(p.latex)}, ${p.displayMode})';
    try {
      await controller.evaluateJavascript(source: script).timeout(_renderTimeout);
    } on TimeoutException {
      // PR-C：单公式超时先标记失败降级（PNG/文本兜底），**不立即**重置
      // WebView——一次超时若 resetRenderer 会级联清空整批等待/活动请求
      // （历史 198 公式 123 timeout = 级联放大）。连续超时达到阈值才重置
      //（说明 WebView JS 线程真卡死）。
      _consecutiveTimeouts++;
      _completePendingError(p.requestId, 'render timeout');
      if (_consecutiveTimeouts >= _maxConsecutiveTimeoutsBeforeReset) {
        _consecutiveTimeouts = 0;
        MermaidService.resetRenderer();
      }
    } catch (e) {
      _completePendingError(p.requestId, 'evaluateJavascript failed: $e');
    }
  }

  static String _js(String s) {
    // Escape backslash first, then quotes, then control chars
    return "'${s
            .replaceAll('\\', '\\\\')
            .replaceAll("'", "\\'")
            .replaceAll('\r', '\\r')
            .replaceAll('\n', '\\n')
            .replaceAll('\t', '\\t')}'";
  }

  /// 由 [MermaidRendererHost] 的 onConsoleMessage 调用。
  /// 处理 LATEX_OK 和 LATEX_ERR 前缀的消息（v2 协议）。
  ///
  /// 新格式：
  ///   - `LATEX_OK|<id>`           — SVG 在 `document.getElementById("payload-<id>")` 的 textContent 里
  ///   - `LATEX_OK|<id>|b64:<b64>` — base64 fallback（DOM 不可用时使用）
  ///   - `LATEX_ERR|<id>|<reason>` — 渲染失败
  static void handleConsoleMessage(String message) {
    if (message.startsWith('LATEX_OK|')) {
      final rest = message.substring('LATEX_OK|'.length);
      // 找到 id 和 payload 之间的第一个 '|'
      final idx = rest.indexOf('|');
      final String id;
      final String payload;
      if (idx < 0) {
        // 新格式：纯 id，SVG 在 DOM
        id = rest;
        payload = '';
      } else {
        // Fallback 格式：id|b64:<base64>
        id = rest.substring(0, idx);
        payload = rest.substring(idx + 1);
      }
      if (id.isEmpty) return;
      if (payload.startsWith('b64:')) {
        // base64 fallback — 立即解码（避免 '|' 字符问题）
        try {
          // 关键：allowMalformed: true 容忍部分字节无法解码的情况，
          // 避免 SVG 中夹杂的边缘 Unicode 字符（未配对 surrogate 等）
          // 导致整批公式渲染失败。
          final svg = utf8.decode(base64Decode(payload.substring(4)),
              allowMalformed: true);
          _completePending(id, svg);
        } catch (e) {
          _completePendingError(id, 'base64 decode failed: $e');
        }
      } else {
        // DOM 路径 — 异步读取 hidden element
        _fetchSvgFromDom(id);
      }
    } else if (message.startsWith('LATEX_ERR|')) {
      final idx = message.indexOf('|', 'LATEX_ERR|'.length);
      if (idx > 0) {
        final id = message.substring('LATEX_ERR|'.length, idx);
        _completePendingError(id, message);
      }
    }
  }

  /// 异步从 WebView DOM 读取 SVG 内容。
  /// 失败时不会无限重试——会通过 _completePendingError 通知调用方。
  static Future<void> _fetchSvgFromDom(String id) async {
    final controller = MermaidService.attachedController;
    if (controller == null) {
      _completePendingError(id, 'controller not available for DOM fetch');
      return;
    }
    try {
      final raw = await controller.evaluateJavascript(
        source:
            '(function(){var e=document.getElementById("payload-${_js(id).substring(1, _js(id).length - 1)}");return e?e.textContent:"";})()',
      );
      final svg = (raw is String) ? raw : (raw?.toString() ?? '');
      // best-effort cleanup
      try {
        await controller.evaluateJavascript(
          source:
              '(function(){var e=document.getElementById("payload-${_js(id).substring(1, _js(id).length - 1)}");if(e)e.remove();})()',
        );
      } catch (_) {}
      if (svg.isEmpty) {
        _completePendingError(id, 'DOM fetch returned empty SVG');
      } else {
        _completePending(id, svg);
      }
    } catch (e) {
      _completePendingError(id, 'DOM fetch failed: $e');
    }
  }

  static void _completePending(String requestId, String svg) {
    final p = _active.remove(requestId);
    if (p != null && !p.completer.isCompleted) {
      p.completer.complete(svg);
    }
    // PR-C：成功渲染重置连续超时计数（避免偶发超时后正常渲染被误判为
    // WebView 卡死而触发 resetRenderer）。
    _consecutiveTimeouts = 0;
    // P0-5：成功路径 telemetry。
    if (p != null) {
      _recordTelemetry(p, DateTime.now(), result: 'success');
    }
    _dispatchWaiting();
  }

  static void _completePendingError(String requestId, String error) {
    final p = _active.remove(requestId);
    if (p != null && !p.completer.isCompleted) {
      p.completer.completeError(FormulaSvgException(error));
    }
    // P0-5：失败路径 telemetry（WebView 返回 LATEX_ERR / DOM 空 SVG 等）。
    if (p != null) {
      _recordTelemetry(p, DateTime.now(), result: 'error');
    }
    // P1 B-6：渲染失败统一上报 observability。
    // 不传 latex 原文（可能含敏感文档内容），仅传长度 + displayMode。
    _reportError(
      'LatexRenderError',
      error,
      params: {
        'requestId': requestId,
        'latexLength': p?.latex.length,
        'displayMode': p?.displayMode,
      },
    );
    _dispatchWaiting();
  }

  static String _cacheKey(String latex, bool displayMode) {
    // P0-4：LaTeX → Normalized Key。Unicode 公式写法（π / ∂ / → 等）先归一为
    // LaTeX 命令再取 md5，保证「同一公式不同写法」命中同一缓存条目，
    // 编辑器 / PDF 矢量 / 导出预渲染跨模块复用。
    final normalized = FormulaExtractor.normalizeLatex(latex);
    final h = md5.convert(normalized.codeUnits).toString();
    return '${displayMode ? 'B' : 'I'}|$h';
  }

  static void _cachePut(String key, String svg) {
    final old = _cache.remove(key);
    if (old != null) {
      _totalCacheBytes -= old.length;
    }
    _cache[key] = svg;
    _totalCacheBytes += svg.length;
    _evictIfNeeded();
  }

  static void _evictIfNeeded() {
    while (_cache.length > _maxCacheEntries || _totalCacheBytes > _maxCacheBytes) {
      if (_cache.isEmpty) break;
      final firstKey = _cache.keys.first;
      final removed = _cache.remove(firstKey);
      if (removed != null) _totalCacheBytes -= removed.length;
    }
  }

  static int get cacheSize => _cache.length;
  static int get totalCacheBytes => _totalCacheBytes;

  static void clearCache() {
    _cache.clear();
    _totalCacheBytes = 0;
  }
}

class _PendingLatex {
  final String requestId;
  final Completer<String> completer;
  final String latex;
  final bool displayMode;

  /// P0-5：入队时刻（telemetry queue_wait 起点）。
  final DateTime enqueuedAt;

  /// P0-5：开始 evaluate 时刻（telemetry render 起点）；null = 未 dispatch。
  DateTime? dispatchedAt;

  _PendingLatex({
    required this.requestId,
    required this.completer,
    required this.latex,
    required this.displayMode,
    required this.enqueuedAt,
  });
}

/// P0-5：单次公式渲染的 telemetry 条目（瓶颈分析输入）。
///
/// 不记 latex 原文，仅长度 + displayMode + 三段耗时 + 结果分类；
/// 供 Render Scheduler 优化决策（先测瓶颈再谈并发，实测bug.md §P0-5）。
class FormulaRenderTelemetry {
  final String formulaId;
  final int latexLength;
  final bool displayMode;
  final int queueWaitMs;
  final int renderMs;
  final int totalMs;
  final String result; // success / timeout / error

  const FormulaRenderTelemetry({
    required this.formulaId,
    required this.latexLength,
    required this.displayMode,
    required this.queueWaitMs,
    required this.renderMs,
    required this.totalMs,
    required this.result,
  });
}

class FormulaSvgException implements Exception {
  final String message;
  FormulaSvgException(this.message);

  @override
  String toString() => 'FormulaSvgException: $message';
}
