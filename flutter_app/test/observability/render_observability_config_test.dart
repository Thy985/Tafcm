/// 渲染可观测层配置与 CJK 检测测试（P1-2 / P1-4 review 修复）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/models.dart' as obs;
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/domain/services/exporters/pdf_exporter.dart';

void main() {
  group('P1-2: renderBufferSize 配置接线', () {
    test('custom renderBufferSize 反映到 RenderTracer capacity', () {
      final svc = ObservabilityService(
        config: const obs.ObservabilityConfig(
          level: obs.ObservabilityLevel.light,
          renderBufferSize: 10,
        ),
      );
      expect(svc.renderTracer.capacity, equals(10));
    });

    test('默认 renderBufferSize=500', () {
      final svc = ObservabilityService.light();
      expect(svc.renderTracer.capacity, equals(500));
    });
  });

  group('P1-4: _containsCjk 覆盖非 BMP astral CJK', () {
    test('BMP CJK（U+4E00 中）detected', () {
      expect(PdfExporter.containsCjk('中文注释'), isTrue);
    });

    test('CJK Extension A（U+3400）detected', () {
      expect(PdfExporter.containsCjk('\u3400'), isTrue);
    });

    test('CJK Extension B（U+20000 𠀀）detected', () {
      expect(PdfExporter.containsCjk('𠀀'), isTrue);
    });

    test('CJK Extension B 范围上界（U+2A6DF）detected', () {
      expect(PdfExporter.containsCjk('\u{2A6DF}'), isTrue);
    });

    test('CJK Compatibility Supplement（U+2F800）detected', () {
      expect(PdfExporter.containsCjk('\u{2F800}'), isTrue);
    });

    test('pure ASCII not detected', () {
      expect(PdfExporter.containsCjk('hello world'), isFalse);
    });

    test('空字符串 not detected', () {
      expect(PdfExporter.containsCjk(''), isFalse);
    });

    test('astral CJK 混在 ASCII 中 detected', () {
      expect(PdfExporter.containsCjk('code 𠀀 comment'), isTrue);
    });
  });
}