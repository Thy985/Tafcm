/// ADI MCP server — Agent-facing wrapper over the ADI CLI.
///
/// Pure-Dart stdio JSON-RPC 2.0 server implementing the Model Context Protocol
/// (MCP) `tools` capability. It does NOT re-implement ADI logic; it shells out
/// to `adi.dart` (the same binary humans use) in `--json` mode, so the Agent
/// and the human always observe identical behavior and the contract is enforced
/// by the exact same, already-tested code path (E2E-ADI-001~004).
///
/// Design:
/// - CLI is for humans (`dart run tools/adi/adi.dart ...`).
/// - MCP is for Agents (this server). Same capabilities, different transport.
/// - The server operates on `<cwd>/.adi` (inherited working directory), exactly
///   like the CLI, so an Agent launches it from the project root and it reads
///   the same `.adi/` the CLI would.
///
/// 落地 ADR-0024 §2.7（CLI/MCP 双入口）+ Phase 3.8 P0（MCP wrapper）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A single MCP tool definition: name, description, JSON-Schema input, and the
/// CLI argument builder that maps MCP `arguments` onto `adi <args>`.
class _Tool {
  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final List<String> Function(Map<String, Object?> args) build;

  _Tool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.build,
  });
}

/// Absolute path to `adi.dart` (sits next to this file).
String get _adiCliPath =>
    File(Platform.script.toFilePath()).parent.uri.resolve('adi.dart').toFilePath();

/// The tool catalogue. Keep in lock-step with `adi.dart`'s command set.
final List<_Tool> _tools = [
  _Tool(
    name: 'adi_doctor',
    description: 'ADI self-check: reports .adi/ storage health, schema and '
        'protocol version, and observation count.',
    inputSchema: _emptySchema(),
    build: (_) => ['doctor'],
  ),
  _Tool(
    name: 'adi_latest_error',
    description: 'Get the latest recorded error: classified error type, '
        'session/trace ids, snapshot availability, and suggested next actions.',
    inputSchema: _emptySchema(),
    build: (_) => ['latest-error'],
  ),
  _Tool(
    name: 'adi_trace_show',
    description: 'Show the causal trace chain for a trace id '
        '(interaction -> command -> transaction -> render -> error).',
    inputSchema: _schema({
      'trace_id': _string('The trace id to inspect (e.g. trc_001).'),
    }, required: ['trace_id']),
    build: (a) => ['trace', 'show', _str(a, 'trace_id')],
  ),
  _Tool(
    name: 'adi_replay',
    description: 'Replay a session to confirm the fault reproduces. Returns '
        'reproduced / notReproduced / inconclusive.',
    inputSchema: _schema({
      'session_id': _string('The session id to replay (e.g. sess_A).'),
    }, required: ['session_id']),
    build: (a) => ['replay', _str(a, 'session_id')],
  ),
  _Tool(
    name: 'adi_validate',
    description: 'Validate an Agent fix (replay + invariant). Returns after='
        'pass | still_failing | inconclusive. Does NOT run flutter test '
        '(that is Change Impact Analysis, ADR-0026).',
    inputSchema: _schema({
      'session_id': _string('The session id the fix targets.'),
    }, required: ['session_id']),
    build: (a) => ['validate', '--after-fix', _str(a, 'session_id')],
  ),
  _Tool(
    name: 'adi_failures_list',
    description: 'List aggregated failures, or rebuild the aggregate from '
        'observations. Pass aggregate=true to rebuild.',
    inputSchema: _schema({
      'aggregate': _boolean('If true, re-aggregate observations into failures '
          'before listing.'),
    }),
    build: (a) {
      final agg = a['aggregate'];
      final doAgg = agg is bool && agg;
      return ['failures', doAgg ? 'aggregate' : 'list'];
    },
  ),
  _Tool(
    name: 'adi_agent_context',
    description: 'Generate Agent-consumable Markdown context: last failure, '
        'evidence, and next actions.',
    inputSchema: _emptySchema(),
    build: (_) => ['agent-context'],
  ),
  _Tool(
    name: 'adi_import',
    description: 'Import an ExportPipeline package (.zip or directory) into '
        '.adi/ so the other tools can consume it.',
    inputSchema: _schema({
      'source': _string('Path to the .zip or unpacked ExportPipeline directory.'),
      'out': _string('Optional output directory (defaults to <cwd>/.adi).'),
    }, required: ['source']),
    build: (a) {
      final args = ['import', _str(a, 'source')];
      final out = a['out'];
      if (out is String && out.isNotEmpty) args.addAll(['--out', out]);
      return args;
    },
  ),
];

