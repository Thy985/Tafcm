/// issue #323 导出协作式取消 — 单元测试（domain 层）。
///
/// 覆盖：
///   - [ExportCancelToken]：幂等取消 / 检查点抛出 [ExportCancelledException]
///   - [ExportProgressNotifier.runWithGuard] 取消语义：Idle→InProgress→Idle
///     （无 Failed）、不触发 onError、异常原样上抛、令牌归还
///   - [ExportProgressNotifier.cancel]：置位令牌 + 状态回 Idle + 后续
///     report() 被忽略；无在途导出时幂等 no-op
///   - 三个导出器的阶段边界检查点：预取消立即中止；逐块检查点命中取消
///
/// widget 层（BACK 确认框 / 浮层 dispose 兜底）在同目录
/// `../presentation/editor/export_back_confirm_widget_test.dart`。
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tafcm/domain/providers/export_progress_provider.dart';
import 'package:tafcm/domain/services/export_cancel_token.dart';
import 'package:tafcm/domain/services/export_service.dart';

void main() {
  group('issue #323 ExportCancelToken', () {
    test('初始未取消；cancel() 置位且幂等', () {
      final token = ExportCancelToken();
      expect(token.isCancelled, isFalse);
      token.cancel();
      expect(token.isCancelled, isTrue);
      token.cancel(); // 幂等
      expect(token.isCancelled, isTrue);
    });

    test('throwIfCancelled：未取消 no-op，已取消抛 ExportCancelledException', () {
      final token = ExportCancelToken();
      expect(token.throwIfCancelled, returnsNormally);
      token.cancel();
      expect(token.throwIfCancelled, throwsA(isA<ExportCancelledException>()));
    });
  });

  group('issue #323 runWithGuard 取消语义', () {
    late ProviderContainer container;
    late ExportProgressNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(exportProgressProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('body 抛 ExportCancelledException：Idle→InProgress→Idle（无 Failed），不进 onError',
        () async {
      final transitions = <ExportState>[];
      container.listen<ExportState>(exportProgressProvider, (_, next) {
        transitions.add(next);
      }, fireImmediately: true);

      Object? onErrorCaptured;
      await expectLater(
        notifier.runWithGuard<void>(
          ExportFormat.pdf,
          () async {
            // body 内模拟管线检查点命中取消。
            throw const ExportCancelledException();
          },
          onError: (e, st) => onErrorCaptured = e,
        ),
        throwsA(isA<ExportCancelledException>()),
      );

      // 序列：Idle → InProgress → Idle（取消不是失败，无 Failed 环节）。
      expect(transitions.length, 3);
      expect(transitions[0], isA<ExportIdleState>());
      expect(transitions[1], isA<ExportInProgressState>());
      expect(transitions[2], isA<ExportIdleState>());
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
      // 取消不是错误：不进 observability 钩子。
      expect(onErrorCaptured, isNull);
    });

    test('body 能经 activeCancelToken 拿到令牌；runWithGuard 结束后令牌归还（null）',
        () async {
      ExportCancelToken? tokenSeenByBody;
      await expectLater(
        notifier.runWithGuard<void>(
          ExportFormat.txt,
          () async {
            tokenSeenByBody = notifier.activeCancelToken;
            // 模拟检查点命中取消（令牌由测试置位，模拟对话框确认路径）。
            tokenSeenByBody!.cancel();
            tokenSeenByBody!.throwIfCancelled();
          },
        ),
        throwsA(isA<ExportCancelledException>()),
      );

      expect(tokenSeenByBody, isNotNull);
      expect(tokenSeenByBody!.isCancelled, isTrue);
      // finally 已归还令牌：下次导出拿到的会是全新令牌。
      expect(notifier.activeCancelToken, isNull);
    });

    test('cancel()：InProgress → Idle，后续 report() 被忽略', () {
      notifier.start(ExportFormat.pdf);
      expect(container.read(exportProgressProvider), isA<ExportInProgressState>());

      notifier.cancel();
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());

      // 已请求取消后，管线残余 report() 不再更新状态（防止浮层复活）。
      notifier.report(const ExportProgress(
        stage: ExportStage.renderingBlocks,
        completed: 5,
        total: 9,
      ));
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
    });

    test('cancel() 无在途导出：幂等 no-op，状态保持 Idle', () {
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
      expect(notifier.cancel, returnsNormally);
      expect(container.read(exportProgressProvider), isA<ExportIdleState>());
      expect(notifier.activeCancelToken, isNull);
    });
  });

  group('issue #323 导出器阶段边界检查点', () {
    testWidgets('PdfExporter：预取消令牌在入口检查点中止（不产出字节）',
        (tester) async {
      final token = ExportCancelToken()..cancel();
      await expectLater(
        MarkdownExporter.exportToPdf('# 标题\n\n正文', cancelToken: token),
        throwsA(isA<ExportCancelledException>()),
      );
    });

    testWidgets('PdfExporter：逐块检查点命中运行中取消', (tester) async {
      final token = ExportCancelToken();
      final future = MarkdownExporter.exportToPdf(
        '# 标题\n\n第一段\n\n第二段\n\n第三段',
        cancelToken: token,
      );
      // 导出是 async 微任务推进：同步置位后首个块边界检查点即命中。
      token.cancel();
      await expectLater(future, throwsA(isA<ExportCancelledException>()));
    });

    testWidgets('WordExporter：预取消令牌在入口检查点中止', (tester) async {
      final token = ExportCancelToken()..cancel();
      await expectLater(
        MarkdownExporter.exportToWord('# 标题\n\n正文', cancelToken: token),
        throwsA(isA<ExportCancelledException>()),
      );
    });

    testWidgets('TextExporter：预取消令牌中止', (tester) async {
      final token = ExportCancelToken()..cancel();
      await expectLater(
        MarkdownExporter.exportToTxt('# 标题\n\n正文', cancelToken: token),
        throwsA(isA<ExportCancelledException>()),
      );
    });

    // 注：TextExporter.export 无 await 挂起点（纯同步推进），运行中取消无法
    // 交错插入——逐块检查点在该导出器仅对「先取消后调用」生效（上方用例），
    // 逐块边界行为已由 PdfExporter 运行中取消用例验证。

    testWidgets('不传令牌：导出正常完成（向后兼容）', (tester) async {
      final bytes = await MarkdownExporter.exportToTxt('# 标题\n\n正文');
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
    });
  });
}
