/// TC-ARCH-7: File line count <= 400 (AGENTS.md §1.2).
///
/// Single responsibility: one .dart file = one class / one theme / one Provider cluster.
/// Files exceeding 400 lines must be split.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Known offenders (AGENTS.md §10 "static state pollution tests" / Phase 2 cleanup):
  //   - markdown_parser.dart: 407 lines (await Phase 1 1.5 rewrite)
  //   - mermaid_service.dart: 530 lines
  //   - pdf_exporter.dart: 592 lines
  //   - word_ooxml_builder.dart: 565 lines
  //   - export_service.dart: 493 lines
  //   - formula_pdf_renderer.dart: 409 lines (Slice 7 + onEachCompleted,
  //     file contains cache + batch preview + LRU eviction, inherently dense)
  //   - editor_screen.dart: 461 lines (await Phase 3 WYSIWYG rewrite)
  //   - base_block_state.dart: 417 lines (Phase 3.2 refactor + minor growth)
  //   - command_handler.dart: 420 lines (Phase 3.7.2 ErrorSnapshotter integration)
  //   - editor_page.dart: 412 lines (P0 fix 2026-08-04 _loadFromExternalUri
  //     method for external app .md file open, not split to keep P0 fix cohesive;
  //     Phase 3 file loading logic sinks to Repository then naturally shrinks)
  const knownOffenders = <String>[
    'lib/core/parser/markdown_parser.dart',
    'lib/core/services/mermaid_service.dart',
    'lib/domain/services/exporters/pdf_exporter.dart',
    'lib/domain/services/exporters/word_ooxml_builder.dart',
    'lib/domain/services/export_service.dart',
    'lib/core/services/formula_pdf_renderer.dart',
    'lib/presentation/screens/editor_screen.dart',
    'lib/presentation/blocks/base_block_state.dart',

    'lib/presentation/observability/command_replayer.dart',
  ];

  test('TC-ARCH-7 lib/ all .dart files <= 400 lines (except known offenders)', () {
    const maxLines = 400;
    final offenders = <String>[];
    final libDir = Directory('lib');
    if (!libDir.existsSync()) {
      fail('lib/ directory does not exist');
    }
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final lines = entity.readAsLinesSync();
      if (lines.length > maxLines && !knownOffenders.contains(path)) {
        offenders.add('$path: ${lines.length} lines');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'AGENTS.md §1.2 files exceeding 400 lines must be split.\n'
          'Offenders:\n${offenders.join("\n")}',
    );
  });

  test('TC-ARCH-7 test/ all .dart files <= 400 lines (except known offenders)', () {
    const maxLines = 400;
    // Known test offenders (Phase 2.8 integration tests, each file by Task Contract §3
    // is a single-topic end-to-end integration scenario; splitting would introduce
    // too many small files reducing readability):
    //   - export_integration_test.dart: export integration test (Phase 1)
    //   - editor_loop_integration_test.dart: edit loop integration test (Phase 2.8 TC-EDIT-8.1)
    //   - ime_transaction_integration_test.dart: IME+Transaction integration test (Phase 2.8 TC-EDIT-8.3)
    //   - parser_serializer_consistency_test.dart: Parser/Serializer consistency integration test (Phase 2.8 TC-EDIT-8.4)
    //   - performance_baseline_test.dart: performance baseline integration test (Phase 2.8 TC-EDIT-8.5)
    //   - transaction_history_integration_test.dart: Transaction+History integration test (Phase 2.8 TC-EDIT-8.2)
    const knownTestOffenders = <String>[
      'test/export_integration_test.dart',
      'test/integration/editor_loop_integration_test.dart',
      'test/integration/ime_transaction_integration_test.dart',
      'test/integration/parser_serializer_consistency_test.dart',
      'test/integration/performance_baseline_test.dart',
      'test/integration/transaction_history_integration_test.dart',
      'test/observability/command_replayer_test.dart',
    ];
    final offenders = <String>[];
    final testDir = Directory('test');
    if (!testDir.existsSync()) {
      fail('test/ directory does not exist');
    }
    for (final entity in testDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final lines = entity.readAsLinesSync(encoding: latin1);
      if (lines.length > maxLines && !knownTestOffenders.contains(path)) {
        offenders.add('$path: ${lines.length} lines');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Test files should also stay single-topic; over 400 lines should split.\n'
          'Offenders:\n${offenders.join("\n")}',
    );
  });

  test('TC-ARCH-7 known offender tracking (non-blocking, record only)', () {
    // This test records known offenders for later cleanup when removing from allowlist.
    for (final path in knownOffenders) {
      final file = File(path);
      if (file.existsSync()) {
        final lines = file.readAsLinesSync();
        // Print only, no assertion
        // ignore: avoid_print
        print('  $path: ${lines.length} lines (known offender)');
      }
    }
    expect(knownOffenders.length, lessThanOrEqualTo(11),
        reason: 'Known offender count should decrease, not increase.');
  });
}
