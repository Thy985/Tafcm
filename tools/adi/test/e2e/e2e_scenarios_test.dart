/// ADI E2E scenarios 001-004 (synthetic + real-device, pure Dart).
///
/// Each scenario drives the pure-Dart `adi` CLI end-to-end to validate the
/// ADI Agent Interaction Contract (ADR-0024 §1.4). No Flutter runtime is
/// involved (per ADR-0024 §4.3.4).
///
/// - 001 Happy Path (synthetic): manufacture -> latest-error -> trace ->
///   replay -> fix -> validate(pass).
/// - 002 Inconclusive (synthetic): incomplete evidence -> validate inconclusive.
/// - 003 Failure Aggregation (synthetic): duplicate errors aggregate, status
///   preserved across re-aggregate.
/// - 004 Real-Device Import: `adi import` the 3.7 ExportPipeline package
///   (identical to real `debug/02/`) -> consumable `.adi/` -> query/replay/
///   validate, asserting the safety-critical `inconclusive` (never false pass)
///   branch when no replay evidence exists.
///
/// 落地 ADR-0024 §9（E2E Test Plan）。
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'e2e_runner.dart';

void main() {
  group('E2E-ADI-001 Happy Path', () {
    late Directory cwd;

    setUp(() => cwd = stageAdi('happy_path'));
    tearDown(() {
      try {
        cwd.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('manufacture → latest-error → trace → replay → fix → validate(pass)', () {
      // Query first: latest-error surfaces the manufactured error.
      final latest = runAdiJson(['latest-error', '--json'], cwd: cwd);
      expect(latest['status'], 'error');
      expect(latest['error_type'], 'RenderOverflow');
      expect(latest['session_id'], 'sess_A');
      expect(latest['trace_id'], 'trc_001');
      expect(latest['snapshot_available'], isTrue);

      // Inspect before edit: the trace chain is queryable.
      final trace = runAdiJson(['trace', 'show', 'trc_001', '--json'], cwd: cwd);
      expect(trace['sessionId'], 'sess_A');
      expect((trace['chain'] as List).length, 5);

      // Replay before modify: confirm the bug reproduces (pre-fix state).
      final replayBefore =
          runAdiJson(['replay', 'sess_A', '--json'], cwd: cwd);
      expect(replayBefore['status'], 'reproduced');

      // Pre-fix validation: still failing.
      final before =
          runAdiJson(['validate', '--after-fix', 'sess_A', '--json'], cwd: cwd);
      expect(before['before'], 'unknown');
      expect(before['after'], 'still_failing');

      // Apply the Agent code fix (simulated by flipping the replay result).
      writeSessionArtifact(cwd, 'sess_A', 'replay.json',
          {'status': 'notReproduced', 'commandsExecuted': 5});

      // Validate after modify: no longer reproduces + invariants pass → pass.
      final after =
          runAdiJson(['validate', '--after-fix', 'sess_A', '--json'], cwd: cwd);
      expect(after['before'], 'unknown');
      expect(after['after'], 'pass');
    });
  });

  group('E2E-ADI-002 Inconclusive', () {
    late Directory cwd;

    setUp(() => cwd = stageAdi('inconclusive'));
    tearDown(() {
      try {
        cwd.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('incomplete evidence → validate returns inconclusive, never false pass', () {
      // Query first.
      final latest = runAdiJson(['latest-error', '--json'], cwd: cwd);
      expect(latest['status'], 'error');
      expect(latest['session_id'], 'sess_B');

      // Inspect before edit.
      final trace = runAdiJson(['trace', 'show', 'trc_002', '--json'], cwd: cwd);
      expect(trace['sessionId'], 'sess_B');
      expect((trace['chain'] as List).length, 3);

      // Replay data is absent → replay inconclusive.
      final replay = runAdiJson(['replay', 'sess_B', '--json'], cwd: cwd);
      expect(replay['status'], 'inconclusive');

      // Respect invariant report: invariants all pass BUT replay is incomplete
      // → inconclusive, NOT a false pass. This is the safety-critical branch.
      final validate =
          runAdiJson(['validate', '--after-fix', 'sess_B', '--json'], cwd: cwd);
      expect(validate['after'], 'inconclusive');
      expect(validate['after'], isNot('pass'));
    });

    test('cross-session validation of a non-existent session → no_data', () {
      // The error belongs to sess_B; validating a different session yields no
      // evidence and must not be mistaken for a pass. (The cross-session
      // *warning* itself is enforced on the App side via
      // AdiValidationAdapterImpl; the CLI guards with no_data.)
      final validate =
          runAdiJson(['validate', '--after-fix', 'sess_C', '--json'], cwd: cwd);
      // no_data branch returns only `status` (no `after` key).
      expect(validate['status'], 'no_data');
    });
  });

  group('E2E-ADI-003 Failure Aggregation', () {
    late Directory cwd;

    setUp(() => cwd = stageAdi('aggregation'));
    tearDown(() {
      try {
        cwd.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('repeated identical errors aggregate; status preserved across re-aggregate', () {
      // Aggregate: 4 RenderOverflow + 1 NullPointer → 2 failures.
      final agg1 = runAdiJson(['failures', 'aggregate', '--json'], cwd: cwd);
      expect(agg1['status'], 'ok');
      expect(agg1['aggregated'], 2);

      final list1 = runAdiJson(['failures', 'list', '--json'], cwd: cwd);
      final fails1 = list1['failures'] as List;
      expect(fails1.length, 2);

      final renderFail1 = fails1.firstWhere(
        (f) => (f as Map)['errorType'] == 'RenderOverflow',
      ) as Map;
      expect(renderFail1['occurrences'], 4);
      expect(renderFail1['status'], 'open');

      // Simulate a prior fix: mark the RenderOverflow failure as fixed.
      final renderPath =
          '${cwd.path}/.adi/failures/${renderFail1['failureId']}.json';
      final renderJson = Map<String, Object?>.from(
        jsonDecode(File(renderPath).readAsStringSync()) as Map,
      );
      renderJson['status'] = 'fixed';
      File(renderPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(renderJson),
      );

      // Re-aggregate (Replay before modify territory: occurrences = identity).
      // The existing status must be preserved, not reset to open.
      final agg2 = runAdiJson(['failures', 'aggregate', '--json'], cwd: cwd);
      expect(agg2['aggregated'], 2);

      final list2 = runAdiJson(['failures', 'list', '--json'], cwd: cwd);
      final fails2 = list2['failures'] as List;
      final renderFail2 = fails2.firstWhere(
        (f) => (f as Map)['errorType'] == 'RenderOverflow',
      ) as Map;
      expect(renderFail2['occurrences'], 4); // merged, not reset
      expect(renderFail2['status'], 'fixed'); // preserved, not overwritten
    });
  });

  group('E2E-ADI-004 Fault-Injection (v0.1 real-device contract)', () {
    late Directory cwd;

    setUp(() => cwd = stageEmpty());
    tearDown(() {
      try {
        cwd.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('fault-injected RenderOverflow -> Agent gets reliable evidence (classified + full chain)', () {
      // 1. Import a FAULT-INJECTED ExportPipeline package (FULL observability):
      //    a known failure was manufactured on-device (not waited-for), so the
      //    produced package carries the full causal chain. ZipImporter
      //    transcribes it into `.adi/`.
      final import = runAdiJson(
          ['import', faultInjectionFixturePath(), '--json'],
          cwd: cwd);
      expect(import['status'], 'ok');
      expect(Directory('${cwd.path}/.adi').existsSync(), isTrue);

      // 2. Query first: latest-error must surface a CLASSIFIED error type, not a
      //    bare GlobalError / FlutterError. The Agent needs `RenderOverflow`,
      //    plus a stable session/trace id and confirmation a snapshot exists.
      final latest = runAdiJson(['latest-error', '--json'], cwd: cwd);
      expect(latest['status'], 'error');
      expect(latest['error_type'], 'RenderOverflow'); // classified, not GlobalError
      expect(latest['error_type_raw'], 'GlobalError'); // raw fidelity preserved
      expect(latest['snapshot_available'], isTrue);
      expect(latest['session_id'], 'sess_fi_001');
      expect(latest['trace_id'], startsWith('trc_'));
      expect(latest['message'], contains('overflowed'));

      // 3. Inspect before edit: the causal chain must be reconstructable, in the
      //    canonical order interaction -> command -> transaction -> render -> error,
      //    and the Agent must NOT need a human to explain "what happened".
      final trace =
          runAdiJson(['trace', 'show', latest['trace_id'] as String, '--json'], cwd: cwd);
      expect(trace['sessionId'], 'sess_fi_001');
      final chain = trace['chain'] as List;
      expect(chain.length, 6); // interaction + command + transaction + 2 renders + error
      final layers = chain.map((s) => (s as Map)['layer'] as String).toList();
      expect(
        layers,
        ['interaction', 'command', 'transaction', 'render', 'render', 'error'],
      );
      final descs = chain.map((s) => (s as Map)['description'] as String).toList();
      expect(descs[0], 'UserInput: PasteText'); // who/what triggered it
      expect(descs[1], 'InsertTextCommand'); // which command
      expect(descs[2], 'TransactionCommit (BlockTree update)'); // state mutation
      expect(descs[3], 'CodeBlockRenderer (build code block)'); // where it rendered
      expect(descs[4], 'HighlightView (highlight long line)');
      expect(descs[5], contains('overflow')); // the failure, named

      // 4. Replay before modify: v0.1 has no replay evidence for a real
      //    fault-injected run -> inconclusive (the safety-critical branch that
      //    MUST NOT collapse into a false `pass`).
      final replay = runAdiJson(
          ['replay', 'sess_fi_001', '--json'], cwd: cwd);
      expect(replay['status'], 'inconclusive');

      // 5. Validate after modify: replay inconclusive + invariant not_checked
      //    must resolve to `inconclusive` — NEVER a false `pass`.
      final validate = runAdiJson(
          ['validate', '--after-fix', 'sess_fi_001', '--json'], cwd: cwd);
      expect(validate['after'], 'inconclusive');
      expect(validate['after'], isNot('pass'));
    });

    test('classification also applies to a genuine LIGHT-mode real-device capture', () {
      // The genuine `debug/02/` export (real device, LIGHT mode, no full chain)
      // still carries an overflow message; classification must surface
      // `RenderOverflow` so the contract holds regardless of observability level.
      final import = runAdiJson(
          ['import', realDeviceFixturePath(), '--json'], cwd: cwd);
      expect(import['status'], 'ok');
      final latest = runAdiJson(['latest-error', '--json'], cwd: cwd);
      expect(latest['error_type'], 'RenderOverflow');
      expect(latest['snapshot_available'], isTrue);
      expect(latest['session_id'], 'sess_6b62');
    });
  });
}
