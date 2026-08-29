/// P0 可观测事件测试（问题 1 focusOn viewState 缺失 + 问题 4 CJK 字体加载）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/core/observability/models.dart' as obs;
import 'package:tafcm/core/observability/observability_service.dart';

void main() {
  group('FocusOnViewStateCreatedEvent（问题 1，P0）', () {
    test('记录到 renderTracer', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.FocusOnViewStateCreatedEvent(
        blockId: 'block_abc',
        timestamp: DateTime.now(),
      ));
      expect(svc.renderTracer.count, equals(1));
      final event =
          svc.renderTracer.entries.last as obs.FocusOnViewStateCreatedEvent;
      expect(event.blockId, equals('block_abc'));
    });

    test('isRenderSignal 始终为 true（viewState 缺失总是异常）', () {
      expect(
        ObservabilityService.isRenderSignal(
          obs.FocusOnViewStateCreatedEvent(
            blockId: 'block_x',
            timestamp: DateTime.now(),
          ),
        ),
        isTrue,
      );
    });

    test('exportSnapshot 包含 FocusOnViewStateCreatedEvent', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.FocusOnViewStateCreatedEvent(
        blockId: 'block_test',
        timestamp: DateTime.now(),
      ));
      final snapshot = svc.exportSnapshot();
      final renders = snapshot['renders'] as List;
      expect(renders.length, equals(1));
      expect((renders[0] as Map)['type'], equals('FocusOnViewStateCreatedEvent'));
      expect((renders[0] as Map)['blockId'], equals('block_test'));
    });
  });

  group('CjkFontLoadEvent（问题 4，P0）', () {
    test('加载成功记录到 renderTracer', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CjkFontLoadEvent(
        loaded: true,
        timestamp: DateTime.now(),
      ));
      final event =
          svc.renderTracer.entries.last as obs.CjkFontLoadEvent;
      expect(event.loaded, isTrue);
      expect(event.errorMessage, isNull);
    });

    test('加载失败记录 errorMessage', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CjkFontLoadEvent(
        loaded: false,
        errorMessage: 'AssetNotFoundException: NotoSansSC.ttf',
        timestamp: DateTime.now(),
      ));
      final event =
          svc.renderTracer.entries.last as obs.CjkFontLoadEvent;
      expect(event.loaded, isFalse);
      expect(event.errorMessage, isNotNull);
    });

    test('isRenderSignal: loaded=true → not signal（正常）', () {
      expect(
        ObservabilityService.isRenderSignal(obs.CjkFontLoadEvent(
          loaded: true,
          timestamp: DateTime.now(),
        )),
        isFalse,
      );
    });

    test('isRenderSignal: loaded=false → signal（降级风险）', () {
      expect(
        ObservabilityService.isRenderSignal(obs.CjkFontLoadEvent(
          loaded: false,
          errorMessage: 'load failed',
          timestamp: DateTime.now(),
        )),
        isTrue,
      );
    });

    test('exportSnapshot 包含 CjkFontLoadEvent', () {
      final svc = ObservabilityService.light();
      svc.recordRender(obs.CjkFontLoadEvent(
        loaded: false,
        errorMessage: 'test error',
        timestamp: DateTime.now(),
      ));
      final snapshot = svc.exportSnapshot();
      final renders = snapshot['renders'] as List;
      expect(renders.length, equals(1));
      expect((renders[0] as Map)['type'], equals('CjkFontLoadEvent'));
      expect((renders[0] as Map)['loaded'], equals(false));
      expect((renders[0] as Map)['errorMessage'], equals('test error'));
    });
  });
}