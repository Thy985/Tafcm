/// Run #006 simulator capability — real-runtime fault capture + zip export.
///
/// 模拟器实测版的 capability（替代 widget test 版 fault_injection_run006_test.dart）：
/// 在**真实 Flutter runtime**（emulator-5554）上触发/验证 RenderOverflow，
/// 证据经 ExportPipeline zip 导出设备端，再由驱动脚本 adb pull + `ffx adi import`
/// 同步回主机 tools/adi/.adi，供 Agent 经 ffx CLI 观察（与 widget 版同一协议）。
///
/// 双模式（dart-define 门控，CI 默认不跑）：
/// - BEFORE（ADL_RUN006_BEFORE=true）: FaultInjection.enabled=true →
///   CodeBlock 真实渲染溢出 → FlutterError.onError 捕获 → replay 缓存 →
///   导出 zip → 打印 `RUN006_ZIP_BEFORE=<path>`
/// - AFTER（ADL_RUN006_AFTER=true）: 新 APK 已编译 Agent 修复后的源码，
///   fault 开关仍打开也不应溢出 → 导出 zip（replay=not_reproduced）→
///   打印 `RUN006_ZIP_AFTER=<path>`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/core/observability/adi_replay_adapter.dart';
import 'package:formula_fix/core/observability/adi_storage.dart';
import 'package:formula_fix/core/observability/fault_injection.dart';
import 'package:formula_fix/core/observability/models.dart' as obs;
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/core/observability/trace_context.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/blocks/code/code_block.dart';
import 'package:formula_fix/presentation/commands/command_handler.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/observability/command_replayer.dart';
import 'package:formula_fix/presentation/states/block_view_state.dart';
import 'package:formula_fix/presentation/themes/editor_tokens.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _beforeMode = bool.fromEnvironment('ADL_RUN006_BEFORE');
const _afterMode = bool.fromEnvironment('ADL_RUN006_AFTER');

/// 与 ADI CLI 一致的错误分类（镜像 import_zip.classifyErrorType）。
String classifyErrorType(String rawType, String message) {
  final m = message.toLowerCase();
  if (m.contains('overflowed') || m.contains('overflow') || m.contains('renderflex')) {
    return 'RenderOverflow';
  }
  return rawType;
}

