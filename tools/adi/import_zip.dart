/// ADI ZipImporter — compatibility/migration layer (ADR-0024 §9.6, v0.1).
///
/// The 3.7 `ExportPipeline` produces a *post-incident* snapshot (see
/// `debug/02/`), whose on-disk format differs from the runtime `.adi/`
/// schema the CLI consumes. This module translates one into the other so
/// that real-device exports become immediately consumable by
/// `tools/adi/adi.dart` without changing the Flutter `ExportPipeline`.
///
/// It is explicitly a *compat/migration* layer, not ADI itself:
/// `debug/02` shows `commandCount=0`/`interactionCount=0`, i.e. the full
/// `input -> command -> transaction -> render -> error` chain is absent.
/// ZipImporter fixes *format*, not *evidence completeness*.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// Protocol version written into the generated `.adi/schema_version.json`.
const String kAdiProtocolVersion = '0.1';
const int kSchemaVersion = 1;

/// Transforms an `ExportPipeline` package (directory or `.zip`) into the
/// `.adi/` layout under [outputDir] (defaults to `<cwd>/.adi`).
///
/// Existing `.adi/` entries are merged (additive); observations/traces are
/// keyed by their derived ids, so re-importing the same package is
/// idempotent.
Future<void> importExport(String sourcePath, {String? outputDir}) async {
  final root = outputDir ?? Directory.current.path;
  final adi = Directory('$root/.adi');
  if (!adi.existsSync()) adi.createSync(recursive: true);

  final srcDir = await _resolveSource(sourcePath);

  final metadata = _readJson('${srcDir.path}/metadata.json');
  final snapshot = _readJson('${srcDir.path}/snapshot.json');
  final trace = _readJson('${srcDir.path}/trace.json');
  final invariant = _readJson('${srcDir.path}/invariant_report.json');

  final sessionId =
      (snapshot?['sessionId'] as String?) ?? (metadata?['sessionId'] as String?);

  // 1. schema_version.json
  _atomicWrite('${adi.path}/schema_version.json', {
    'schema_version': kSchemaVersion,
    'adi_protocol_version': kAdiProtocolVersion,
    'imported_from': 'ExportPipeline',
  });

  // 2. observation (only if a snapshot/error exists)
  if (snapshot != null && sessionId != null) {
    final observation = transformObservation(snapshot, metadata, sessionId);
    _atomicWrite('${adi.path}/observations/${observation["id"]}.json', observation);

    // 3. trace (derived from the export trace, keyed by the observation's traceId)
    if (trace != null) {
      final t = transformTrace(trace, sessionId, observation['traceId'] as String);
      _atomicWrite('${adi.path}/traces/${t["traceId"]}.json', t);
    }
  }

  // 4. session: invariant_report (transformed) + original metadata for provenance.
  if (sessionId != null) {
    final sessionDir = Directory('${adi.path}/sessions/$sessionId');
    if (!sessionDir.existsSync()) sessionDir.createSync(recursive: true);
    if (invariant != null) {
      _atomicWrite(
        '${sessionDir.path}/invariant_report.json',
        transformInvariant(invariant),
      );
    }
    if (metadata != null) {
      _atomicWrite('${sessionDir.path}/metadata.json', metadata);
    }
    // NOTE: replay.json is intentionally NOT synthesized. A real-device
    // export carries no replay evidence, so `adi validate` must resolve to
    // `inconclusive` rather than a false `pass`.
  }
}

/// Maps an `ExportPipeline` snapshot into an ADI `observation` record.
Map<String, Object?> transformObservation(
  Map<String, Object?> snapshot,
  Map<String, Object?>? metadata,
  String sessionId,
) {
  final snapshotId = snapshot['id'] as String? ?? 'unknown';
  final traceId = 'trc_${_shortHash('$sessionId|$snapshotId')}';
  final message = snapshot['message'] as String? ?? '';
  final stackHash = _shortHash(message);
  return {
    'id': snapshotId,
    'errorType': snapshot['type'] ?? 'unknown',
    'message': message,
    'sessionId': sessionId,
    'time': snapshot['timestamp'],
    'traceId': traceId,
    'stackHash': stackHash,
  };
}

