/// Run #006 capability test — the failure/success capability the Agent drives.
///
/// 供 Agent harness（tools/adi/run006_agent.py）在完整自主修复闭环中调用：
///
/// - before 模式（--dart-define=ADL_RUN006_BEFORE=true）:
///   FaultInjection.enabled=true → CodeBlock 确定性 RenderOverflow → 证据写入
///   真实 `.adi`（ADL_ADI_ROOT），并缓存 replay.json=reproduced +
///   invariant_report.json → Agent 经 `ffx adi latest-error/replay` 观察。
/// - after 模式（--dart-define=ADL_RUN006_AFTER=true）:
///   新进程已编译 Agent 修复后的源码，即使 fault 开关打开也不应再溢出 →
///   把同一 session 的 replay.json 覆盖为 not_reproduced →
///   Agent 经 `ffx adi validate --after-fix <session>` 判定成功。
///
/// 门控：无 before/after define 时整体跳过（CI 默认安全）。
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

const _beforeMode = bool.fromEnvironment('ADL_RUN006_BEFORE');
const _afterMode = bool.fromEnvironment('ADL_RUN006_AFTER');

/// 真实 .adi 根（Agent harness 通过 ffx 读取）。为空时退回系统临时目录。
const _adiRoot = String.fromEnvironment('ADL_ADI_ROOT');

/// Agent 复用同一 session：before 写 reproduced，after 覆盖为 not_reproduced。
const _sessionId = String.fromEnvironment('ADL_SESSION_ID');

/// 与 ADI CLI 一致的错误分类。
String classifyErrorType(String rawType, String message) {
  final m = message.toLowerCase();
  if (m.contains('overflowed') || m.contains('overflow') || m.contains('renderflex')) {
    return 'RenderOverflow';
  }
  return rawType;
}

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

/// 写 replay.json + invariant_report.json + trace.json 到 session/存根目录
/// （AS-RG.1 缓存语义；trace 文件供 `ffx adi trace show` 读取，结构对齐
/// ExportPipeline._buildTrace 的 spans：layer/description/spanId/parent/seq）。
void _cacheSessionEvidence(
  Directory rootDir,
  String sessionId,
  String traceId,
  String replayStatus,
) {
  final sessionDir = Directory('${rootDir.path}/sessions/$sessionId')
    ..createSync(recursive: true);
  final replay = <String, Object?>{
    'status': replayStatus,
    'commandsExecuted': 1,
    'failedAt': replayStatus == 'reproduced'
        ? 'step 0: InsertTextCommand'
        : null,
    'steps': [
      {
        'index': 0,
        'commandName': 'InsertTextCommand',
        'success': replayStatus != 'reproduced',
        'hashMatch': true,
      },
    ],
  };
  File('${sessionDir.path}/replay.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(replay),
  );
  final invariants = <String, Object?>{
    'allNames': ['CursorExists', 'SelectionValid', 'BlockTreeAcyclic'],
    'failedNames': <String>[],
  };
  File('${sessionDir.path}/invariant_report.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(invariants),
  );
  // trace.json：Agent 经 `ffx adi trace show` 观察因果链，render span 名
  // 含 CodeBlockThemeRendered -> Agent 推理定位 CodeBlock 组件。
  final trace = <String, Object?>{
    'sessionId': sessionId,
    'spans': [
      {
        'seq': 0,
        'layer': 'interaction',
        'description': 'UserInput len=20 nl=false ascii=true',
        'spanId': 'span_1',
        'parent': null,
      },
      {
        'seq': 1,
        'layer': 'command',
        'description': 'InsertTextCommand tx=tx_run006',
        'spanId': 'span_2',
        'parent': 'span_1',
      },
      {
        'seq': 2,
        'layer': 'render',
        'description': 'CodeBlockThemeRendered isDark=false theme=github '
            'lang=dart',
        'spanId': 'span_3',
        'parent': 'span_2',
      },
      {
        'seq': 3,
        'layer': 'error',
        'description': 'GlobalError: A RenderFlex overflowed by 99858 pixels '
            'on the bottom.',
        'spanId': 'span_4',
        'parent': 'span_3',
      },
    ],
  };
  final tracesDir = Directory('${rootDir.path}/traces')
    ..createSync(recursive: true);
  File('${tracesDir.path}/$traceId.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(trace),
  );
}

