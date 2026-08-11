/// E2E runner helper for the ADI pure-Dart CLI.
///
/// Drives `tools/adi/adi.dart` against a synthetic `.adi/` produced from a
/// fixture directory, validating the ADI Agent Interaction Contract
/// (ADR-0024 §1.4) as an end-to-end protocol loop.
///
/// The CLI reads `<cwd>/.adi`, so each scenario stages a private temp copy of
/// its fixture as `.adi/` and runs the CLI with that temp dir as CWD. This
/// keeps tests hermetic (committed fixtures are never mutated) and avoids
/// any reliance on the Flutter runtime (per ADR-0024 §4.3.4).
///
/// 落地 ADR-0024 §9（E2E Test Plan）。
library;

import 'dart:convert';
import 'dart:io';

/// Locates the repo root by walking up from an anchor directory until
/// `tools/adi/adi.dart` is found.
///
/// Under `dart test` the script URI resolves to a compiled kernel (`.dill`)
/// in a temp dir, so we anchor on [Directory.current] (the package dir the
/// test was launched from) and, as a fallback, on the script's parent when it
/// is a real `file:` URI (i.e. when the runner is executed via
/// `dart run` directly).
String findRepoRoot() {
  final anchors = <String>[
    Directory.current.path,
    if (Platform.script.scheme == 'file')
      File.fromUri(Platform.script).parent.path,
  ];
  for (final start in anchors) {
    var dir = Directory(start);
    while (true) {
      if (File('${dir.path}/tools/adi/adi.dart').existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  throw StateError(
    'Could not locate repo root (cwd=${Directory.current.path}, '
    'script=${Platform.script})',
  );
}

/// Absolute path to the `adi` CLI entrypoint.
String adiCliPath() => '${findRepoRoot()}/tools/adi/adi.dart';

/// Stages [fixtureName] (a directory under `fixtures/`) into a fresh temp dir
/// as `.adi/`, returning the temp dir (use it as CWD for CLI runs).
Directory stageAdi(String fixtureName) {
  final repoRoot = findRepoRoot();
  final fixtureDir =
      Directory('$repoRoot/tools/adi/test/e2e/fixtures/$fixtureName');
  if (!fixtureDir.existsSync()) {
    throw StateError('Fixture not found: ${fixtureDir.path}');
  }
  final temp = Directory.systemTemp.createTempSync('adi_e2e_');
  _copyDir(fixtureDir, Directory('${temp.path}/.adi'));
  return temp;
}

/// Basename of a filesystem entity.
///
/// `entity.uri.pathSegments.last` returns an empty string for directories
/// (their URI carries a trailing slash), so we derive the name from the
/// platform path instead.
String _baseName(FileSystemEntity entity) =>
    entity.path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;

void _copyDir(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final entity in src.listSync(recursive: false)) {
    final name = _baseName(entity);
    if (entity is File) {
      entity.copySync('${dst.path}/$name');
    } else if (entity is Directory) {
      _copyDir(entity, Directory('${dst.path}/$name'));
    }
  }
}

/// Runs `adi <args>` with CWD set to [cwd] (the staged `.adi` parent).
ProcessResult runAdi(List<String> args, {required Directory cwd}) {
  return Process.runSync(
    'dart',
    ['run', adiCliPath(), ...args],
    workingDirectory: cwd.path,
  );
}

/// Runs `adi <args>` and decodes the JSON object from stdout.
///
/// Throws if the CLI exits non-zero so failures surface as test errors.
Map<String, Object?> runAdiJson(List<String> args, {required Directory cwd}) {
  final result = runAdi(args, cwd: cwd);
  if (result.exitCode != 0) {
    throw StateError(
      'adi ${args.join(' ')} failed (exit ${result.exitCode}):\n'
      'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
  }
  final stdout = (result.stdout as String).trim();
  final decoded = jsonDecode(stdout);
  if (decoded is Map) return decoded.cast<String, Object?>();
  throw StateError('Expected a JSON object from adi, got: $stdout');
}

/// Overwrites a session artifact inside the staged `.adi/` (simulates the
/// effect of an Agent code fix taking hold).
void writeSessionArtifact(
  Directory cwd,
  String sessionId,
  String fileName,
  Map<String, Object?> data,
) {
  final path = '${cwd.path}/.adi/sessions/$sessionId/$fileName';
  File(path).parent.createSync(recursive: true);
  File(path).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(data),
  );
}

/// Stages an *empty* temp dir (no `.adi/` yet). Used by E2E-004, which
/// populates `.adi/` via the `adi import` command rather than a fixture copy.
/// Returns a single-use temp dir to use as CWD for CLI runs.
Directory stageEmpty() => Directory.systemTemp.createTempSync('adi_e2e_');

/// Absolute path to the `real_device` fixture directory (an `ExportPipeline`
/// package: metadata/snapshot/trace/invariant_report JSON, identical to the
/// real `debug/02/` export).
String realDeviceFixturePath() =>
    '${findRepoRoot()}/tools/adi/test/e2e/fixtures/real_device';

/// Absolute path to the `fault_injection` fixture directory — a *fault-injected*
/// `ExportPipeline` package representing what a deterministic fault-injection
/// run on a real device produces (FULL observability: the full
/// interaction -> command -> transaction -> render -> error chain).
///
/// This is the v0.1 "Agent can get reliable evidence" scenario: a known failure
/// is manufactured (not waited-for), so the ADI protocol can be proven without
/// depending on a flaky, real-world bug. See ADR-0024 §9 + fault-injection plan.
String faultInjectionFixturePath() =>
    '${findRepoRoot()}/tools/adi/test/e2e/fixtures/fault_injection';
