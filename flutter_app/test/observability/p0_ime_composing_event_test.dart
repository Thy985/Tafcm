/// P0 修复验证测试：IME composing 状态变化可观测（G2 修复）。
///
/// **修复前**：[ComposingController] 在 composing 状态转换时
/// 无任何独立可观测信号,中文输入法组合中断/死锁/双字符提交类 bug
/// 只能从最终 Command 反推。
/// **修复后**：
/// - [ComposingController] 新增可选 `observer` 回调,每次状态转换时触发
/// - 新增 [ImeComposingStateChangedEvent] 模型,含 composing region /
///   source length / new state / blockId 字段
/// - [ObservabilityService.recordInteraction] 接收新事件,入 RingBuffer
/// - [ExportPipeline] 在 zip 报告中序列化新事件
///
/// 验证 4 项：
/// - TC-1: ComposingController 4 个状态转换（start/update/commitComplete/cancelComplete）触发 observer
/// - TC-2: ImeComposingStateChangedEvent 模型字段完整 + isOutOfBounds 自描述
/// - TC-3: ObservabilityService.recordInteraction 接收新事件,description 正确
/// - TC-4: ExportPipeline 把事件序列化到 zip（trace.json interactions 数组）
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/core/editing/composing_controller.dart';
import 'package:formula_fix/core/editing/composing_state.dart';
import 'package:formula_fix/core/observability/models.dart' as obs;
import 'package:formula_fix/core/observability/observability_service.dart';

/// 路径提供桩：避免 path_provider 在测试环境抛 MissingPluginException。
class _MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => _testDir;
}

/// 测试输出目录（Windows 兼容：用系统 temp 目录）。
String get _testDir =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}ff_test_ime_composing';

/// Mock ComposingHost：模拟 Flutter TextEditingController 的 composing region。
class _MockComposingHost implements ComposingHost {
  @override
  String source;
  @override
  ComposingRegion composing;

  _MockComposingHost({required this.source, required this.composing});

  @override
  void replaceRange(int start, int end, String replacement) {
    source = source.substring(0, start) + replacement + source.substring(end);
  }

