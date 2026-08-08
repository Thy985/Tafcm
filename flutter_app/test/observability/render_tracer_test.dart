/// 渲染/导出可观测层测试（问题 6.1/6.4/6.5）。
///
/// 验证：
/// - RenderTracer 基本功能（record / clear / capacity）
/// - ObservabilityService.recordRender() 正确记录到 RingBuffer
/// - 三种 RenderObservabilityEvent 子类字段正确
/// - isRenderSignal 信噪比判定（问题 3 修复：theme/chip 异常检测）
/// - exportSnapshot() 包含 render 事件
/// - clear() 清空 render tracer
/// - OFF 模式不记录
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/models.dart' as obs;
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/core/observability/render_tracer.dart';

void main() {
  group('RenderTracer 基本功能', () {
    test('record / count / entries', () {
      final tracer = RenderTracer(capacity: 10);
      expect(tracer.count, equals(0));

      final now = DateTime.now();
      tracer.record(obs.CodeBlockThemeRendered(
        isDark: true,
        themeName: 'atomOneDark',
        language: 'python',
        timestamp: now,
      ));
      expect(tracer.count, equals(1));
      expect(tracer.entries.last, isA<obs.CodeBlockThemeRendered>());
    });

    test('clear', () {
      final tracer = RenderTracer(capacity: 10);
      tracer.record(obs.CodeBlockThemeRendered(
        isDark: false,
        themeName: 'github',
        language: 'dart',
        timestamp: DateTime.now(),
      ));
      expect(tracer.count, equals(1));
      tracer.clear();
      expect(tracer.count, equals(0));
    });

    test('RingBuffer 容量溢出丢弃最旧', () {
      final tracer = RenderTracer(capacity: 3);
      for (var i = 0; i < 5; i++) {
        tracer.record(obs.CodeBlockThemeRendered(
          isDark: false,
          themeName: 'github',
          language: 'lang$i',
          timestamp: DateTime.now(),
        ));
      }
      expect(tracer.count, equals(3));
      final entries = tracer.entries;
      expect((entries[0] as obs.CodeBlockThemeRendered).language, equals('lang2'));
      expect((entries[2] as obs.CodeBlockThemeRendered).language, equals('lang4'));
    });
  });

  group('ObservabilityService.recordRender()', () {
    test('LIGHT 模式记录到 RingBuffer', () {
      final svc = ObservabilityService.light();
      final now = DateTime.now();

      svc.recordRender(obs.CodeBlockThemeRendered(
        isDark: true,
        themeName: 'atomOneDark',
        language: 'python',
        timestamp: now,
      ));

      expect(svc.renderTracer.count, equals(1));
      final event = svc.renderTracer.entries.last;
      expect(event, isA<obs.CodeBlockThemeRendered>());
      final rendered = event as obs.CodeBlockThemeRendered;
      expect(rendered.isDark, isTrue);
      expect(rendered.themeName, equals('atomOneDark'));
      expect(rendered.language, equals('python'));
    });

    test('OFF 模式不记录', () {
      final svc = ObservabilityService.off();
      svc.recordRender(obs.CodeBlockThemeRendered(
        isDark: false,
        themeName: 'github',
        language: 'dart',
        timestamp: DateTime.now(),
      ));
      expect(svc.renderTracer.count, equals(0));
    });

    test('clear() 清空 render tracer', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CodeBlockThemeRendered(
        isDark: false,
        themeName: 'github',
        language: 'dart',
        timestamp: DateTime.now(),
      ));
      expect(svc.renderTracer.count, equals(1));
      svc.clear();
      expect(svc.renderTracer.count, equals(0));
    });
  });

  group('CodeBlockThemeRendered（问题 6.1）', () {
    test('dark 主题 → atomOneDark', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CodeBlockThemeRendered(
        isDark: true,
        themeName: 'atomOneDark',
        language: 'python',
        timestamp: DateTime.now(),
      ));
      final event = svc.renderTracer.entries.last as obs.CodeBlockThemeRendered;
      expect(event.isDark, isTrue);
      expect(event.themeName, equals('atomOneDark'));
    });

    test('light 主题 → github', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CodeBlockThemeRendered(
        isDark: false,
        themeName: 'github',
        language: 'dart',
        timestamp: DateTime.now(),
      ));
      final event = svc.renderTracer.entries.last as obs.CodeBlockThemeRendered;
      expect(event.isDark, isFalse);
      expect(event.themeName, equals('github'));
    });
  });

  group('CodeBlockLanguageChipRendered（问题 6.5）', () {
    test('有 language → shown=true', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CodeBlockLanguageChipRendered(
        language: 'python',
        shown: true,
        mode: obs.CodeBlockChipMode.edit,
        timestamp: DateTime.now(),
      ));
      final event =
          svc.renderTracer.entries.last as obs.CodeBlockLanguageChipRendered;
      expect(event.language, equals('python'));
      expect(event.shown, isTrue);
      expect(event.mode, equals(obs.CodeBlockChipMode.edit));
    });

    test('无 language → shown=false', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CodeBlockLanguageChipRendered(
        language: null,
        shown: false,
        mode: obs.CodeBlockChipMode.render,
        timestamp: DateTime.now(),
      ));
      final event =
          svc.renderTracer.entries.last as obs.CodeBlockLanguageChipRendered;
      expect(event.language, isNull);
      expect(event.shown, isFalse);
    });
  });

  group('PdfCjkFontFallbackEvent（问题 6.4）', () {
    test('CJK 字体已加载 → fallbackActive=true', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.PdfCjkFontFallbackEvent(
        fontLoaded: true,
        fallbackActive: true,
        language: 'python',
        codeLength: 50,
        hasCjk: true,
        timestamp: DateTime.now(),
      ));
      final event =
          svc.renderTracer.entries.last as obs.PdfCjkFontFallbackEvent;
      expect(event.fontLoaded, isTrue);
      expect(event.fallbackActive, isTrue);
      expect(event.hasCjk, isTrue);
    });

    test('CJK 字体未加载 + 含 CJK → fallbackActive=false（降级信号）', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.PdfCjkFontFallbackEvent(
        fontLoaded: false,
        fallbackActive: false,
        language: 'python',
        codeLength: 50,
        hasCjk: true,
        timestamp: DateTime.now(),
      ));
      final event =
          svc.renderTracer.entries.last as obs.PdfCjkFontFallbackEvent;
      expect(event.fontLoaded, isFalse);
      expect(event.fallbackActive, isFalse);
      expect(event.hasCjk, isTrue);
    });
  });

  group('isRenderSignal 信噪比判定（问题 3 修复）', () {
    final now = DateTime.now();

    group('PdfCjkFontFallbackEvent', () {
      test('hasCjk=true + fallbackActive=false → signal（降级风险）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.PdfCjkFontFallbackEvent(
            fontLoaded: false,
            fallbackActive: false,
            language: 'python',
            codeLength: 50,
            hasCjk: true,
            timestamp: now,
          )),
          isTrue,
        );
      });

      test('hasCjk=false + fallbackActive=true → not signal（正常）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.PdfCjkFontFallbackEvent(
            fontLoaded: true,
            fallbackActive: true,
            language: 'python',
            codeLength: 50,
            hasCjk: false,
            timestamp: now,
          )),
          isFalse,
        );
      });

      test('hasCjk=true + fallbackActive=true → not signal（正常）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.PdfCjkFontFallbackEvent(
            fontLoaded: true,
            fallbackActive: true,
            language: 'python',
            codeLength: 50,
            hasCjk: true,
            timestamp: now,
          )),
          isFalse,
        );
      });
    });

    group('CodeBlockThemeRendered', () {
      test('isDark=true + themeName=atomOneDark → not signal（正常）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.CodeBlockThemeRendered(
            isDark: true,
            themeName: 'atomOneDark',
            language: 'python',
            timestamp: now,
          )),
          isFalse,
        );
      });

      test('isDark=false + themeName=github → not signal（正常）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.CodeBlockThemeRendered(
            isDark: false,
            themeName: 'github',
            language: 'dart',
            timestamp: now,
          )),
          isFalse,
        );
      });

      test('isDark=true + themeName=github → signal（映射错误）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.CodeBlockThemeRendered(
            isDark: true,
            themeName: 'github',
            language: 'python',
            timestamp: now,
          )),
          isTrue,
        );
      });

      test('isDark=false + themeName=atomOneDark → signal（映射错误）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.CodeBlockThemeRendered(
            isDark: false,
            themeName: 'atomOneDark',
            language: 'dart',
            timestamp: now,
          )),
          isTrue,
        );
      });
    });

    group('CodeBlockLanguageChipRendered', () {
      test('有 language + shown=true → not signal（正常）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.CodeBlockLanguageChipRendered(
            language: 'python',
            shown: true,
            mode: obs.CodeBlockChipMode.edit,
            timestamp: now,
          )),
          isFalse,
        );
      });

      test('无 language + shown=false → not signal（正常）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.CodeBlockLanguageChipRendered(
            language: null,
            shown: false,
            mode: obs.CodeBlockChipMode.render,
            timestamp: now,
          )),
          isFalse,
        );
      });

      test('有 language + shown=false → signal（逻辑错误）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.CodeBlockLanguageChipRendered(
            language: 'python',
            shown: false,
            mode: obs.CodeBlockChipMode.edit,
            timestamp: now,
          )),
          isTrue,
        );
      });

      test('无 language + shown=true → signal（逻辑错误）', () {
        expect(
          ObservabilityService.isRenderSignal(obs.CodeBlockLanguageChipRendered(
            language: null,
            shown: true,
            mode: obs.CodeBlockChipMode.render,
            timestamp: now,
          )),
          isTrue,
        );
      });
    });
  });

  group('exportSnapshot() 包含 render 事件', () {
    test('renderCount + renders 列表', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CodeBlockThemeRendered(
        isDark: true,
        themeName: 'atomOneDark',
        language: 'python',
        timestamp: DateTime.now(),
      ));
      svc.recordRender(obs.CodeBlockLanguageChipRendered(
        language: 'python',
        shown: true,
        mode: obs.CodeBlockChipMode.edit,
        timestamp: DateTime.now(),
      ));
      svc.recordRender(obs.PdfCjkFontFallbackEvent(
        fontLoaded: true,
        fallbackActive: true,
        language: 'python',
        codeLength: 30,
        hasCjk: true,
        timestamp: DateTime.now(),
      ));

      final snapshot = svc.exportSnapshot();
      expect(snapshot['renderCount'], equals(3));
      final renders = snapshot['renders'] as List;
      expect(renders.length, equals(3));
      expect((renders[0] as Map)['type'], equals('CodeBlockThemeRendered'));
      expect((renders[1] as Map)['type'], equals('CodeBlockLanguageChipRendered'));
      expect((renders[2] as Map)['type'], equals('PdfCjkFontFallbackEvent'));
    });
  });
}