void main(List<String> args) {
  _runServer().catchError((e) {
    stderr.writeln('adi-mcp fatal: $e');
    exit(1);
  });
}

Future<void> _runServer() async {
  final stdinLines =
      stdin.transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in stdinLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    Map<String, Object?>? msg;
    try {
      msg = jsonDecode(trimmed) as Map<String, Object?>;
    } catch (_) {
      continue; // ignore non-JSON noise on stdin
    }
    final method = msg['method'] as String?;
    final id = msg['id'];
    final isNotification = id == null;

    switch (method) {
      case 'initialize':
        if (!isNotification) {
          _send(id, result: {
            'protocolVersion': '2024-11-05',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'adi-mcp', 'version': '0.1.0'},
          });
        }
      case 'notifications/initialized':
        // No response required.
        break;
      case 'ping':
        if (!isNotification) _send(id, result: {});
      case 'tools/list':
        if (!isNotification) {
          _send(id, result: {'tools': _tools.map(_toolSpec).toList()});
        }
      case 'tools/call':
        if (!isNotification) {
          await _handleToolCall(id, msg['params'] as Map<String, Object?>?);
        }
      default:
        if (!isNotification) {
          _send(id, error: {
            'code': -32601,
            'message': 'Method not found: $method',
          });
        }
    }
  }
}

Future<void> _handleToolCall(
  Object? id,
  Map<String, Object?>? params,
) async {
  final name = params?['name'] as String?;
  final arguments =
      (params?['arguments'] as Map?)?.cast<String, Object?>() ?? {};
  final tool = _tools.where((t) => t.name == name).firstOrNull;
  if (tool == null) {
    _send(id, error: {'code': -32602, 'message': 'Unknown tool: $name'});
    return;
  }
  try {
    final cliArgs = tool.build(arguments);
    final result = await Process.run(
      Platform.executable,
      [_adiCliPath, ...cliArgs, '--json'],
      workingDirectory: Directory.current.path,
    );
    final stdoutStr = (result.stdout as String).trim();
    final isError = result.exitCode != 0;
    _send(id, result: {
      'content': [
        {
          'type': 'text',
          'text': stdoutStr.isNotEmpty ? stdoutStr : (result.stderr as String),
        }
      ],
      'isError': isError,
    });
  } catch (e) {
    _send(id, result: {
      'content': [
        {'type': 'text', 'text': 'adi-mcp tool error: $e'}
      ],
      'isError': true,
    });
  }
}

void _send(Object? id, {Map<String, Object?>? result, Map<String, Object?>? error}) {
  final payload = <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
  };
  if (error != null) {
    payload['error'] = error;
  } else {
    payload['result'] = result ?? {};
  }
  stdout.writeln(jsonEncode(payload));
}

Map<String, Object?> _toolSpec(_Tool t) => {
      'name': t.name,
      'description': t.description,
      'inputSchema': t.inputSchema,
    };

Map<String, Object?> _emptySchema() => {'type': 'object', 'properties': {}};

Map<String, Object?> _schema(
  Map<String, Map<String, Object?>> properties, {
  List<String> required = const [],
}) =>
    {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };

Map<String, Object?> _string(String description) =>
    {'type': 'string', 'description': description};

Map<String, Object?> _boolean(String description) =>
    {'type': 'boolean', 'description': description};

String _str(Map<String, Object?> a, String key) {
  final v = a[key];
  if (v is! String || v.isEmpty) {
    throw ArgumentError('Missing required string argument: $key');
  }
  return v;
}