void main() {
  group(
    'Run #006 capability (Agent-driven)',
    () {
      late Directory rootDir;
      late ObservabilityService service;

      setUp(() {
        rootDir = Directory(_adiRoot.isEmpty
            ? Directory.systemTemp.createTempSync('adi_run006_').path
            : _adiRoot);
        rootDir.createSync(recursive: true);
        final storage = AdiStorageImpl(rootDir.path)..initialize();
        service = ObservabilityService.full(adiStorage: storage);
        FaultInjection.enabled = true;
      });

      tearDown(() {
        FaultInjection.enabled = false;
        if (_adiRoot.isEmpty) {
          try {
            rootDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });

      testWidgets(
        'BEFORE: capture RenderOverflow into real .adi',
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
            length: 20, hasNewline: false, isAscii: true,
            timestamp: DateTime.now(),
          ));
          service.recordCommand(obs.CommandTraceEntry(
            commandName: 'InsertTextCommand',
            params: {'blockId': 'b1', 'text': 'void main(){}\n'},
            origin: obs.CommandOrigin.keyboard,
            timestamp: DateTime.now(),
            transactionId: 'tx_run006',
            succeeded: true,
          ));
          service.recordTransaction(const obs.TransactionTraceEntry(
            transactionId: 'tx_run006',
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
          expect(snapshot, isNotNull,
              reason: 'BEFORE: Agent must observe a captured bug');
          expect(snapshot!.message.toLowerCase(), contains('overflow'));
          expect(
            classifyErrorType(snapshot.type, snapshot.message),
            'RenderOverflow',
          );

          final storage = AdiStorageImpl(rootDir.path);
          final record = storage.latestErrorRecord();
          expect(record, isNotNull,
              reason: 'BEFORE: error persisted to .adi');
          final rec = record!; // expect 已断言非空，此处显式解包
          final session = _sessionId.isEmpty ? rec.sessionId : _sessionId;
          _cacheSessionEvidence(
            rootDir,
            session,
            rec.traceId,
            'reproduced',
          );

          print(jsonEncode({
            'phase': 'before',
            'status': 'captured',
            'session_id': session,
            'trace_id': rec.traceId,
            'error_type': classifyErrorType(rec.errorType, rec.message),
            'message': rec.message,
          }));
        },
        skip: !_beforeMode,
        timeout: const Timeout(Duration(seconds: 30)),
      );

      testWidgets(
        'AFTER: no overflow with fixed source (fresh process)',
        (tester) async {
          final originalOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            service.captureError(
              type: 'GlobalError',
              message: details.exceptionAsString(),
            );
          };
          addTearDown(() => FlutterError.onError = originalOnError);

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
          expect(snapshot, isNull,
              reason: 'AFTER: fixed source must not overflow '
                  'even with fault enabled');
          expect(FaultInjection.enabled, isTrue,
              reason: 'AFTER: fix must live in the SOURCE, not a flag toggle');

          // 覆盖同一 session 的 replay 状态 → validate 判定 after=pass
          final session = _sessionId.isEmpty ? service.sessionId : _sessionId;
          _cacheSessionEvidence(
            rootDir,
            session,
            'trace_after_${DateTime.now().millisecondsSinceEpoch}',
            'not_reproduced',
          );

          print(jsonEncode({
            'phase': 'after',
            'status': 'not_reproduced',
            'session_id': session,
            'error_type': 'RenderOverflow',
          }));
        },
        skip: !_afterMode,
        timeout: const Timeout(Duration(seconds: 30)),
      );
    },
    skip: (!_beforeMode && !_afterMode)
        ? 'skipped: run via tools/adi/run006_agent.py '
            '(sets ADL_RUN006_BEFORE/AFTER)'
        : false,
  );
}
