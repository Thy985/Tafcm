/// P0 修复验证测试：invariant_report 占位符 → 真实结果（G1 修复）。
///
/// **修复前**：`invariant_report.json` 永远为 `result: not_checked`，
/// 用户导出诊断 zip 后看不到最近一次 invariant check 结果。
/// **修复后**：`InvariantReportSnapshot` 缓存最近一次 `checkAll` 结果，
/// ExportPipeline 据此生成真实报告。
///
/// 验证 4 项：
/// - TC-1: App 启动后尚未运行 invariant check → `lastInvariantReport == null`
/// - TC-2: `updateInvariantReport` 写入后 `lastInvariantReport` 可读
/// - TC-3: 注入快照后 ExportPipeline 生成的 zip 含真实 `result` 字段
/// - TC-4: OFF 模式 `updateInvariantReport` 空操作（不写入）
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tafcm/core/observability/models.dart';
import 'package:tafcm/core/observability/observability_service.dart';

/// 路径提供桩：避免 path_provider 在测试环境抛 MissingPluginException。
class _MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => _testDir;
}

/// 测试输出目录（Windows 兼容：用系统 temp 目录）。
String get _testDir =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}ff_test_invariant_report';

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

  group('G1-TC-1: lastInvariantReport 初始为 null', () {
    test('新建 service 后 lastInvariantReport 应为 null', () {
      final svc = ObservabilityService();
      expect(svc.lastInvariantReport, isNull,
          reason: 'App 启动后尚未运行 invariant check,应返回 null 占位。');
    });
  });

  group('G1-TC-2: updateInvariantReport 写入可读', () {
    test('passed 快照写入后 getter 返回相同快照', () {
      final svc = ObservabilityService();
      final snap = InvariantReportSnapshot(
        checkedAt: DateTime.utc(2026, 8, 10, 12),
        result: InvariantCheckResult.passed,
        failedNames: const [],
        allNames: const [
          'CursorExists',
          'SelectionValid',
          'BlockTreeAcyclic',
          'ParentChildValid',
          'EditorNotEmpty',
          'HistoryConsistent',
        ],
      );
      svc.updateInvariantReport(snap);
      final got = svc.lastInvariantReport;
      expect(got, isNotNull);
      expect(got!.result, equals(InvariantCheckResult.passed));
      expect(got.failedNames, isEmpty);
      expect(got.allNames, hasLength(6));
    });

    test('failed 快照写入后 getter 返回 failed + failedNames', () {
      final svc = ObservabilityService();
      svc.updateInvariantReport(InvariantReportSnapshot(
        checkedAt: DateTime.now(),
        result: InvariantCheckResult.failed,
        failedNames: const ['SelectionValid', 'BlockTreeAcyclic'],
        allNames: const ['CursorExists', 'SelectionValid'],
      ));
      final got = svc.lastInvariantReport!;
      expect(got.result, equals(InvariantCheckResult.failed));
      expect(got.failedNames, equals(['SelectionValid', 'BlockTreeAcyclic']));
    });
  });

  group('G1-TC-3: OFF 模式 updateInvariantReport 空操作', () {
    test('OFF 模式 service 调用 updateInvariantReport 后仍为 null', () {
      final svc = ObservabilityService.off();
      svc.updateInvariantReport(InvariantReportSnapshot(
        checkedAt: DateTime.now(),
        result: InvariantCheckResult.passed,
        failedNames: const [],
        allNames: const ['CursorExists'],
      ));
      expect(svc.lastInvariantReport, isNull,
          reason: 'OFF 模式 tree-shaking,updateInvariantReport 应空操作。');
    });
  });

  group('G1-TC-4: ExportPipeline zip 含真实 invariant_report.json', () {
    test('缓存为 passed → zip report.result == passed', () async {
      final svc = ObservabilityService();
      svc.updateInvariantReport(InvariantReportSnapshot(
        checkedAt: DateTime.utc(2026, 8, 10, 12, 30),
        result: InvariantCheckResult.passed,
        failedNames: const [],
        allNames: const [
          'CursorExists',
          'SelectionValid',
          'BlockTreeAcyclic',
          'ParentChildValid',
          'EditorNotEmpty',
          'HistoryConsistent',
        ],
      ));

      final zipPath = await svc.exportDiagnosticZip(
        outputDir: _testDir,
      );
      expect(zipPath, isNotNull, reason: 'exportDiagnosticZip 应返回非 null 路径');

      final bytes = await File(zipPath!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final reportFile = archive.findFile('invariant_report.json');
      expect(reportFile, isNotNull, reason: 'invariant_report.json 必须存在');

      final content = utf8.decode(reportFile!.content as List<int>);
      expect(content, contains('"result": "passed"'),
          reason: 'G1 修复前此处永远为 "not_checked"');
      expect(content, contains('"lastCheckTime"'));
      expect(content, contains('2026-08-10T12:30'));
    });

    test('缓存为 failed → zip report.result == failed + failedNames 含具体项',
        () async {
      final svc = ObservabilityService();
      svc.updateInvariantReport(InvariantReportSnapshot(
        checkedAt: DateTime.utc(2026, 8, 10, 13),
        result: InvariantCheckResult.failed,
        failedNames: const ['SelectionValid', 'HistoryConsistent'],
        allNames: const [
          'CursorExists',
          'SelectionValid',
          'BlockTreeAcyclic',
          'ParentChildValid',
          'EditorNotEmpty',
          'HistoryConsistent',
        ],
      ));

      final zipPath = await svc.exportDiagnosticZip(
        outputDir: _testDir,
      );
      expect(zipPath, isNotNull);
      final bytes = await File(zipPath!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final content = utf8
          .decode(archive.findFile('invariant_report.json')!.content as List<int>);

      expect(content, contains('"result": "failed"'));
      expect(content, contains('SelectionValid'));
      expect(content, contains('HistoryConsistent'));
      expect(content, isNot(contains('not_checked')),
          reason: '有缓存时不应再返回占位符');
    });

    test('缓存为空 → zip report.result == not_checked（占位符保留）',
        () async {
      final svc = ObservabilityService(); // 未调用 updateInvariantReport
      final zipPath = await svc.exportDiagnosticZip(
        outputDir: _testDir,
      );
      expect(zipPath, isNotNull);
      final bytes = await File(zipPath!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final content = utf8
          .decode(archive.findFile('invariant_report.json')!.content as List<int>);

      expect(content, contains('"result": "not_checked"'));
      expect(content, contains('尚未运行'),
          reason: '占位符应带 note 说明 App 启动后未运行 invariant check');
    });
  });
}