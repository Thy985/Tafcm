/// ADI E2E scenarios 001-003 (synthetic, pure Dart).
///
/// Each scenario drives the pure-Dart `adi` CLI end-to-end to validate the
/// ADI Agent Interaction Contract (ADR-0024 §1.4). No Flutter runtime is
/// involved (per ADR-0024 §4.3.4). Scenario 004 (real-device Render Overflow)
/// is documented in ADR-0024 §9 but deferred until the ZipImporter (v0.1
/// compatible layer) lands.
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
      expect(latest['errorType'], 'RenderOverflow');
      expect(latest['session'], 'sess_A');
      expect(latest['trace'], 'trc_001');

      // Inspect before edit: the trace is queryable (CLI returns the raw trace).
      final trace = runAdiJson(['trace', 'show', 'trc_001', '--json'], cwd: cwd);
      expect(trace['sessionId'], 'sess_A');
      expect((trace['spans'] as List).length, 5);

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
      expect(latest['session'], 'sess_B');

      // Inspect before edit.
      final trace = runAdiJson(['trace', 'show', 'trc_002', '--json'], cwd: cwd);
      expect(trace['sessionId'], 'sess_B');
      expect((trace['spans'] as List).length, 3);

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
}
