/// ADI CLI：Agent Diagnostic Interface 命令行入口。
///
/// 纯 Dart 脚本，不依赖 Flutter runtime。Agent 直接 `dart run tools/adi/adi.dart`。
/// 读取 .adi/ 目录，输出人类可读或 --json machine 模式。
///
/// **设计决策（ADR-0024 §2.7）**：CLI 直接读 .adi/ 文件，**不经过 QueryAdapter**。
/// 原因：QueryAdapter 依赖 ObservabilityService（Flutter runtime + Widget 树），
/// CLI 作为纯 Dart 脚本无法加载 Flutter runtime。CLI 与 QueryAdapter 是
/// 同一协议的两个入口——App 内走 QueryAdapter（实时），Agent 走 CLI（离线）。
/// 两者读同一份 .adi/ schema，输出同一组 AdiView 字段。
///
/// 落地 ADR-0024 §2.7（CLI Entry）。
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    exit(1);
  }

  final jsonMode = args.contains('--json');
  final command = args[0];
  final rest = args.where((a) => a != '--json' && a != command).toList();

  switch (command) {
    case 'doctor':
      _cmdDoctor(jsonMode);
    case 'latest-error':
      _cmdLatestError(jsonMode);
    case 'trace':
      _cmdTrace(rest, jsonMode);
    case 'replay':
      _cmdReplay(rest, jsonMode);
    case 'agent-context':
      _cmdAgentContext(jsonMode);
    case 'failure':
      _cmdFailure(rest, jsonMode);
    case 'failures':
      _cmdFailures(rest, jsonMode);
    case 'validate':
      _cmdValidate(rest, jsonMode);
    default:
      stderr.writeln('Unknown command: $command');
      _printUsage();
      exit(1);
  }
}

void _printUsage() {
  stderr.writeln('Usage: dart run tools/adi/adi.dart <command> [--json]');
  stderr.writeln('Commands:');
  stderr.writeln('  doctor              ADI self-check');
  stderr.writeln('  latest-error        Get latest error');
  stderr.writeln('  trace show <id>     Show trace chain');
  stderr.writeln('  replay <id>          Replay session');
  stderr.writeln('  agent-context       Generate Agent context Markdown');
  stderr.writeln('  failure show <id>   Show failure details');
  stderr.writeln('  failures list       List recent failures (aggregated)');
  stderr.writeln('  validate --after-fix <id>  Validate fix (replay + invariant)');
}

String get _adiRoot => '${Directory.current.path}/.adi';

Map<String, Object?>? _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (_) {
    return null;
  }
}

void _cmdDoctor(bool json) {
  final root = Directory(_adiRoot);
  final exists = root.existsSync();
  final schema = _readJson('$_adiRoot/schema_version.json');
  final obsDir = Directory('$_adiRoot/observations');
  final obsCount = obsDir.existsSync()
      ? obsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).length
      : 0;

  if (json) {
    print(jsonEncode({
      'status': exists ? 'healthy' : 'broken',
      'storage': {'exists': exists, 'path': _adiRoot},
      'schema': schema?['schema_version'] ?? 0,
      'adi_protocol_version': schema?['adi_protocol_version'] ?? 'unknown',
      'observations': obsCount,
    }));
  } else {
    print('ADI Health Check');
    print('─' * 40);
    print('Storage:     ${exists ? "✓ writable" : "✗ not initialized"} ($_adiRoot)');
    print('Schema:      ${schema != null ? "✓ version ${schema["schema_version"]}" : "✗ missing"}');
    print('Protocol:    ${schema?["adi_protocol_version"] ?? "unknown"}');
    print('Observations: $obsCount');
    print('─' * 40);
    print('Status: ${exists ? "healthy" : "broken"}');
  }
}

void _cmdLatestError(bool json) {
  final dir = Directory('$_adiRoot/observations');
  if (!dir.existsSync()) {
    if (json) {
      print(jsonEncode({'status': 'no_error'}));
    } else {
      print('No errors recorded.');
    }
    return;
  }

  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();
  if (files.isEmpty) {
    if (json) {
      print(jsonEncode({'status': 'no_error'}));
    } else {
      print('No errors recorded.');
    }
    return;
  }

  files.sort((a, b) => b.path.compareTo(a.path));
  final record = _readJson(files.first.path);
  if (record == null) {
    if (json) {
      print(jsonEncode({'status': 'error', 'message': 'Failed to read record'}));
    } else {
      print('Error: Failed to read record');
    }
    return;
  }

  if (json) {
    print(jsonEncode({
      'status': 'error',
      'id': record['id'],
      'errorType': record['errorType'],
      'message': record['message'],
      'trace': record['traceId'],
      'session': record['sessionId'],
      'time': record['time'],
      'next_actions': [
        'adi replay ${record['sessionId']}',
        'adi trace show ${record['traceId']}',
      ],
    }));
  } else {
    print('Error: ${record["errorType"]}: ${record["message"]}');
    print('  Trace: ${record["traceId"]}  Session: ${record["sessionId"]}  Time: ${record["time"]}');
    print('  Next: adi replay ${record["sessionId"]} | adi trace show ${record["traceId"]}');
  }
}

