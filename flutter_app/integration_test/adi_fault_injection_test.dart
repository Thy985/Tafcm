/// Real-device fault-injection test (v0.1 infrastructure proof on hardware).
///
/// Proves the ADI pipeline obtains *reliable evidence* from a *known*,
/// deterministic failure on a REAL device — no flaky real-world bug required:
///
///   FaultInjection.enabled
///     → pump a real [CodeBlock] inside a bounded box
///     → injected child overflows on the real Flutter engine
///     → FlutterError.onError → ObservabilityService.captureError(GlobalError)
///     → classifier (same rule as the ADI CLI) ⇒ RenderOverflow
///
/// The diagnostic zip is exported to app documents so it can be pulled via
/// `adb pull` and fed to `dart run tools/adi/adi.dart import` for the CLI-side
/// proof (covered by E2E-004 offline; this test proves the RUNTIME side).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/core/observability/adi_replay_adapter.dart';
import 'package:tafcm/core/observability/adi_storage.dart';
import 'package:tafcm/core/observability/fault_injection.dart';
import 'package:tafcm/core/observability/models.dart' as obs;
import 'package:tafcm/core/observability/observability_service.dart';
import 'package:tafcm/core/observability/trace_context.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/blocks/code/code_block.dart';
import 'package:tafcm/presentation/commands/command_handler.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/observability/command_replayer.dart';
import 'package:tafcm/presentation/states/block_view_state.dart';
import 'package:tafcm/presentation/themes/editor_tokens.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Mirror of `classifyErrorType` in `tools/adi/import_zip.dart` — the SAME rule
/// the ADI CLI applies. Kept inline so the app package stays decoupled from the
/// CLI package.
String classifyErrorType(String rawType, String message) {
  final m = message.toLowerCase();
  if (m.contains('overflowed') || m.contains('overflow') || m.contains('renderflex')) {
    return 'RenderOverflow';
  }
  return rawType;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('REAL DEVICE: fault-injected RenderOverflow captured deterministically',
      (tester) async {
    // 1. Enable the deterministic fault so the real CodeBlock on this device
    //    manufactures an overflow in the real rendering engine.
    FaultInjection.enabled = true;
    addTearDown(() => FaultInjection.enabled = false);

    // 2. FULL observability + ADI storage in a device-writable dir. Real async
    //    I/O works here (unlike widget tests' FakeAsync zone).
    final docsDir = await getApplicationDocumentsDirectory();
    final adiDir = Directory('${docsDir.path}/adi_fi_test')..createSync(recursive: true);
    final storage = AdiStorageImpl(adiDir.path)..initialize();
    final service = ObservabilityService.full(adiStorage: storage);

    // 3. Route real FlutterErrors (incl. the injected RenderOverflow) into
    //    observability capture — exactly what main.dart does.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      service.captureError(
        type: 'GlobalError',
        message: details.exceptionAsString(),
      );
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    // 4. Emulate the canonical chain leading up to the render:
    //    interaction -> command -> transaction.
    service.setTraceContext(EditorTraceContext(
      sessionId: service.sessionId,
      traceId: TraceIdGenerator.traceId(),
      spanId: 'span_1',
    ));
    service.recordInteraction(obs.UserInput(
      length: 13,
      hasNewline: false,
      isAscii: true,
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
      beforeSnapshot: '',
      beforeHash: 'h1',
      operations: [],
      afterSnapshot: '',
      afterHash: 'h2',
      result: obs.TransactionResult.commit,
      elapsed: Duration.zero,
    ));

    // 5. Build a REAL CodeBlock (real editor state) whose coordinator points at
    //    the FULL service, so its render records CodeBlockThemeRendered spans.
    final editor = InMemoryDocumentEditor();
    final blockId = editor.insertBlock(
      0,
      const CodeElement(code: 'void main(){}', language: 'dart'),
    );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(),
      observability: service,
    );

    // 6. Pump inside a bounded box. On the REAL engine the injected 100000-tall
    //    child overflows -> FlutterError.onError -> captureError(GlobalError).
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
                element: const CodeElement(code: 'void main(){}', language: 'dart'),
                coordinator: coordinator,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 7. The injected RenderOverflow was captured as GlobalError + overflow
    //    message on the real device.
    final snapshot = service.lastErrorSnapshot;
    expect(snapshot, isNotNull,
        reason: 'REAL DEVICE: injected RenderOverflow must be captured');
    expect(snapshot!.type, 'GlobalError');
    expect(snapshot.message.toLowerCase(), contains('overflow'),
        reason: 'raw message must contain overflow so CLI can classify it');

    // 8. The CLI classification rule yields RenderOverflow (not a bare
    //    GlobalError / FlutterError).
    expect(classifyErrorType(snapshot.type, snapshot.message), 'RenderOverflow');

    // 9. The runtime produced the full chain the CLI transcribes.
    final exported = service.exportSnapshot();
    expect((exported['interactions'] as List).isNotEmpty, isTrue);
    expect((exported['commands'] as List).isNotEmpty, isTrue);
    expect((exported['transactions'] as List).isNotEmpty, isTrue);
    expect((exported['renders'] as List).isNotEmpty, isTrue,
        reason: 'CodeBlock must have recorded a render span before overflow');

    // 9.5. AS-RG.1：真机采集侧运行 ReplayEngine 并缓存 replay 结果，
    //      使导出 zip 携带 replay 证据（replay.json + commands.jsonl），
    //      否则 CLI 侧 `adi replay` 永远是 inconclusive（无法 reproduced）。
    final replayHandler = CommandHandler(editor: editor, history: EditorHistory());
    final replayResult = AdiReplayAdapterImpl(
      service,
      () => CommandReplayer(handler: replayHandler, events: const []),
    ).replay(service.sessionId);
    expect(replayResult.commandsExecuted, greaterThan(0),
        reason: 'AS-RG.1: replay must execute the recorded command');
    expect(service.lastReplayResult, isNotNull,
        reason: 'AS-RG.1: replay result must be cached for zip export');

    // 10. Export the diagnostic zip on-device; log the path so it can be
    //     `adb pull`-ed and fed to the ADI CLI (`adi import <zip>`).
    final zipPath = await service.exportDiagnosticZip(outputDir: docsDir.path);
    expect(zipPath, isNotNull, reason: 'REAL DEVICE: zip export must succeed');
    expect(File(zipPath!).existsSync(), isTrue);
    // ignore: avoid_print — explicit artifact path for the human/tooling.
    debugPrint('ADI_FAULT_ZIP=$zipPath');

    // 11. Clean up the temp ADI dir on the device.
    try {
      adiDir.deleteSync(recursive: true);
    } catch (_) {}
  });
}
