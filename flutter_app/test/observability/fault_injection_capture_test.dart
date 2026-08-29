/// Fault-injection capture test (v0.1 infrastructure capability proof).
///
/// Proves the ADI pipeline can obtain *reliable evidence* from a *known*,
/// deterministic failure — no flaky real-world bug required. The test flips
/// [FaultInjection.enabled], pumps a real [CodeBlock] (whose coordinator points
/// at a FULL [ObservabilityService]), and asserts the injected RenderOverflow is
/// captured end-to-end: error snapshot + full causal chain + exportable zip.
///
/// The CLI classification (RenderOverflow) and chain rendering are proven
/// separately by `tools/adi/test/e2e` against the offline fixture that mirrors
/// exactly the JSON this runtime produces. Together they prove the contract.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/editor_history.dart';
import 'package:tafcm/core/observability/adi_storage.dart';
import 'package:tafcm/core/observability/fault_injection.dart';
import 'package:tafcm/core/observability/models.dart' as obs;
import 'package:tafcm/core/observability/observability_service.dart';
import 'package:tafcm/core/observability/trace_context.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/blocks/code/code_block.dart';
import 'package:tafcm/presentation/editor/editor_coordinator.dart';
import 'package:tafcm/presentation/editor/editor_scope.dart';
import 'package:tafcm/presentation/editor/in_memory_document_editor.dart';
import 'package:tafcm/presentation/states/block_view_state.dart';
import 'package:tafcm/presentation/themes/editor_tokens.dart';

/// Mirror of `classifyErrorType` in `tools/adi/import_zip.dart`.
///
/// Kept inline so the Flutter test asserts the *same* classification rule the
/// CLI applies, without coupling the app package to the CLI package.
String classifyErrorType(String rawType, String message) {
  final m = message.toLowerCase();
  if (m.contains('overflowed') || m.contains('overflow') || m.contains('renderflex')) {
    return 'RenderOverflow';
  }
  return rawType;
}

void main() {
  group('FaultInjection deterministic RenderOverflow capture', () {
    late Directory tempDir;
    late ObservabilityService service;
    void Function(FlutterErrorDetails details)? originalOnError;

    setUp(() {
      // Enable the deterministic fault so CodeBlock manufactures an overflow.
      FaultInjection.enabled = true;
      tempDir = Directory.systemTemp.createTempSync('adi_fi_');
      // Explicitly initialize the ADI schema dirs (observations/traces/...):
      // AdiStorageImpl skips initialize() when the root dir already exists,
      // which is the case here because createTempSync creates it.
      final storage = AdiStorageImpl(tempDir.path)..initialize();
      service = ObservabilityService.full(adiStorage: storage);
    });

    tearDown(() {
      FaultInjection.enabled = false;
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets(
        'CodeBlock fault -> captured as RenderOverflow with full causal chain',
        (tester) async {
      // Emulate main.dart: route real FlutterErrors (incl. the injected
      // RenderOverflow) into observability capture as a GlobalError, so the
      // Agent sees the raw "overflowed" message and the CLI classifies it.
      // NOTE: must be set here (inside the test body), NOT in setUp — the test
      // binding installs its own FlutterError.onError after setUp runs.
      originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        service.captureError(
          type: 'GlobalError',
          message: details.exceptionAsString(),
        );
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      // 1. Emulate the canonical chain the real coordinator records leading up
      //    to the render: interaction -> command -> transaction.
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

      // 2. Build a real CodeBlock whose coordinator points at the FULL service,
      //    so its render records a CodeBlockThemeRendered span before overflow.
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
      final codeBlock = CodeBlock(
        state: BlockViewState(id: blockId),
        element: const CodeElement(code: 'void main(){}', language: 'dart'),
        coordinator: coordinator,
      );

      // 3. Pump inside a bounded container. The injected fault child overflows
      //    its parent -> FlutterError.onError -> captureError(GlobalError,
      //    '...overflowed...'). A single pump is enough to lay out + fire.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [EditorTokens.light]),
          home: Scaffold(
            body: EditorScope(
              coordinator: coordinator,
              child: SizedBox(
                width: 300,
                height: 200,
                child: codeBlock,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 4. The injected RenderOverflow was captured as a GlobalError with an
      //    overflow message (exactly what main.dart routes to captureError).
      final snapshot = service.lastErrorSnapshot;
      expect(snapshot, isNotNull, reason: 'injected RenderOverflow must be captured');
      expect(snapshot!.type, 'GlobalError');
      expect(snapshot.message.toLowerCase(), contains('overflow'),
          reason: 'raw message must contain overflow so CLI can classify it');

      // 5. The same classification rule the CLI applies yields RenderOverflow
      //    (not a bare GlobalError / FlutterError).
      expect(classifyErrorType(snapshot.type, snapshot.message), 'RenderOverflow');

      // 6. The runtime produced the full chain the CLI transcribes:
      //    interaction + command + transaction + (render via CodeBlock) + error.
      final exported = service.exportSnapshot();
      expect((exported['interactions'] as List).isNotEmpty, isTrue,
          reason: 'interaction span must be present');
      expect((exported['commands'] as List).isNotEmpty, isTrue,
          reason: 'command span must be present');
      expect((exported['transactions'] as List).isNotEmpty, isTrue,
          reason: 'transaction span must be present');
      expect((exported['renders'] as List).isNotEmpty, isTrue,
          reason: 'CodeBlock must have recorded a render span before overflow');

      // 7. The diagnostic zip is exportable and consumable by the ADI importer
      //    (metadata/trace/snapshot/invariant_report present in the package).
      //    NOTE: runAsync is required — ExportPipeline does real async file I/O
      //    which never completes inside testWidgets' FakeAsync zone.
      final zipPath = await tester.runAsync(
        () => service.exportDiagnosticZip(outputDir: tempDir.path),
      );
      expect(zipPath, isNotNull);
      expect(File(zipPath!).existsSync(), isTrue,
          reason: 'exported zip must exist for the ADI importer');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  });
}