/// Maps an `ExportPipeline` trace into an ADI `trace` (flat span list).
///
/// The export distinguishes interactions/commands/transactions/renders; the
/// CLI schema flattens them into `spans` with a `layer` discriminator.
Map<String, Object?> transformTrace(
  Map<String, Object?> trace,
  String sessionId,
  String traceId,
) {
  final spans = <Map<String, Object?>>[];
  _appendSpans(spans, trace['interactions'] as List?, 'interaction');
  _appendSpans(spans, trace['commands'] as List?, 'command');
  _appendSpans(spans, trace['transactions'] as List?, 'transaction');
  _appendSpans(spans, trace['renders'] as List?, 'render');
  return {
    'sessionId': sessionId,
    'traceId': traceId,
    'spans': spans,
  };
}

void _appendSpans(
  List<Map<String, Object?>> spans,
  List<dynamic>? items,
  String layer,
) {
  if (items == null) return;
  for (var i = 0; i < items.length; i++) {
    final item = items[i] as Map<String, Object?>;
    spans.add({
      'layer': layer,
      'spanId': '${layer}_$i',
      'description': _describe(item),
    });
  }
}

String _describe(Map<String, Object?> item) {
  final type = item['type'] ?? 'unknown';
  final relevant = item.entries
      .where((e) => e.key != 'type' && e.key != 'timestamp')
      .map((e) => '${e.key}=${e.value}')
      .join(', ');
  return relevant.isEmpty ? '$type' : '$type($relevant)';
}

/// Maps an `ExportPipeline` invariant report into the ADI invariant schema.
///
/// The export records `result: "not_checked"` with a list of invariant
/// *names* but no computed violations. We faithfully preserve the names as
/// `allNames`, leave `failedNames` empty (no violation was recorded), and
/// surface `evaluated: false` + `originalResult` so the gap is explicit.
/// `adi validate` treats a missing replay as `inconclusive`, which is the
/// safety net that prevents a false `pass` here.
Map<String, Object?> transformInvariant(Map<String, Object?> invariant) {
  final names = (invariant['invariants'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
      <String>[];
  final result = invariant['result'] as String? ?? 'unknown';
  final evaluated =
      result == 'checked' || result == 'pass' || result == 'fail';
  return {
    'allNames': names,
    'failedNames': const <String>[],
    'evaluated': evaluated,
    'originalResult': result,
    if (!evaluated)
      'note':
          'Source invariant_report.result=$result; ADI requires replay '
          'evidence for a conclusion.',
  };
}

// --- helpers --------------------------------------------------------------

Future<Directory> _resolveSource(String sourcePath) async {
  final file = File(sourcePath);
  if (sourcePath.endsWith('.zip') && file.existsSync()) {
    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final tmp = Directory.systemTemp.createTempSync('adi_import_');
    for (final fileEntry in archive) {
      final path = '${tmp.path}/${fileEntry.name}';
      if (fileEntry.isFile) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileEntry.content as List<int>);
      } else {
        Directory(path).createSync(recursive: true);
      }
    }
    return tmp;
  }
  final dir = Directory(sourcePath);
  if (!dir.existsSync()) {
    throw ArgumentError('Import source not found: $sourcePath');
  }
  return dir;
}

Map<String, Object?>? _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } on Object {
    return null;
  }
}

String _shortHash(String input) =>
    sha256.convert(input.codeUnits).toString().substring(0, 16);

void _atomicWrite(String path, Map<String, Object?> data) {
  final file = File(path);
  file.createSync(recursive: true);
  final tmp = File('$path.tmp');
  tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  tmp.renameSync(path);
}
