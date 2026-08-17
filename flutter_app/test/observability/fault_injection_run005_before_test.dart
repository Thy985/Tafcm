/// Run #005 (before): real production code repair proof — bug present phase.
///
/// 双进程证明的第一阶段：在 fault-injection bug 块仍存在于生产源码时运行，
/// 验证 ADI 能捕获 RenderOverflow（P1），并确认 bug 块确实在生产源码中
/// （P2 前置条件）。
///
/// 由 `tools/adi/run005_proof.sh` 驱动：before 通过后应用生产修复（P2），
/// 再以新进程运行 `fault_injection_run005_after_test.dart` 验证修复生效
/// （P3 运行时 / P4 不变量 / P5 replay / P6 能力回归）。
///
/// 关键区别（Run #004 vs Run #005）：
/// - Run #004: 修复 = 测试标志 `FaultInjection.enabled = false`
/// - Run #005: 修复 = 真实修改 code_block.dart 生产源码（git diff 可审计）
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/editor_history.dart';
import 'package:formula_fix/core/observability/adi_storage.dart';
import 'package:formula_fix/core/observability/fault_injection.dart';
import 'package:formula_fix/core/observability/models.dart' as obs;
import 'package:formula_fix/core/observability/observability_service.dart';
import 'package:formula_fix/core/observability/trace_context.dart';
import 'package:formula_fix/data/models/document.dart';
import 'package:formula_fix/presentation/blocks/code/code_block.dart';
import 'package:formula_fix/presentation/editor/editor_coordinator.dart';
import 'package:formula_fix/presentation/editor/editor_scope.dart';
import 'package:formula_fix/presentation/editor/in_memory_document_editor.dart';
import 'package:formula_fix/presentation/states/block_view_state.dart';
import 'package:formula_fix/presentation/themes/editor_tokens.dart';

/// 从 git 工作树读取 code_block.dart 的生产源码（B 层审计对象）。
String _readProductionCode() {
  final f = File('lib/presentation/blocks/code/code_block.dart');
  return f.readAsStringSync();
}

/// 与 ADI CLI 一致的错误分类：基于消息内容把原始类型归一为稳定枚举。
String classifyErrorType(String rawType, String message) {
  final m = message.toLowerCase();
  if (m.contains('overflowed') || m.contains('overflow') || m.contains('renderflex')) {
    return 'RenderOverflow';
  }
  return rawType;
}

/// 构建一个注入 CodeBlock 的 EditorScope widget（before/after 共用布局）。
Widget _buildCodeBlockApp(CodeBlock codeBlock, EditorCoordinator coordinator) {
  return MaterialApp(
    theme: ThemeData(extensions: const [EditorTokens.light]),
    home: Scaffold(
      body: EditorScope(
        coordinator: coordinator,
        child: SizedBox(width: 300, height: 200, child: codeBlock),
      ),
    ),
  );
}

void main() {
  group('Run #005 (before): bug present — P1 reproduced', () {
    late Directory tempDir;
    late ObservabilityService service;
    void Function(FlutterErrorDetails)? originalOnError;
    final Map<String, dynamic> _evidence = {};

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('adi_run005_before_');
      final storage = AdiStorageImpl(tempDir.path)..initialize();
      service = ObservabilityService.full(adiStorage: storage);
      FaultInjection.enabled = true;
    });

    tearDown(() {
      FaultInjection.enabled = false;
      FlutterError.onError = originalOnError;
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('P2-pre: production source still contains the fault-injection bug',
        () {
      final code = _readProductionCode();
      expect(code, contains('SizedBox(height: 100000)'),
          reason: 'P2-pre: bug block must still be present (committed state)');
      expect(code, contains('FaultInjection.renderOverflowEnabled'),
          reason: 'P2-pre: fault gate must be present');
    });

    testWidgets('P1: ADI captures RenderOverflow from production code',
        (tester) async {
      originalOnError = FlutterError.onError;
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
        length: 20, hasNewline: false, isAscii: true,
        timestamp: DateTime.now(),
      ));
      service.recordCommand(obs.CommandTraceEntry(
        commandName: 'InsertTextCommand',
        params: {'blockId': 'b1', 'text': 'void main(){}\n'},
        origin: obs.CommandOrigin.keyboard,
        timestamp: DateTime.now(),
        transactionId: 'tx_run005',
        succeeded: true,
      ));
      service.recordTransaction(const obs.TransactionTraceEntry(
        transactionId: 'tx_run005',
        origin: obs.TransactionOrigin.keyboard,
        beforeSnapshot: '', beforeHash: 'h1',
        operations: [], afterSnapshot: '', afterHash: 'h2',
        result: obs.TransactionResult.commit, elapsed: Duration.zero,
      ));

      final editor = InMemoryDocumentEditor();
      final blockId = editor.insertBlock(
        0, const CodeElement(code: 'void main(){}', language: 'dart'),
      );
      final coordinator = EditorCoordinator(
        editor: editor, history: EditorHistory(), observability: service,
      );
      final codeBlock = CodeBlock(
        state: BlockViewState(id: blockId),
        element: const CodeElement(code: 'void main(){}', language: 'dart'),
        coordinator: coordinator,
      );

      await tester.pumpWidget(_buildCodeBlockApp(codeBlock, coordinator));
      await tester.pump();

      final snapshot = service.lastErrorSnapshot;
      expect(snapshot, isNotNull, reason: 'P1: bug must be captured');
      expect(snapshot!.type, 'GlobalError');
      expect(snapshot.message.toLowerCase(), contains('overflow'));

      final exported = service.exportSnapshot();
      expect((exported['interactions'] as List).isNotEmpty, isTrue);
      expect((exported['commands'] as List).isNotEmpty, isTrue);
      expect((exported['transactions'] as List).isNotEmpty, isTrue);
      expect((exported['renders'] as List).isNotEmpty, isTrue);

      final storage = AdiStorageImpl(tempDir.path);
      final record = storage.latestErrorRecord();
      expect(record, isNotNull, reason: 'P1: ADI persistence');
      _evidence['session_id'] = record!.sessionId;
      _evidence['trace_id'] = record.traceId;
      _evidence['error_type'] = classifyErrorType(record.errorType, record.message);
      _evidence['message'] = record.message;
      _evidence['before_fix_status'] = 'reproduced';

      print('\n[before] P1 BUG DETECTED: ${snapshot.message}');
      print('         session=${record.sessionId} trace=${record.traceId}');
      print('         chain: ${(exported["interactions"] as List).length}+'
          '${(exported["commands"] as List).length}+'
          '${(exported["transactions"] as List).length}+'
          '${(exported["renders"] as List).length} spans');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('P1-evidence: before state exported for driver audit', () {
      final evidence = <String, dynamic>{
        'run': '005-before',
        'status': 'bug_reproduced',
        'timestamp': DateTime.now().toIso8601String(),
        'summary': 'P1 verified: ADI captured RenderOverflow from production code',
        'predicates': <String, dynamic>{
          'P1_before_reproduced': true,
          'P2_agent_patch_authenticity': 'pending (driver applies fix)',
        },
        'evidence': _evidence,
      };
      File('${tempDir.path}/run005_before_evidence.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(evidence),
      );
      expect(_evidence['session_id'], isNotNull);
      expect(_evidence['error_type'], 'RenderOverflow');
    });
  });
}