void _cmdTrace(List<String> rest, bool json) {
  if (rest.isEmpty || rest[0] != 'show' || rest.length < 2) {
    stderr.writeln('Usage: adi trace show <id>');
    exit(1);
  }
  final traceId = rest[1];
  final trace = _readJson('$_adiRoot/traces/$traceId.json');
  if (trace == null) {
    if (json) {
      print(jsonEncode({'status': 'not_found', 'traceId': traceId}));
    } else {
      print('Trace not found: $traceId');
    }
    return;
  }
  if (json) {
    print(jsonEncode(trace));
  } else {
    print('Trace: $traceId');
    print('  Session: ${trace["sessionId"]}');
    final spans = trace['spans'] as List?;
    if (spans != null) {
      for (final span in spans) {
        final s = span as Map<String, Object?>;
        print('  [${s["layer"]}] ${s["spanId"]}: ${s["description"]}');
      }
    }
  }
}

void _cmdReplay(List<String> rest, bool json) {
  if (rest.isEmpty) {
    stderr.writeln('Usage: adi replay <sessionId>');
    exit(1);
  }
  final sessionId = rest[0];
  final sessionDir = Directory('$_adiRoot/sessions/$sessionId');
  if (!sessionDir.existsSync()) {
    if (json) {
      print(jsonEncode({'status': 'not_found', 'sessionId': sessionId}));
    } else {
      print('Session not found: $sessionId');
    }
    return;
  }
  final replayFile = File('$_adiRoot/sessions/$sessionId/replay.json');
  if (replayFile.existsSync()) {
    final replay = _readJson(replayFile.path);
    if (json) {
      print(jsonEncode(replay));
    } else {
      print('Replay result for session $sessionId:');
      print('  Status: ${replay?["status"] ?? "unknown"}');
      print('  Commands: ${replay?["commandsExecuted"] ?? 0}');
    }
    return;
  }
  if (json) {
    print(jsonEncode({
      'status': 'inconclusive',
      'message': 'Replay data exists but no replay result cached. Run replay from App.',
    }));
  } else {
    print('Replay data exists for session $sessionId but no result cached.');
    print('Run replay from the App to generate a result.');
  }
}

void _cmdAgentContext(bool json) {
  final dir = Directory('$_adiRoot/observations');
  if (!dir.existsSync() || dir.listSync().isEmpty) {
    if (json) {
      print(jsonEncode({'status': 'no_data', 'message': 'No observations recorded.'}));
    } else {
      print('# Current Software State\n\nNo errors recorded.');
    }
    return;
  }

  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
  files.sort((a, b) => b.path.compareTo(a.path));
  final latest = _readJson(files.first.path);

  final buf = StringBuffer();
  buf.writeln('# Current Software State');
  buf.writeln();
  buf.writeln('## Last failure');
  buf.writeln('${latest?["errorType"] ?? "unknown"}: ${latest?["message"] ?? ""}');
  buf.writeln();
  buf.writeln('## Evidence');
  buf.writeln('- trace_id: ${latest?["traceId"] ?? "unknown"}');
  buf.writeln('- session_id: ${latest?["sessionId"] ?? "unknown"}');
  buf.writeln('- snapshot: .adi/observations/${latest?["id"] ?? "unknown"}.json');
  buf.writeln();
  buf.writeln('## Suggested next action');
  buf.writeln('- Inspect: `adi trace show ${latest?["traceId"] ?? "unknown"}`');
  buf.writeln('- Replay: `adi replay ${latest?["sessionId"] ?? "unknown"}`');

  if (json) {
    print(jsonEncode({'status': 'ok', 'context': buf.toString()}));
  } else {
    print(buf.toString());
  }
}

