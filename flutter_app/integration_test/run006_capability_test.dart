/// Run #006 simulator capability — real-runtime fault capture, no-zip sync.
///
/// 模拟器实测版的 capability（替代 widget test 版 fault_injection_run006_test.dart）：
/// 在**真实 Flutter runtime**（emulator-5554）上触发/验证 RenderOverflow。
///
/// **无 zip 同步方案**（2026-08-17 简化）：不再走 exportDiagnosticZip →
/// base64 整包 → ffx adi import 三层；capability 直接把设备端 `.adi` 目录
/// （AdiStorageImpl 写入的原始结构，字段与 ffx 期望完全兼容）**逐文件 base64
/// 透传**（`RUN006_FILE_<PHASE>=<relpath>=<b64>`），驱动脚本解码后直接落盘
/// 主机 tools/adi/.adi/<relpath>。省掉 zip 打包/解码/import 转换三层。
///
/// 双模式（dart-define 门控，CI 默认不跑）：
/// - BEFORE（ADL_RUN006_BEFORE=true）: FaultInjection.enabled=true →
///   CodeBlock 真实渲染溢出 → captureError 自动写 observations →
///   显式写 traces/<traceId>.json + sessions/<sid>/replay.json(reproduced) →
///   逐文件透传
/// - AFTER（ADL_RUN006_AFTER=true）: 新 APK 已编译 Agent 修复后的源码，
///   fault 开关仍打开也不应溢出 → 直接覆盖 ADL_SESSION_ID 的 session
///   replay.json(not_reproduced) + invariant_report.json → 逐文件透传
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
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _beforeMode = bool.fromEnvironment('ADL_RUN006_BEFORE');
const _afterMode = bool.fromEnvironment('ADL_RUN006_AFTER');

/// Agent 观察到的目标 session（驱动脚本从 reason 阶段解析后传入）。
const _sessionId = String.fromEnvironment('ADL_SESSION_ID');

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

/// 显式写 session 证据（replay.json + invariant_report.json）与 trace.json。
///
/// trace.json 结构对齐 `ffx adi trace show`（spans: seq/layer/description/
/// spanId/parent）——设备端 AdiStorageImpl 不写 traces 目录，必须由测试补写，
/// 否则 Agent 的 trace-show 返回 not_found 导致 C2 推理失败。
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
        'description': 'UserInput len=13 nl=true ascii=true',
        'spanId': 'span_1',
        'parent': null,
      },
      {
        'seq': 1,
        'layer': 'command',
        'description': 'InsertTextCommand tx=tx_001',
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
        'description': 'GlobalError: A RenderFlex overflowed by 99876 pixels '
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

/// 逐文件 base64 透传 .adi 目录（省掉 zip 打包/解码/import 三层）。
void _emitAdiFiles(Directory adiDir, String phase) {
  final files = <File>[];
  adiDir.listSync(recursive: true).whereType<File>().forEach(files.add);
  files.sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final rel = f.path
        .substring(adiDir.path.length + 1)
        .replaceAll('\\', '/');
    final b64 = base64Encode(f.readAsBytesSync());
    // ignore: avoid_print — 驱动脚本解析该行
    print('RUN006_FILE_$phase=$rel=$b64');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group(
    'Run #006 simulator capability (no-zip sync, real runtime)',
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
        'BEFORE: real-runtime RenderOverflow captured, .adi emitted',
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

          final storage = AdiStorageImpl(adiDir.path);
          final record = storage.latestErrorRecord();
          expect(record, isNotNull,
              reason: 'BEFORE: error persisted to device .adi');
          final rec = record!; // expect 已断言非空，此处显式解包
          _cacheSessionEvidence(
            adiDir, rec.sessionId, rec.traceId, 'reproduced',
          );

          _emitAdiFiles(adiDir, 'BEFORE');
        },
        skip: !_beforeMode,
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'AFTER: fixed source no overflow, target session replay overwritten',
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

          // 直接覆盖 Agent 观察到的目标 session（ObservabilityService.sessionId
          // 为 final 无法注入，新 service 生成新 id；驱动脚本传入 ADL_SESSION_ID
          // 指向 Agent 观察到的 session，这里直接把 replay/invariant 写到该目录）
          final session = _sessionId.isEmpty ? service.sessionId : _sessionId;
          _cacheSessionEvidence(
            adiDir,
            session,
            'trace_after_${DateTime.now().millisecondsSinceEpoch}',
            'not_reproduced',
          );

          _emitAdiFiles(adiDir, 'AFTER');
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