  @override
  void restoreSource(String restored) {
    source = restored;
  }
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _MockPathProviderPlatform();
  });

  setUp(() {
    final dir = Directory(_testDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  });

  tearDown(() {
    final dir = Directory(_testDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('G2-TC-1: ComposingController observer 回调', () {
    test('onComposingStart 触发 observer（idle → composing）', () {
      final calls = <Map<String, Object?>>[];
      final host = _MockComposingHost(
        source: 'hello',
        composing: ComposingRegion.empty,
      );
      final controller = ComposingController(
        host,
        observer: ({
          required newState,
          required composing,
          required sourceLength,
          required event,
        }) {
          calls.add({
            'newState': newState,
            'composing': composing,
            'sourceLength': sourceLength,
            'event': event,
          });
        },
      );

      host.composing = const ComposingRegion(start: 5, end: 5);
      controller.onComposingStart();

      expect(calls, hasLength(1));
      expect(calls.single['newState'], equals(ComposingState.composing));
      expect(calls.single['event'], equals(ComposingEvent.start));
      expect((calls.single['composing'] as ComposingRegion).start, equals(5));
    });

    test('onComposingUpdate 触发 observer（composing → composing self-transition）',
        () {
      final calls = <ComposingEvent>[];
      final host = _MockComposingHost(
        source: 'hello',
        composing: const ComposingRegion(start: 0, end: 0),
      );
      final controller = ComposingController(
        host,
        observer: ({
          required newState,
          required composing,
          required sourceLength,
          required event,
        }) {
          calls.add(event);
        },
      );

      controller.onComposingStart();
      host.composing = const ComposingRegion(start: 0, end: 2);
      controller.onComposingUpdate();
      host.composing = const ComposingRegion(start: 0, end: 3);
      controller.onComposingUpdate();

      expect(calls, equals([ComposingEvent.start, ComposingEvent.update, ComposingEvent.update]));
    });

    test('onComposingCommit 触发 observer（commitComplete）', () {
      final calls = <ComposingEvent>[];
      final host = _MockComposingHost(
        source: 'hello',
        composing: const ComposingRegion(start: 0, end: 5),
      );
      final controller = ComposingController(
        host,
        observer: ({required event, required newState, required composing, required sourceLength}) {
          calls.add(event);
        },
      );

      controller.onComposingStart();
      controller.onComposingCommit('hi');

      // commit 内含 commit + commitComplete 两个状态转换,但只 notify commitComplete
      // （commit 在 transitionComposingState 中间态,通知会引入冗余）
      expect(calls, equals([ComposingEvent.start, ComposingEvent.commitComplete]));
    });

    test('onComposingCancel 触发 observer（cancelComplete）', () {
      final calls = <ComposingEvent>[];
      final host = _MockComposingHost(
        source: 'original',
        composing: const ComposingRegion(start: 0, end: 8),
      );
      final controller = ComposingController(
        host,
        observer: ({required event, required newState, required composing, required sourceLength}) {
          calls.add(event);
        },
      );

      controller.onComposingStart();
      controller.onComposingCancel();

      expect(calls, equals([ComposingEvent.start, ComposingEvent.cancelComplete]));
    });

    test('observer 为 null 时不抛异常（向后兼容）', () {
      final host = _MockComposingHost(
        source: 'hi',
        composing: const ComposingRegion(start: 0, end: 2),
      );
      // 无 observer 参数
      final controller = ComposingController(host);
      controller.onComposingStart();
      controller.onComposingCommit('h');
      // 不应抛出（cancel 在 idle 态会抛 StateError,故不调）
    });
  });

  group('G2-TC-2: ImeComposingStateChangedEvent 模型', () {
    test('composingLength getter 计算正确', () {
      final ev = obs.ImeComposingStateChangedEvent(
        composingStart: 2,
        composingEnd: 5,
        sourceLength: 10,
        newState: obs.ComposingState.composing,
        timestamp: DateTime.now(),
      );
      expect(ev.composingLength, equals(3));
      expect(ev.isOutOfBounds, isFalse);
    });

    test('isOutOfBounds: composingEnd > sourceLength → true', () {
      final ev = obs.ImeComposingStateChangedEvent(
        composingStart: 5,
        composingEnd: 15,
        sourceLength: 10,
        newState: obs.ComposingState.composing,
        timestamp: DateTime.now(),
      );
      expect(ev.isOutOfBounds, isTrue,
          reason: 'composing 越界（end > sourceLength）→ 标记异常路径');
    });

    test('composing region 无效（start=-1, end=-1）→ composingLength=-1', () {
      final ev = obs.ImeComposingStateChangedEvent(
        composingStart: -1,
        composingEnd: -1,
        sourceLength: 0,
        newState: obs.ComposingState.idle,
        timestamp: DateTime.now(),
      );
      expect(ev.composingLength, equals(-1));
    });
  });

  group('G2-TC-3: ObservabilityService.recordInteraction 接入新事件', () {
    test('recordInteraction 接收 ImeComposingStateChangedEvent 入 tracer', () {
      final svc = ObservabilityService();
      svc.recordInteraction(obs.ImeComposingStateChangedEvent(
        composingStart: 0,
        composingEnd: 3,
        sourceLength: 10,
        newState: obs.ComposingState.composing,
        blockId: 'block_x',
        timestamp: DateTime.now(),
      ));
      expect(svc.interactionTracer.count, equals(1));
      final ev = svc.interactionTracer.entries.last
          as obs.ImeComposingStateChangedEvent;
      expect(ev.composingStart, equals(0));
      expect(ev.composingEnd, equals(3));
      expect(ev.blockId, equals('block_x'));
    });

    test('exportSnapshot 包含 ImeComposingStateChangedEvent', () {
      final svc = ObservabilityService();
      svc.recordInteraction(obs.ImeComposingStateChangedEvent(
        composingStart: 0,
        composingEnd: 5,
        sourceLength: 10,
        newState: obs.ComposingState.composing,
        blockId: 'b1',
        timestamp: DateTime.now(),
      ));
      final snap = svc.exportSnapshot();
      final interactions = snap['interactions'] as List;
      expect(interactions, hasLength(1));
      final entry = interactions.single as Map<String, Object?>;
      expect(entry['type'], equals('ImeComposingStateChangedEvent'));
      expect(entry['composingStart'], equals(0));
      expect(entry['composingEnd'], equals(5));
      expect(entry['newState'], equals('composing'));
      expect(entry['blockId'], equals('b1'));
    });
  });

  group('G2-TC-4: ExportPipeline zip 序列化新事件', () {
    test('trace.json interactions 数组含 IME composing 事件', () async {
      final svc = ObservabilityService();
      svc.recordInteraction(obs.ImeComposingStateChangedEvent(
        composingStart: 2,
        composingEnd: 7,
        sourceLength: 20,
        newState: obs.ComposingState.composing,
        blockId: 'block_zz',
        timestamp: DateTime.utc(2026, 8, 10, 14, 30),
      ));

      final zipPath = await svc.exportDiagnosticZip(
        outputDir: _testDir,
      );
      expect(zipPath, isNotNull);
      final bytes = await File(zipPath!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final traceFile = archive.findFile('trace.json');
      expect(traceFile, isNotNull);
      final content = utf8.decode(traceFile!.content as List<int>);

      expect(content, contains('ImeComposingStateChangedEvent'));
      expect(content, contains('"composingStart": 2'));
      expect(content, contains('"composingEnd": 7'));
      expect(content, contains('"newState": "composing"'));
      expect(content, contains('block_zz'));
    });
  });
}