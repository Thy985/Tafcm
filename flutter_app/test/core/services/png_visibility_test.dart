/// test/core/services/png_visibility_test.dart
///
/// Issue #234 第 1 层守门：导出公式 PNG **非全透明**（CI 可跑的纯解码路径）。
///
/// 背景：`RenderRepaintBoundary.toImage` 依赖 GPU 光栅化，在 CI headless
/// flutter_tester 挂起（PR #278 实证）→ 既有 offscreen_capture_pixel_test
/// 在 CI 上 [SKIP]，#234 "公式空白" 类回归在 CI 漏网。本测试改走
/// `instantiateImageCodec`（= GPU 无关的 CPU 解码）+ `toByteData`，确定性
/// 覆盖，从而把"导出 PNG 非全透明"真正织进 CI 回归网。
library;

import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/services/png_visibility.dart';

/// --- 最小纯 Dart PNG 编码器（测试语料，非生产） ----------------------

class _Crc32 {
  static final Uint32List _table = _build();

  static Uint32List _build() {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : (c >> 1);
      }
      t[n] = c;
    }
    return t;
  }

  static int of(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

ByteData _u32(int v) => ByteData(4)..setUint32(0, v);

void _writeChunk(BytesBuilder out, String type, List<int> data) {
  out.add(_u32(data.length).buffer.asUint8List());
  final typeBytes = type.codeUnits;
  out.add(typeBytes);
  out.add(data);
  out.add(_u32(_Crc32.of([...typeBytes, ...data])).buffer.asUint8List());
}

/// 构造一张 width×height 的 RGBA PNG。像素来自 [getPixel]（i = 行优先）。
Uint8List _buildPng(int width, int height, List<int> Function(int i) getPixel) {
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bitDepth
    ..setUint8(9, 6) // colorType: RGBA
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace

  final rawBytes = ByteData(1 + width * 4);
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    rawBytes.setUint8(0, 0); // filter: none
    for (var x = 0; x < width; x++) {
      final p = getPixel(y * width + x);
      final o = 1 + x * 4;
      rawBytes.setUint8(o, p[0]);
      rawBytes.setUint8(o + 1, p[1]);
      rawBytes.setUint8(o + 2, p[2]);
      rawBytes.setUint8(o + 3, p[3]);
    }
    raw.add(rawBytes.buffer.asUint8List(0, 1 + width * 4));
  }

  final idat = ZLibEncoder().convert(raw.takeBytes());

  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // PNG signature
  _writeChunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _writeChunk(out, 'IDAT', idat);
  _writeChunk(out, 'IEND', const []);
  return out.takeBytes();
}

void main() {
  group('analyzePng: 解码-统计（纯 CPU，CI 可跑）', () {
    test('全透明 PNG → opaqueRatio == 0（PNG 空白拦截）', () async {
      final png = _buildPng(20, 10, (_) => [0, 0, 0, 0]); // 全透明
      final s = await analyzePng(png);
      expect(s, isNotNull, reason: '合法 PNG 应能解码');
      expect(s!.opaqueRatio, 0,
          reason: '全透明 PNG 必须被识别为不可见（#234 守护：导出空白）');
      expect(await pngHasAnyOpaquePixel(png), isFalse);
    });

    test('白底 → opaque != 0；中心黑墨点 → ink > 0（可见内容）', () async {
      final png = _buildPng(3, 3, (i) {
        if (i == 4) return [0, 0, 0, 255]; // 中心一个黑墨点
        return [255, 255, 255, 255]; // 白底
      });
      final s = await analyzePng(png);
      expect(s, isNotNull);
      expect(s!.opaqueRatio, 1.0, reason: '全部像素完全不透明(白底 alpha=255)');
      expect(s.inkRatio, greaterThan(0), reason: '有 1 个黑墨点＝内容可见');
      expect(await pngHasAnyOpaquePixel(png), isTrue);
    });

    test('纯黑（全不透明）→ opaque=1 且 ink=1', () async {
      final png = _buildPng(2, 2, (_) => [0, 0, 0, 255]);
      final s = (await analyzePng(png))!;
      expect(s.opaqueRatio, 1.0);
      expect(s.inkRatio, 1.0);
    });
  });

  group('非 PNG / 损坏字节', () {
    test('非 PNG 字节 → analyzePng 返回 null（不抛）', () async {
      final bad = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(await analyzePng(bad), isNull);
      expect(await pngHasAnyOpaquePixel(bad), isFalse);
    });
  });
}