/// Unit tests for [ZipImporter] (ADR-0024 §9.6, v0.1 compat layer).
///
/// Exercises the pure transform functions and the end-to-end
/// `importExport` directory flow without spawning the CLI, so the
/// mapping contract (ExportPipeline package -> `.adi/`) is pinned
/// independently of `e2e_scenarios_test.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../import_zip.dart';

void main() {
  group('ZipImporter transformObservation', () {
    test('maps ExportPipeline snapshot -> ADI observation', () {
      final snapshot = {
        'id': 'err_x',
        'timestamp': '2026-08-11T10:21:49.300256',
        'type': 'GlobalError',
        'message': 'A RenderLine overflowed by 66 pixels on the right.',
        'sessionId': 'sess_6b62',
      };
      final obs = transformObservation(snapshot, {'sessionId': 'sess_6b62'}, 'sess_6b62');
      expect(obs['id'], 'err_x');
      expect(obs['errorType'], 'RenderOverflow'); // classified from overflow message
      expect(obs['errorTypeRaw'], 'GlobalError'); // raw fidelity preserved
      expect(obs['snapshotAvailable'], isTrue);
      expect(obs['message'], contains('RenderLine overflowed'));
      expect(obs['sessionId'], 'sess_6b62');
      expect(obs['time'], '2026-08-11T10:21:49.300256');
      expect(obs['traceId'], startsWith('trc_')); // derived, stable
      expect(obs['stackHash'], isA<String>()); // derived from message
    });

    test('non-overflow message keeps raw type (no mis-classification)', () {
      final snapshot = {
        'id': 'err_z',
        'type': 'GlobalError',
        'message': 'something unrelated crashed',
        'sessionId': 'sess_q',
      };
      final obs = transformObservation(snapshot, null, 'sess_q');
      expect(obs['errorType'], 'GlobalError');
      expect(obs['errorTypeRaw'], 'GlobalError');
    });

    test('falls back to metadata sessionId when snapshot lacks one', () {
      final snapshot = {
        'id': 'err_y',
        'type': 'GlobalError',
        'message': 'boom',
      };
      final obs = transformObservation(snapshot, {'sessionId': 'sess_z'}, 'sess_z');
      expect(obs['sessionId'], 'sess_z');
    });
  });

  group('ZipImporter transformTrace', () {
    test('flattens render spans; empty cmd/interaction/transaction -> 0 (no snapshot)', () {
      final trace = {
        'interactions': <dynamic>[],
        'commands': <dynamic>[],
        'transactions': <dynamic>[],
        'renders': [
          {'type': 'CodeBlockThemeRendered', 'themeName': 'github'},
          {'type': 'CodeBlockLanguageChipRendered', 'shown': false},
        ],
      };
      final t = transformTrace(trace, 'sess_6b62', 'trc_abc', null);
      expect(t['sessionId'], 'sess_6b62');
      expect(t['traceId'], 'trc_abc');
      final spans = t['spans'] as List;
      expect(spans.length, 2);
      expect(spans.every((s) => (s as Map)['layer'] == 'render'), isTrue);
      // every span carries a monotonic seq for causal-chain reconstruction
      final seqs = spans.map((s) => (s as Map)['seq']).toList();
      expect(seqs, [0, 1]);
    });

    test('combine all four layers in order, then append error link from snapshot', () {
      final trace = {
        'interactions': [
          {'type': 'Tap', 'action': 'PasteText'},
        ],
        'commands': [
          {'type': 'InsertTextCommand'},
        ],
        'transactions': [
          {'type': 'TransactionCommit', 'description': 'BlockTree update'},
        ],
        'renders': [
          {'type': 'CodeBlockRenderer', 'detail': 'build'},
        ],
      };
      final snapshot = {
        'type': 'GlobalError',
        'message': 'A RenderLine overflowed by 66 pixels on the right.',
      };
      final spans = (transformTrace(trace, 's', 't', snapshot)['spans'] as List)
          .map((s) => (s as Map)['layer'])
          .toList();
      expect(
        spans,
        ['interaction', 'command', 'transaction', 'render', 'error'],
      );
      // seq is monotonic across the flattened, cross-layer chain
      final seqs = (transformTrace(trace, 's', 't', snapshot)['spans'] as List)
          .map((s) => (s as Map)['seq'] as int)
          .toList();
      expect(seqs, [0, 1, 2, 3, 4]);
      // error link description is the canonical overflow label
      final errorSpan = (transformTrace(trace, 's', 't', snapshot)['spans'] as List)
          .last as Map;
      expect(errorSpan['description'], 'RenderParagraph overflow');
    });
  });

  group('ZipImporter transformInvariant', () {
    test('not_checked -> evaluated false, no false violations, note present', () {
      final inv = {
        'invariants': [
          'CursorExists',
          'SelectionValid',
          'BlockTreeAcyclic',
          'ParentChildValid',
          'HistoryConsistent',
        ],
        'result': 'not_checked',
      };
      final out = transformInvariant(inv);
      expect(out['allNames'], hasLength(5));
      expect(out['failedNames'], isEmpty);
      expect(out['evaluated'], isFalse);
      expect(out['originalResult'], 'not_checked');
      expect(out.containsKey('note'), isTrue);
    });

    test('checked -> evaluated true (evidence completeness preserved)', () {
      final inv = {
        'invariants': ['CursorExists', 'SelectionValid'],
        'result': 'checked',
        'failedNames': <String>[],
      };
      final out = transformInvariant(inv);
      expect(out['evaluated'], isTrue);
      expect(out.containsKey('note'), isFalse);
    });
  });

  group('ZipImporter importExport', () {
    late Directory src;
    late Directory out;

    setUp(() {
      src = Directory.systemTemp.createTempSync('adi_imp_src_');
      out = Directory.systemTemp.createTempSync('adi_imp_out_');
      _write(src.path, 'metadata.json', {'sessionId': 'sess_6b62'});
      _write(src.path, 'snapshot.json', {
        'id': 'err_x',
        'timestamp': '2026-08-11T10:21:49.300256',
        'type': 'GlobalError',
        'message': 'A RenderLine overflowed by 66 pixels on the right.',
        'sessionId': 'sess_6b62',
      });
      _write(src.path, 'trace.json', {
        'renders': [
          {'type': 'CodeBlockThemeRendered'},
        ],
      });
      _write(src.path, 'invariant_report.json', {
        'invariants': ['CursorExists', 'SelectionValid'],
        'result': 'not_checked',
      });
    });

    tearDown(() {
      try {
        src.deleteSync(recursive: true);
      } catch (_) {}
      try {
        out.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('produces consumable .adi/: observation + trace + invariant, NO replay', () async {
      await importExport(src.path, outputDir: out.path);

      final adi = Directory('${out.path}/.adi');
      expect(adi.existsSync(), isTrue);
      expect(File('${adi.path}/schema_version.json').existsSync(), isTrue);

      // observation keyed by snapshot id
      expect(File('${adi.path}/observations/err_x.json').existsSync(), isTrue);

      // trace keyed by the *derived* traceId from the observation
      final obs = _read('${adi.path}/observations/err_x.json');
      final traceId = obs['traceId'] as String;
      expect(File('${adi.path}/traces/$traceId.json').existsSync(), isTrue);

      // invariant transformed + metadata copied for provenance
      expect(
        File('${adi.path}/sessions/sess_6b62/invariant_report.json').existsSync(),
        isTrue,
      );
      expect(
        File('${adi.path}/sessions/sess_6b62/metadata.json').existsSync(),
        isTrue,
      );

      // Safety-critical: the real-device export carries no replay, so the
      // importer must NOT synthesize one. validate() relies on this gap to
      // return `inconclusive` rather than a false `pass`.
      expect(
        File('${adi.path}/sessions/sess_6b62/replay.json').existsSync(),
        isFalse,
      );

      final inv = _read('${adi.path}/sessions/sess_6b62/invariant_report.json');
      expect(inv['evaluated'], isFalse);
    });

    test('re-import is idempotent (merge, not duplicate)', () async {
      await importExport(src.path, outputDir: out.path);
      await importExport(src.path, outputDir: out.path);
      final obsDir = Directory('${out.path}/.adi/observations');
      final count = obsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .length;
      expect(count, 1); // err_x.json single entry
    });

    test('AS-RG.1：zip 含 replay 证据时透传 commands.jsonl + replay.json', () async {
      // ExportPipeline（AS-RG.1 后）会在 zip 中携带 replay 序列与 App 端结果。
      _write(src.path, 'commands.jsonl',
          {'_placeholder': true}); // overwritten below as raw text
      File('${src.path}/commands.jsonl').writeAsStringSync(
        '{"commandName":"InsertTextCommand","params":{"blockId":"b1","text":"hello"},"origin":"keyboard","beforeStateHash":"hb","afterStateHash":"ha"}\n',
      );
      _write(src.path, 'replay.json', {
        'status': 'reproduced',
        'commandsExecuted': 1,
        'failedAt': 'step 0: InsertTextCommand',
      });

      await importExport(src.path, outputDir: out.path);

      final adi = Directory('${out.path}/.adi');
      // 透传：App 端实际运行的 replay 结果落到 session 目录，CLI `adi replay`
      // 可读到 reproduced（不再是 inconclusive）。
      final replay = _read('${adi.path}/sessions/sess_6b62/replay.json');
      expect(replay['status'], 'reproduced');
      expect(replay['commandsExecuted'], 1);

      // 透传：replay 序列原样保留供诊断/复现。
      final seq = File('${adi.path}/sessions/sess_6b62/commands.jsonl')
          .readAsStringSync();
      expect(seq, contains('InsertTextCommand'));
      expect(seq, contains('"afterStateHash":"ha"'));
    });
  });
}

void _write(String dir, String name, Map<String, Object?> data) {
  final file = File('$dir/$name')..createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}

Map<String, Object?> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
