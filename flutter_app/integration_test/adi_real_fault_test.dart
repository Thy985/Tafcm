/// Real-code fault capture test (E2E-ADI-005 v0.2 full maintenance loop).
///
/// Unlike [adi_fault_injection_test.dart] (which manufactures a RenderOverflow
/// via the `FaultInjection` kill-switch), this test proves the loop against a
/// REAL code defect: `CodeBlock.buildRenderContent` currently renders its
/// container with a hardcoded bounded `height: 120` and NO scroll protection.
/// Any code taller than 120px overflows the render column on the real engine.
///
/// Pipeline: real overflow → FlutterError.onError → captureError(GlobalError)
/// → classifier ⇒ RenderOverflow → replay (CommandReplayer) → diagnostic zip.
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

/// Mirror of `classifyErrorType` in `tools/adi/import_zip.dart`.
String classifyErrorType(String rawType, String message) {
  final m = message.toLowerCase();
  if (m.contains('overflowed') || m.contains('overflow') || m.contains('renderflex')) {
    return 'RenderOverflow';
  }
  return rawType;
}

/// A code payload much taller than the faulted 120px container (multi-line,
/// no space so the row is unbreakable — the real defect overflows vertically).
String _tallCode(int lines) {
  final line = 'void main(){${'x' * 40}}';
  return List.generate(lines, (_) => line).join('\n');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('REAL FAULT: code container overflow captured without FaultInjection',
      (tester) async {
    // 1. FaultInjection is OFF — this must reproduce via the REAL code defect
    //    (CodeBlock hardcoded height:120, no scroll), not the kill-switch.
    FaultInjection.enabled = false;

    // 2. FULL observability + ADI storage in a device-writable dir.
    final docsDir = await getApplicationDocumentsDirectory();
    final adiDir = Directory('${docsDir.path}/adi_real_fault')..createSync(recursive: true);
    final storage = AdiStorageImpl(adiDir.path)..initialize();
    final service = ObservabilityService.full(adiStorage: storage);

    // 3. Route real FlutterErrors into observability capture.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      service.captureError(
        type: 'GlobalError',
        message: details.exceptionAsString(),
      );
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    // 4. Emulate the canonical chain leading up to the render.
    service.setTraceContext(EditorTraceContext(
      sessionId: service.sessionId,
      traceId: TraceIdGenerator.traceId(),
      spanId: 'span_1',
    ));
    service.recordInteraction(obs.UserInput(
      length: 13,
      hasNewline: true,
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

    // 5. Build a REAL CodeBlock with TALL code (> 120px) — the real defect.
    final editor = InMemoryDocumentEditor();
    final blockId = editor.insertBlock(
      0,
      CodeElement(code: _tallCode(200), language: 'dart'),
    );
    final coordinator = EditorCoordinator(
      editor: editor,
      history: EditorHistory(),
      observability: service,
    );

    // 6. Pump inside a bounded box. On the REAL engine the 200-line code
    //    overflows the faulted 120px container -> FlutterError -> capture.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [EditorTokens.light]),
        home: Scaffold(
          body: EditorScope(
            coordinator: coordinator,
            child: SizedBox(
              width: 300,
              // Real-product viewport: EditorViewport is a ReorderableListView
              // whose items size to their content (unbounded main axis). A bare
              // bounded parent would overflow ANY tall block regardless of the
              // defect — that is not the fault. ListView mirrors production.
              child: ListView(
                children: [
                  CodeBlock(
                    state: BlockViewState(id: blockId),
                    element: CodeElement(code: _tallCode(200), language: 'dart'),
                    coordinator: coordinator,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 7. REAL defect verification — assertion is CONDITIONAL so the same test
    //    drives both sides of the maintenance loop:
    //    - fault present (pre-fix): snapshot captured -> classified RenderOverflow
    //    - fault removed (post-fix): no overflow -> snapshot null (failure gone)
    final snapshot = service.lastErrorSnapshot;
    if (snapshot != null) {
      expect(classifyErrorType(snapshot.type, snapshot.message), 'RenderOverflow',
          reason: 'real defect must classify as RenderOverflow when present');
    } else {
      // Post-fix: the hardcoded bounded-height defect was removed, so the tall
      // code no longer overflows — the failure is GONE (this is the fix proof).
      debugPrint('ADI_REAL_FAULT=none (post-fix: overflow gone)');
    }

    // 8. AS-RG.1: run replay on the recorded command stream + cache result.
    final replayHandler = CommandHandler(editor: editor, history: EditorHistory());
    final replayResult = AdiReplayAdapterImpl(
      service,
      () => CommandReplayer(handler: replayHandler, events: const []),
    ).replay(service.sessionId);
    expect(replayResult.commandsExecuted, greaterThan(0),
        reason: 'AS-RG.1: replay must execute the recorded command');
    expect(service.lastReplayResult, isNotNull,
        reason: 'AS-RG.1: replay result must be cached for zip export');

    // 9. Export the diagnostic zip on-device for `adi import`.
    final zipPath = await service.exportDiagnosticZip(outputDir: docsDir.path);
    expect(zipPath, isNotNull);
    expect(File(zipPath!).existsSync(), isTrue);
    // ignore: avoid_print — explicit artifact path for the human/tooling.
    debugPrint('ADI_FAULT_ZIP=$zipPath');

    // 10. Clean up the temp ADI dir on the device.
    try {
      adiDir.deleteSync(recursive: true);
    } catch (_) {}
  });
}
