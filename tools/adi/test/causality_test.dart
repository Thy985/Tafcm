/// E2E-ADI-005 — Trace Causality Integrity (revised AS-R1.5).
///
/// Validates that `adi trace show` reports *causality*, not just *shape*:
/// a root span, a reachable failure span, and no orphan spans — regardless of
/// how many layers the trace has. This is the correction to the original
/// fixed-"6-layer" reading: a trace with 3 spans (or any count) is valid as
/// long as the causal chain holds.
///
/// 落地 Phase 3.8 修订 AS-R1.5（Trace Causality Integrity）。
import 'dart:io';

import 'package:test/test.dart';

import 'e2e/e2e_runner.dart';

void main() {
  group('E2E-ADI-005 Trace Causality Integrity', () {
    test('happy_path (5-span chain) validates with root→failure reachable', () {
      final cwd = stageAdi('happy_path');
      try {
        final trace =
            runAdiJson(['trace', 'show', 'trc_001', '--json'], cwd: cwd);
        final caus = trace['causality'] as Map<String, Object?>;
        expect(caus['rootSpanId'], 'sp_1');
        expect(caus['failureSpanId'], 'sp_5');
        expect(caus['reachable'], isTrue);
        expect(caus['orphanSpanIds'], isEmpty);
        expect(caus['valid'], isTrue);
      } finally {
        cwd.deleteSync(recursive: true);
      }
    });

    test('inconclusive (3-span chain, no command/transaction) still valid', () {
      // A network/parse-style failure may have fewer layers; causality, not
      // layer count, is what matters.
      final cwd = stageAdi('inconclusive');
      try {
        final trace =
            runAdiJson(['trace', 'show', 'trc_002', '--json'], cwd: cwd);
        final caus = trace['causality'] as Map<String, Object?>;
        expect(caus['rootSpanId'], 'sp_1');
        expect(caus['failureSpanId'], 'sp_3');
        expect(caus['reachable'], isTrue);
        expect(caus['valid'], isTrue);
      } finally {
        cwd.deleteSync(recursive: true);
      }
    });

    test('orphan parent (dangling reference) flagged and invalid', () {
      final cwd = stageAdi('happy_path');
      try {
        final traceFile = File('${cwd.path}/.adi/traces/trc_001.json');
        final txt = traceFile
            .readAsStringSync()
            .replaceFirst('"parent": "sp_1"', '"parent": "sp_X"');
        traceFile.writeAsStringSync(txt);
        final trace =
            runAdiJson(['trace', 'show', 'trc_001', '--json'], cwd: cwd);
        final caus = trace['causality'] as Map<String, Object?>;
        expect(caus['orphanSpanIds'], contains('sp_2'));
        expect(caus['valid'], isFalse);
      } finally {
        cwd.deleteSync(recursive: true);
      }
    });

    test('imported fault-injection trace gains causal links', () {
      final cwd = stageEmpty();
      try {
        runAdiJson(
            ['import', faultInjectionFixturePath(), '--json'], cwd: cwd);
        // The imported trace id is derived; query latest-error to get it.
        final latest = runAdiJson(['latest-error', '--json'], cwd: cwd);
        final traceId = latest['trace_id'] as String;
        final trace =
            runAdiJson(['trace', 'show', traceId, '--json'], cwd: cwd);
        final caus = trace['causality'] as Map<String, Object?>;
        expect(caus['rootSpanId'], isNotNull);
        expect(caus['failureSpanId'], isNotNull);
        expect(caus['reachable'], isTrue);
        expect(caus['valid'], isTrue);
      } finally {
        cwd.deleteSync(recursive: true);
      }
    });
  });
}