void _cmdFailure(List<String> rest, bool json) {
  if (rest.isEmpty || rest[0] != 'show' || rest.length < 2) {
    stderr.writeln('Usage: adi failure show <id>');
    exit(1);
  }
  final failureId = rest[1];
  final failure = _readJson('$_adiRoot/failures/$failureId.json');
  if (failure == null) {
    if (json) {
      print(jsonEncode({'status': 'not_found', 'failureId': failureId}));
    } else {
      print('Failure not found: $failureId');
    }
    return;
  }
  if (json) {
    print(jsonEncode(failure));
  } else {
    print('Failure: $failureId');
    print('  Type: ${failure["errorType"]}');
    print('  Occurrences: ${failure["occurrences"]}');
    print('  Status: ${failure["status"]}');
    print('  First seen: ${failure["firstSeen"]}');
    print('  Last seen: ${failure["lastSeen"]}');
  }
}

void _cmdFailures(List<String> rest, bool json) {
  final sub = rest.isNotEmpty ? rest[0] : 'list';

  if (sub == 'aggregate') {
    _aggregateFailures(json);
    return;
  }

  final dir = Directory('$_adiRoot/failures');
  if (!dir.existsSync()) {
    if (json) {
      print(jsonEncode({'status': 'no_failures', 'failures': []}));
    } else {
      print('No failures recorded. Run `adi failures aggregate` to build from observations.');
    }
    return;
  }

  final failures = <Map<String, Object?>>[];
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final f = _readJson(entity.path);
    if (f != null) failures.add(f);
  }
  failures.sort((a, b) =>
      (b['lastSeen'] as String? ?? '').compareTo(a['lastSeen'] as String? ?? ''));

  if (json) {
    print(jsonEncode({'status': 'ok', 'count': failures.length, 'failures': failures}));
  } else {
    print('Failures (${failures.length}):');
    for (final f in failures) {
      print('  ${f["failureId"]}: ${f["errorType"]} ×${f["occurrences"]} [${f["status"]}]');
    }
  }
}

void _aggregateFailures(bool json) {
  final obsDir = Directory('$_adiRoot/observations');
  if (!obsDir.existsSync()) {
    if (json) {
      print(jsonEncode({'status': 'no_observations', 'aggregated': 0}));
    } else {
      print('No observations to aggregate.');
    }
    return;
  }

  final errors = <Map<String, Object?>>[];
  for (final entity in obsDir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final e = _readJson(entity.path);
    if (e != null) errors.add(e);
  }

  final byFailureId = <String, List<Map<String, Object?>>>{};
  for (final error in errors) {
    final errorType = error['errorType'] as String? ?? 'unknown';
    final stackHash = error['stackHash'] as String?;
    final fid = _computeFailureId(errorType, stackHash);
    byFailureId.putIfAbsent(fid, () => []).add(error);
  }

  final failDir = Directory('$_adiRoot/failures');
  if (!failDir.existsSync()) failDir.createSync(recursive: true);

  for (final entry in byFailureId.entries) {
    final fid = entry.key;
    final records = entry.value;
    records.sort((a, b) =>
        (a['time'] as String? ?? '').compareTo(b['time'] as String? ?? ''));

    final failure = {
      'failureId': fid,
      'firstSeen': records.first['time'],
      'lastSeen': records.last['time'],
      'occurrences': records.length,
      'errorType': records.first['errorType'],
      'stackHash': records.first['stackHash'],
      'traceIds': records.map((r) => r['traceId']).toList(),
      'sessionIds': records.map((r) => r['sessionId']).toSet().toList(),
      'status': 'open',
    };

    final tempPath = '$_adiRoot/failures/$fid.json.tmp';
    File(tempPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(failure),
    );
    File(tempPath).renameSync('$_adiRoot/failures/$fid.json');
  }

  final index = {
    'updated_at': DateTime.now().toIso8601String(),
    'failures': byFailureId.entries
        .map((e) => {
              'failureId': e.key,
              'errorType': e.value.first['errorType'],
              'occurrences': e.value.length,
              'lastSeen': e.value.last['time'],
            })
        .toList(),
  };
  final tempIdx = '$_adiRoot/index.json.tmp';
  File(tempIdx).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(index),
  );
  File(tempIdx).renameSync('$_adiRoot/index.json');

  if (json) {
    print(jsonEncode({
      'status': 'ok',
      'aggregated': byFailureId.length,
      'total_observations': errors.length,
    }));
  } else {
    print('Aggregated ${errors.length} observations into ${byFailureId.length} failures.');
    print('Index written to .adi/index.json');
  }
}

