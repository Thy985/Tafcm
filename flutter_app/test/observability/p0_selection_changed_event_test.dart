/// P0 修复验证测试：Selection 实时变化可观测（G3 修复）。
///
/// **修复前**：selection 仅在 `WrapSelectionCommand` 中携带，
/// 光标跳到不存在字符类 bug 无独立可观测信号。
/// **修复后**：
/// - 新增 [SelectionChangedEvent] 模型,含 baseOffset / extentOffset /
///   sourceLength / blockId / source 字段
/// - 新增 [SelectionChangeSource] 枚举区分 keyboard / tap / programmatic / autoPair / ime
/// - [ObservabilityService.recordInteraction] 接收新事件,入 RingBuffer
/// - [ExportPipeline] 在 zip 报告中序列化新事件
/// - [BaseBlockState._onSelectionChanged] postFrame callback 调用 recordInteraction
///
/// 验证 4 项：
/// - TC-1: SelectionChangedEvent 模型字段 + isOutOfBounds / isReversed 自描述
/// - TC-2: ObservabilityService.recordInteraction 接入新事件,description 正确
/// - TC-3: exportSnapshot 包含 SelectionChangedEvent
/// - TC-4: ExportPipeline zip 序列化新事件
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tafcm/core/observability/models.dart' as obs;
import 'package:tafcm/core/observability/observability_service.dart';

/// 路径提供桩：避免 path_provider 在测试环境抛 MissingPluginException。
class _MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => _testDir;
}

