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
  stderr.writeln('  failures list       List recent failures');
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
  final dir = Directory('$_adiRoot/failures');
  if (!dir.existsSync()) {
    if (json) {
      print(jsonEncode({'status': 'no_failures', 'failures': []}));
    } else {
      print('No failures recorded.');
    }
    return;
  }

  final failures = <Map<String, Object?>>[];
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final f = _readJson(entity.path);
    if (f != null) failures.add(f);
  }

  if (json) {
    print(jsonEncode({'status': 'ok', 'count': failures.length, 'failures': failures}));
  } else {
    print('Failures (${failures.length}):');
    for (final f in failures) {
      print('  ${f["failureId"]}: ${f["errorType"]} ×${f["occurrences"]} [${f["status"]}]');
    }
  }
}