String _computeFailureId(String errorType, String? stackHash) {
  final input = '$errorType|${stackHash ?? ''}';
  final digest = _sha256(input);
  return 'f_${digest.substring(0, 16)}';
}

String _sha256(String input) {
  final bytes = input.codeUnits;
  final h = List<int>.filled(8, 0);
  h[0] = 0x6a09e667; h[1] = 0xbb67ae85; h[2] = 0x3c6ef372; h[3] = 0xa54ff53a;
  h[4] = 0x510e527f; h[5] = 0x9b05688c; h[6] = 0x1f83d9ab; h[7] = 0x5be0cd19;
  final k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a4a, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c88, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9aca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  final padded = _pad(bytes);
  for (final block in padded) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      w[i] = block[i * 4] << 24 | block[i * 4 + 1] << 16 | block[i * 4 + 2] << 8 | block[i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final temp1 = (hh + s1 + ch + k[i] + w[i]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xFFFFFFFF;
      hh = g; g = f; f = e; e = (d + temp1) & 0xFFFFFFFF;
      d = c; c = b; b = a; a = (temp1 + temp2) & 0xFFFFFFFF;
    }
    h[0] = (h[0] + a) & 0xFFFFFFFF; h[1] = (h[1] + b) & 0xFFFFFFFF;
    h[2] = (h[2] + c) & 0xFFFFFFFF; h[3] = (h[3] + d) & 0xFFFFFFFF;
    h[4] = (h[4] + e) & 0xFFFFFFFF; h[5] = (h[5] + f) & 0xFFFFFFFF;
    h[6] = (h[6] + g) & 0xFFFFFFFF; h[7] = (h[7] + hh) & 0xFFFFFFFF;
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}

int _rotr(int x, int n) => (x >> n) | (x << (32 - n)) & 0xFFFFFFFF;

List<List<int>> _pad(List<int> bytes) {
  final bitLen = bytes.length * 8;
  final withOne = [...bytes, 0x80];
  while (withOne.length % 64 != 56) withOne.add(0);
  final lenBytes = <int>[];
  for (var i = 7; i >= 0; i--) lenBytes.add((bitLen >> (i * 8)) & 0xFF);
  withOne.addAll(lenBytes);
  final blocks = <List<int>>[];
  for (var i = 0; i < withOne.length; i += 64) {
    blocks.add(withOne.sublist(i, i + 64));
  }
  return blocks;
}

void _cmdValidate(List<String> rest, bool json) {
  if (rest.isEmpty || rest[0] != '--after-fix' || rest.length < 2) {
    stderr.writeln('Usage: adi validate --after-fix <sessionId>');
    exit(1);
  }
  final sessionId = rest[1];

  final replayFile = File('$_adiRoot/sessions/$sessionId/replay.json');
  final replay = _readJson(replayFile.path);

  final invariantFile = File('$_adiRoot/sessions/$sessionId/invariant_report.json');
  final invariants = _readJson(invariantFile.path);

  if (replay == null && invariants == null) {
    if (json) {
      print(jsonEncode({
        'status': 'no_data',
        'message': 'No cached replay or invariant data for session $sessionId. '
            'Run validation from the App first.',
      }));
    } else {
      print('No validation data for session $sessionId.');
      print('Run validation from the App to generate results.');
    }
    return;
  }

  final replayStatus = replay?['status'] as String? ?? 'inconclusive';
  final replayOk = replayStatus != 'reproduced';
  final violated = (invariants?['failedNames'] as List?)?.cast<String>() ?? [];
  final checked = (invariants?['allNames'] as List?)?.cast<String>() ?? [];
  final invariantOk = violated.isEmpty;

  final after = replayStatus == 'inconclusive'
      ? 'inconclusive'
      : (replayOk && invariantOk ? 'pass' : 'still_failing');

  final result = {
    'before': 'unknown',
    'after': after,
    'replay': replay ?? {'status': 'no_data'},
    'invariants': {
      'violated': violated,
      'checked': checked,
      'allPassed': invariantOk,
    },
  };

  if (json) {
    print(jsonEncode(result));
  } else {
    print('Validation result for session $sessionId:');
    print('  After: $after');
    print('  Replay: $replayStatus (${replay?["commandsExecuted"] ?? 0} commands)');
    if (violated.isEmpty) {
      print('  Invariants: all ${checked.length} passed');
    } else {
      print('  Invariants: VIOLATED ${violated.join(", ")}');
    }
  }
}