/// Slice 7 / 3.4.4 导出进度 — 数据/状态/facade 测试。
///
/// 覆盖（Phase 3.4 Task Contract v1.2 §4.1）：
///   - ExportProgress 数据层：fraction / toString
///   - ExportProgressNotifier 状态机：start → report → complete / fail → reset
///   - MarkdownExporter facade 透传 onProgress（via MarkdownExporter.register 注入 fake）
///
/// widget 测试在 `export_progress_widget_test.dart`（同目录），按文件 ≤400 行
/// 拆分（TC-ARCH-7）。
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/domain/providers/export_progress_provider.dart';
import 'package:formula_fix/domain/services/export_service.dart';

/// 假 PDF exporter：仅发出预定 onProgress 序列并返回最小字节（验证
/// MarkdownExporter 透传 onProgress 给下游实现）。
class _ProgressPdfExporter implements PdfExporterInterface {
  final List<ExportProgress> emittedProgress;
  _ProgressPdfExporter(this.emittedProgress);

  @override
  Future<Uint8List> export(
    String markdown, {
    String? title,
    String? author,
    bool isDark = false,
    ExportProgressCallback? onProgress,
    ObservabilityService? observability,
  }) async {
    // 模拟至少 3 次回调：collecting → preRender → rendering → assembling（0/1 → 1/1）。
    onProgress?.call(const ExportProgress(
      stage: ExportStage.collectingFormulas,
      completed: 0,
      total: 1,
    ));
    onProgress?.call(const ExportProgress(
      stage: ExportStage.preRenderingFormulaSvg,
      completed: 5,
      total: 10,
    ));
    onProgress?.call(const ExportProgress(
      stage: ExportStage.renderingBlocks,
      completed: 7,
      total: 10,
    ));
    emittedProgress.addAll(<ExportProgress>[
      const ExportProgress(
        stage: ExportStage.collectingFormulas,
        completed: 0,
        total: 1,
      ),
      const ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 5,
        total: 10,
      ),
      const ExportProgress(
        stage: ExportStage.renderingBlocks,
        completed: 7,
        total: 10,
      ),
    ]);
    return Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
  }
}

void main() {
  group('3.4.4 ExportProgress 数据层', () {
    test('fraction：0/1 = 0.0', () {
      const p = ExportProgress(
        stage: ExportStage.collectingFormulas,
        completed: 0,
        total: 1,
      );
      expect(p.fraction, 0.0);
    });

    test('fraction：total==0 返回 0.0（防御除零）', () {
      const p = ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 0,
        total: 0,
      );
      expect(p.fraction, 0.0);
    });

    test('fraction：5/10 = 0.5', () {
      const p = ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 5,
        total: 10,
      );
      expect(p.fraction, 0.5);
    });

    test('fraction：10/10 = 1.0', () {
      const p = ExportProgress(
        stage: ExportStage.renderingBlocks,
        completed: 10,
        total: 10,
      );
      expect(p.fraction, 1.0);
    });

    test('toString 含阶段名与百分比', () {
      const p = ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 3,
        total: 4,
      );
      expect(p.toString(), contains('preRenderingFormulaSvg'));
      expect(p.toString(), contains('3/4'));
      expect(p.toString(), contains('75.0%'));
    });
  });

  group('3.4.4 ExportProgressNotifier 状态机', () {
    late ProviderContainer container;
    late ExportProgressNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(exportProgressProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('初始 = ExportIdleState', () {
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
    });

    test('start(format) → ExportInProgressState 含 format 与初始进度', () {
      notifier.start(ExportFormat.pdf);
      final state = container.read(exportProgressProvider);
      expect(state, isA<ExportInProgressState>());
      final inProgress = state as ExportInProgressState;
      expect(inProgress.format, ExportFormat.pdf);
      expect(inProgress.progress.stage, ExportStage.collectingFormulas);
    });

    test('report 在 InProgress 期间推进 stage 与 fraction', () {
      notifier.start(ExportFormat.pdf);
      notifier.report(const ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 5,
        total: 10,
      ));
      final state = container.read(exportProgressProvider) as ExportInProgressState;
      expect(state.progress.stage, ExportStage.preRenderingFormulaSvg);
      expect(state.progress.fraction, 0.5);
    });

    test('report 在 Idle 状态被忽略（防御状态不一致）', () {
      notifier.report(const ExportProgress(
        stage: ExportStage.preRenderingFormulaSvg,
        completed: 5,
        total: 10,
      ));
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
    });

    test('complete(format) → ExportCompletedState', () {
      notifier.start(ExportFormat.docx);
      notifier.complete(ExportFormat.docx);
      final state = container.read(exportProgressProvider);
      expect(state, isA<ExportCompletedState>());
      expect((state as ExportCompletedState).format, ExportFormat.docx);
    });

    test('fail(format, kind) → ExportFailedState 含 kind', () {
      notifier.start(ExportFormat.txt);
      notifier.fail(ExportFormat.txt, ExportFailure.renderError);
      final state = container.read(exportProgressProvider);
      expect(state, isA<ExportFailedState>());
      expect((state as ExportFailedState).failure, ExportFailure.renderError);
    });

    test('reset() → ExportIdleState（无论之前状态）', () {
      notifier.start(ExportFormat.pdf);
      notifier.reset();
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
    });
  });

  group('3.4.4 MarkdownExporter facade 透传 onProgress', () {
    late _ProgressPdfExporter fake;
    late List<ExportProgress> emitted;
    late void Function() disposeFake;

    setUp(() {
      emitted = <ExportProgress>[];
      fake = _ProgressPdfExporter(emitted);
      disposeFake = MarkdownExporter.register(pdf: fake);
    });

    tearDown(() {
      disposeFake();
    });

    test('exportToPdf 调用 onProgress 三次（收集→预渲染→渲染）', () async {
      final received = <ExportProgress>[];
      final bytes = await MarkdownExporter.exportToPdf(
        '# 标题\n\n正文',
        onProgress: received.add,
      );
      expect(bytes.isNotEmpty, true);
      expect(received.length, 3);
      expect(received[0].stage, ExportStage.collectingFormulas);
      expect(received[1].stage, ExportStage.preRenderingFormulaSvg);
      expect(received[2].stage, ExportStage.renderingBlocks);
    });

    test('不传 onProgress：仍正常工作（向后兼容）', () async {
      final bytes = await MarkdownExporter.exportToPdf('# hello');
      expect(bytes.isNotEmpty, true);
    });
  });
}
