/// ADI View 单元测试。
///
/// 验证 AdiErrorView / AdiTraceView / AdiReplayResultView 的 toJson 序列化、
/// AdiHypothesis / AdiObservationQuality 语义。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/adi_view.dart';

void main() {
  group('AdiErrorView', () {
    test('toJson 包含全部字段', () {
      final view = AdiErrorView(
        id: 'obs_001',
        traceId: 'trace_001',
        errorType: 'CommandExecutionError',
        message: 'Block not found',
        replayAvailable: true,
        snapshotPath: '.adi/observations/obs_001.json',
        quality: AdiObservationQuality.complete,
        sessionId: 'sess_1',
        commandName: 'InsertTextCommand',
        hypotheses: [
          AdiHypothesis(
            file: 'lib/core/editing/block_editor.dart',
            line: 42,
            reason: 'Null block reference',
            confidence: 'hypothesis',
          ),
        ],
      );
      final json = view.toJson();

      expect(json['id'], 'obs_001');
      expect(json['errorType'], 'CommandExecutionError');
      expect(json['replayAvailable'], isTrue);
      expect(json['quality'], 'complete');
      expect(json['sessionId'], 'sess_1');
      expect(json['commandName'], 'InsertTextCommand');
      final hyps = json['hypotheses'] as List;
      expect(hyps.length, 1);
      expect((hyps[0] as Map)['file'], 'lib/core/editing/block_editor.dart');
    });

    test('toJson 省略 null 可选字段', () {
      final view = AdiErrorView(
        id: 'obs_002',
        traceId: 'trace_002',
        errorType: 'GlobalError',
        message: 'crash',
        replayAvailable: false,
      );
      final json = view.toJson();

      expect(json.containsKey('snapshotPath'), isFalse);
      expect(json.containsKey('sessionId'), isFalse);
      expect(json.containsKey('commandName'), isFalse);
      expect(json['quality'], 'partial');
    });
  });

  group('AdiTraceView', () {
    test('toJson 包含 spans 列表', () {
      final view = AdiTraceView(
        id: 'trace_001',
        traceId: 'trace_001',
        sessionId: 'sess_1',
        spans: [
          AdiSpanNode(
            spanId: 'span_1',
            parentSpanId: null,
            layer: 'command',
            description: 'InsertTextCommand',
            timestamp: DateTime(2026, 8, 11),
          ),
          AdiSpanNode(
            spanId: 'span_2',
            parentSpanId: 'span_1',
            layer: 'transaction',
            description: 'commit',
            timestamp: DateTime(2026, 8, 11, 0, 0, 1),
          ),
        ],
      );
      final json = view.toJson();

      expect(json['sessionId'], 'sess_1');
      final spans = json['spans'] as List;
      expect(spans.length, 2);
      expect((spans[1] as Map)['parentSpanId'], 'span_1');
    });
  });

  group('AdiReplayResultView', () {
    test('toJson 包含全部步骤', () {
      final view = AdiReplayResultView(
        status: AdiReplayStatus.reproduced,
        failedAt: 'step 3: DeleteCommand',
        commandsExecuted: 5,
        resultTraceId: 'replay_001',
        steps: [
          AdiReplayStepView(
            index: 0,
            commandName: 'InsertTextCommand',
            success: true,
            hashMatch: true,
          ),
          AdiReplayStepView(
            index: 1,
            commandName: 'DeleteCommand',
            success: false,
            hashMatch: false,
            error: 'Block not found',
          ),
        ],
      );
      final json = view.toJson();

      expect(json['status'], 'reproduced');
      expect(json['failedAt'], 'step 3: DeleteCommand');
      expect(json['commandsExecuted'], 5);
      final steps = json['steps'] as List;
      expect(steps.length, 2);
      expect((steps[1] as Map)['error'], 'Block not found');
    });

    test('inconclusive 状态无 failedAt', () {
      final view = AdiReplayResultView(
        status: AdiReplayStatus.inconclusive,
        commandsExecuted: 0,
        resultTraceId: 'replay_002',
        steps: const [],
      );
      final json = view.toJson();

      expect(json['status'], 'inconclusive');
      expect(json.containsKey('failedAt'), isFalse);
    });
  });

  group('AdiInvariantView', () {
    test('allPassed 当 violated 为空时返回 true', () {
      const view = AdiInvariantView(
        violated: [],
        checked: ['CursorExists', 'SelectionValid'],
      );
      expect(view.allPassed, isTrue);
    });

    test('allPassed 当 violated 非空时返回 false', () {
      const view = AdiInvariantView(
        violated: ['CursorExists'],
        checked: ['CursorExists', 'SelectionValid'],
      );
      expect(view.allPassed, isFalse);
    });
  });
}