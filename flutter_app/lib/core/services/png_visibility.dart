/// PNG 可见性分析（Issue #234 第 1 层：PNG 非全透明 CI 守门）。
///
/// 端到端捕获链（formula_pdf_renderer 离屏 toImage）里若被人误加回
/// `Opacity(0)`，产出的公式 PNG 会全透明（RGB 被丢弃），Word/PDF 里公式
/// 就"空白"。既有基于 `RenderRepaintBoundary.toImage` 的像素测试在 CI
/// headless flutter_tester 上会挂起，只能本地跑 → #234 的 CI 回归网开了
/// 大洞。本助手改为**纯解码路径**（`instantiateImageCodec` + `getNextFrame`
/// + `toByteData`），不经过 GPU 光栅化，在 CI headless 下确定性可跑，从而
/// 把"导出 PNG 非全透明"织进 CI。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// 解码结果统计。
class PngAlphaStats {
  const PngAlphaStats({
    required this.width,
    required this.height,
    required this.opaqueRatio,
    required this.inkRatio,
  });

  final double width;
  final double height;

  /// 不透膜像素占比（alpha > 0）。
  final double opaqueRatio;

  /// 非背景墨迹像素占比（RGB 任一 < 0xDD 且 alpha > 0），用于"有内容"佐证。
  final double inkRatio;
}

/// 解码 PNG 字节并统计 alpha / 墨迹。
///
/// 解码用 CPU 侧 `instantiateImageCodec`，不需要 GPU 光栅化 → CI headless
/// 可跑（与 `RenderRepaintBoundary.toImage` 相反）。
///
/// 返回 null 表示解码失败（非法 PNG / 编码器不识别）。
Future<PngAlphaStats?> analyzePng(Uint8List pngBytes) async {
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(pngBytes);
  } catch (_) {
    return null;
  }
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final w = image.width.toDouble();
  final h = image.height.toDouble();
  image.dispose();
  codec.dispose();
  if (byteData == null) return null;

  final bytes = byteData.buffer.asUint8List();
  var opaque = 0, ink = 0, total = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    total++;
    final alpha = bytes[i + 3];
    if (alpha > 0) opaque++;
    // 白底墨迹：非白像素（含抗锯齿灰度）。阈值避开纯噪声。
    if (alpha > 0 &&
        (bytes[i] < 0xDD || bytes[i + 1] < 0xDD || bytes[i + 2] < 0xDD)) {
      ink++;
    }
  }
  if (total == 0) return PngAlphaStats(width: w, height: h, opaqueRatio: 1, inkRatio: 0);
  return PngAlphaStats(
    width: w,
    height: h,
    opaqueRatio: opaque / total,
    inkRatio: ink / total,
  );
}

/// 便捷：PNG 是否**可见**（含任意不透膜像素）。全透明 → false。
///
/// 这是 #234 断言的最小形式："导出公式 PNG 非全透明"。
Future<bool> pngHasAnyOpaquePixel(Uint8List pngBytes) async {
  final s = await analyzePng(pngBytes);
  return s != null && s.opaqueRatio > 0;
}