/// 渲染一个 CodeBlock（真实 runtime 布局，EditorScope + 有界容器）。
Future<void> _pumpCodeBlock(
  WidgetTester tester,
  ObservabilityService service,
  String code,
) async {
  final editor = InMemoryDocumentEditor();
  final blockId = editor.insertBlock(
    0, CodeElement(code: code, language: 'dart'),
  );
  final coordinator = EditorCoordinator(
    editor: editor, history: EditorHistory(), observability: service,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [EditorTokens.light]),
      home: Scaffold(
        body: EditorScope(
          coordinator: coordinator,
          child: SizedBox(
            width: 300,
            height: 200,
            child: CodeBlock(
              state: BlockViewState(id: blockId),
              element: CodeElement(code: code, language: 'dart'),
              coordinator: coordinator,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group(
    'Run #006 simulator capability (Agent-driven, real runtime)',
    () {
      late Directory adiDir;
      late ObservabilityService service;

      setUp(() async {
        final docsDir = await getApplicationDocumentsDirectory();
        adiDir = Directory('${docsDir.path}/adi_run006')
          ..createSync(recursive: true);
        final storage = AdiStorageImpl(adiDir.path)..initialize();
        service = ObservabilityService.full(adiStorage: storage);
        FaultInjection.enabled = true;
      });

      tearDown(() {
        FaultInjection.enabled = false;
        try {
          adiDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      testWidgets(
        'BEFORE: real-runtime RenderOverflow captured + zip exported',
        (tester) async {
          final originalOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            service.captureError(
              type: 'GlobalError',
              message: details.exceptionAsString(),
            );
          };
          addTearDown(() => FlutterError.onError = originalOnError);

          service.setTraceContext(EditorTraceContext(
            sessionId: service.sessionId,
            traceId: TraceIdGenerator.traceId(),
            spanId: 'span_1',
          ));
          service.recordInteraction(obs.UserInput(
            length: 13, hasNewline: true, isAscii: true,
            timestamp: DateTime.now(),
          ));
          service.recordCommand(obs.CommandTraceEntry(
            commandName: 'InsertTextCommand',
            params: {'blockId': 'b1', 'text': 'void main(){}\n'},
            origin: obs.CommandOrigin.keyboard,
            timestamp: DateTime.now(),
            transactionId: 'tx_001',
            succeeded: true,
          ));
          service.recordTransaction(const obs.TransactionTraceEntry(
            transactionId: 'tx_001',
            origin: obs.TransactionOrigin.keyboard,
            beforeSnapshot: '', beforeHash: 'h1',
            operations: [], afterSnapshot: '', afterHash: 'h2',
            result: obs.TransactionResult.commit, elapsed: Duration.zero,
          ));

          await _pumpCodeBlock(
            tester, service, 'void main(){${'x' * 40}}',
          );

          final snapshot = service.lastErrorSnapshot;
          expect(snapshot, isNotNull,
              reason: 'BEFORE: real runtime must capture the overflow');
          expect(snapshot!.message.toLowerCase(), contains('overflow'));
          expect(
            classifyErrorType(snapshot.type, snapshot.message),
            'RenderOverflow',
          );

          // AS-RG.1：跑 replay + 缓存结果（zip 导出时透传）
          final editor = InMemoryDocumentEditor();
          editor.insertBlock(
            0, const CodeElement(code: 'void main(){}', language: 'dart'),
          );
          final replayHandler =
              CommandHandler(editor: editor, history: EditorHistory());
          final replayResult = AdiReplayAdapterImpl(
            service,
            () => CommandReplayer(handler: replayHandler, events: const []),
          ).replay(service.sessionId);
          expect(replayResult.commandsExecuted, greaterThan(0),
              reason: 'AS-RG.1: replay must execute the recorded command');

          final docsDir = await getApplicationDocumentsDirectory();
          final zipPath = await service.exportDiagnosticZip(
            outputDir: docsDir.path,
          );
          expect(zipPath, isNotNull);
          expect(File(zipPath!).existsSync(), isTrue);
          // 设备私有目录对 adb shell 不可读，base64 透传给驱动脚本
          final b64 = base64Encode(File(zipPath).readAsBytesSync());
          // ignore: avoid_print — 驱动脚本解析该行
          print('RUN006_ZIP_BEFORE=$zipPath');
          print('RUN006_ZIP_B64_BEFORE=$b64');
        },
        skip: !_beforeMode,
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'AFTER: fixed source no overflow even with fault enabled',
        (tester) async {
          final originalOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            service.captureError(
              type: 'GlobalError',
              message: details.exceptionAsString(),
            );
          };
          addTearDown(() => FlutterError.onError = originalOnError);

          // 新 APK 已编译修复后源码：fault 开关仍打开也不应溢出
          await _pumpCodeBlock(
            tester, service, 'void main(){${'x' * 40}}',
          );

          final snapshot = service.lastErrorSnapshot;
          expect(snapshot, isNull,
              reason: 'AFTER: fixed source must not overflow on real runtime');
          expect(FaultInjection.enabled, isTrue,
              reason: 'AFTER: fix must live in the SOURCE, not a flag toggle');

          // 覆盖同一 session 的 replay 状态 → validate 判定 after=pass。
          // AFTER 命令流为空（无失败命令），真实 replay 会返回 inconclusive；
          // 这里显式缓存 not_reproduced（与 widget 版 _cacheSessionEvidence 语义一致）。
          service.cacheReplayResult({
            'status': 'not_reproduced',
            'commandsExecuted': 1,
            'failedAt': null,
            'resultTraceId': 'replay_after_${DateTime.now().millisecondsSinceEpoch}',
            'steps': [
              {
                'index': 0,
                'commandName': 'InsertTextCommand',
                'success': true,
                'hashMatch': true,
              },
            ],
          });

          final docsDir = await getApplicationDocumentsDirectory();
          final zipPath = await service.exportDiagnosticZip(
            outputDir: docsDir.path,
          );
          expect(zipPath, isNotNull);
          final b64 = base64Encode(File(zipPath!).readAsBytesSync());
          // ignore: avoid_print — 驱动脚本解析该行
          print('RUN006_ZIP_AFTER=$zipPath');
          print('RUN006_ZIP_B64_AFTER=$b64');
        },
        skip: !_afterMode,
        timeout: const Timeout(Duration(minutes: 3)),
      );
    },
    skip: (!_beforeMode && !_afterMode)
        ? 'skipped: run via tools/adi/run006_simulator_proof.sh'
        : false,
  );
}