/// 测试输出目录（Windows 兼容：用系统 temp 目录）。
String get _testDir =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}ff_test_selection_changed';

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

  group('G3-TC-1: SelectionChangedEvent 模型', () {
    test('isOutOfBounds: extentOffset > sourceLength → true', () {
      final ev = obs.SelectionChangedEvent(
        baseOffset: 0,
        extentOffset: 15,
        sourceLength: 10,
        blockId: 'b1',
        source: obs.SelectionChangeSource.keyboard,
        timestamp: DateTime.now(),
      );
      expect(ev.isOutOfBounds, isTrue,
          reason: 'selection 越界（extent > sourceLength）→ ArrayIndexOutOfBounds 风险');
    });

    test('isOutOfBounds: baseOffset < 0 → true', () {
      final ev = obs.SelectionChangedEvent(
        baseOffset: -1,
        extentOffset: 5,
        sourceLength: 10,
        blockId: 'b1',
        source: obs.SelectionChangeSource.keyboard,
        timestamp: DateTime.now(),
      );
      expect(ev.isOutOfBounds, isTrue);
    });

    test('isReversed: baseOffset > extentOffset → true', () {
      final ev = obs.SelectionChangedEvent(
        baseOffset: 5,
        extentOffset: 2,
        sourceLength: 10,
        blockId: 'b1',
        source: obs.SelectionChangeSource.tap,
        timestamp: DateTime.now(),
      );
      expect(ev.isReversed, isTrue,
          reason: 'selection 反转是 SelectionValid invariant 失败前兆');
      expect(ev.isOutOfBounds, isTrue);
    });

    test('正常 selection (collapsed at offset 5) → 全部 false', () {
      final ev = obs.SelectionChangedEvent(
        baseOffset: 5,
        extentOffset: 5,
        sourceLength: 10,
        blockId: 'b1',
        source: obs.SelectionChangeSource.tap,
        timestamp: DateTime.now(),
      );
      expect(ev.isOutOfBounds, isFalse);
      expect(ev.isReversed, isFalse);
    });
  });

  group('G3-TC-2: ObservabilityService.recordInteraction 接入新事件', () {
    test('recordInteraction 接收 SelectionChangedEvent 入 tracer', () {
      final svc = ObservabilityService();
      svc.recordInteraction(obs.SelectionChangedEvent(
        baseOffset: 3,
        extentOffset: 7,
        sourceLength: 20,
        blockId: 'block_test',
        source: obs.SelectionChangeSource.keyboard,
        timestamp: DateTime.now(),
      ));
      expect(svc.interactionTracer.count, equals(1));
      final ev = svc.interactionTracer.entries.last
          as obs.SelectionChangedEvent;
      expect(ev.baseOffset, equals(3));
      expect(ev.extentOffset, equals(7));
      expect(ev.blockId, equals('block_test'));
      expect(ev.source, equals(obs.SelectionChangeSource.keyboard));
    });

    test('recordInteraction 多种 SelectionChangeSource 都被记录', () {
      final svc = ObservabilityService();
      for (final source in obs.SelectionChangeSource.values) {
        svc.recordInteraction(obs.SelectionChangedEvent(
          baseOffset: 0,
          extentOffset: 1,
          sourceLength: 10,
          blockId: 'b',
          source: source,
          timestamp: DateTime.now(),
        ));
      }
      expect(svc.interactionTracer.count, equals(5));
    });
  });

  group('G3-TC-3: exportSnapshot 包含 SelectionChangedEvent', () {
    test('record 后 exportSnapshot 含 type=SelectionChangedEvent', () {
      final svc = ObservabilityService();
      svc.recordInteraction(obs.SelectionChangedEvent(
        baseOffset: 1,
        extentOffset: 4,
        sourceLength: 12,
        blockId: 'b_x',
        source: obs.SelectionChangeSource.autoPair,
        timestamp: DateTime.now(),
      ));
      final snap = svc.exportSnapshot();
      final interactions = snap['interactions'] as List;
      expect(interactions, hasLength(1));
      final entry = interactions.single as Map<String, Object?>;
      expect(entry['type'], equals('SelectionChangedEvent'));
      expect(entry['baseOffset'], equals(1));
      expect(entry['extentOffset'], equals(4));
      expect(entry['sourceLength'], equals(12));
      expect(entry['blockId'], equals('b_x'));
      expect(entry['source'], equals('autoPair'));
    });
  });

  group('G3-TC-4: ExportPipeline zip 序列化新事件', () {
    test('trace.json interactions 数组含 SelectionChangedEvent', () async {
      final svc = ObservabilityService();
      svc.recordInteraction(obs.SelectionChangedEvent(
        baseOffset: 2,
        extentOffset: 8,
        sourceLength: 20,
        blockId: 'block_zz',
        source: obs.SelectionChangeSource.ime,
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

      expect(content, contains('SelectionChangedEvent'));
      expect(content, contains('"baseOffset": 2'));
      expect(content, contains('"extentOffset": 8'));
      expect(content, contains('"source": "ime"'));
      expect(content, contains('block_zz'));
    });

    test('混合 IME composing + selection changed 事件都进 zip', () async {
      final svc = ObservabilityService();
      svc.recordInteraction(obs.ImeComposingStateChangedEvent(
        composingStart: 0,
        composingEnd: 5,
        sourceLength: 10,
        newState: obs.ComposingState.composing,
        blockId: 'block_1',
        timestamp: DateTime.now(),
      ));
      svc.recordInteraction(obs.SelectionChangedEvent(
        baseOffset: 3,
        extentOffset: 7,
        sourceLength: 10,
        blockId: 'block_1',
        source: obs.SelectionChangeSource.ime,
        timestamp: DateTime.now(),
      ));

      final zipPath = await svc.exportDiagnosticZip(
        outputDir: _testDir,
      );
      expect(zipPath, isNotNull);
      final bytes = await File(zipPath!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final content = utf8.decode(archive.findFile('trace.json')!.content as List<int>);

      expect(content, contains('ImeComposingStateChangedEvent'));
      expect(content, contains('SelectionChangedEvent'));
      // switch 表达式穷举,类型安全
      final imeCount = '"ImeComposingStateChangedEvent"'.allMatches(content).length;
      final selCount = '"SelectionChangedEvent"'.allMatches(content).length;
      expect(imeCount, greaterThanOrEqualTo(1));
      expect(selCount, greaterThanOrEqualTo(1));
    });
  });
}