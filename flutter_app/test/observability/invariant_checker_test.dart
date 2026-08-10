/// TC-EDIT-INV: InvariantChecker 单元测试（G1 修复，2026-08-10）。
///
/// 覆盖 6 类 EditorInvariant：
/// - CursorExists：cursor 指向存在的 Block → 通过；指向已删 → 失败
/// - SelectionValid：selection 越界 / 反转 → 失败
/// - BlockTreeAcyclic：parentId 链形成环 → 失败
/// - ParentChildValid：parentId 悬空 → 失败
/// - EditorNotEmpty：编辑器为空 → 失败
/// - HistoryConsistent：history 引用已删 blockId → 失败
///
/// **G1 修复背景**：原 InvariantChecker 无任何单元测试守门，
/// InvariantReportSnapshot 占位符导致诊断 zip 永远显示 not_checked。
/// 本测试既守门 6 类 invariant 正确性,也验证 InvariantReportSnapshot
/// 序列化链路（含 List 等集合字段）的可测性。
library;

import 'package:flutter_test/flutter_test.dart';


import 'package:formula_fix/core/observability/invariant_checker.dart';
import 'package:formula_fix/core/observability/models.dart';
import 'package:formula_fix/data/models/document.dart';

/// 构造单个 [EditorInvariantContext] 的 helper。
EditorInvariantContext _ctx({
  required String blockId,
  required String source,
  String? parentId,
  Set<String> historyBlockIds = const {},
}) {
  // fromElement 走 block_serializer 还原 source
  // （测试中直接给 source，避免依赖完整 DocumentElement → source 链路）
  final element = ParagraphElement(children: [
    TextElement(source),
  ]);
  return EditorInvariantContext(
    blockId: blockId,
    element: element,
    parentId: parentId,
    historyBlockIds: historyBlockIds,
  );
}

void main() {
  group('TC-EDIT-INV.1 CursorExists', () {
    test('cursor 指向存在的 Block → 通过', () {
      final checker = InvariantChecker(cursorBlockId: 'b1');
      final state = [_ctx(blockId: 'b1', source: 'hello')];
      final failures = checker.checkAll(state);
      expect(failures, isEmpty);
    });

    test('cursor 指向已删除 Block → 失败', () {
      final checker = InvariantChecker(cursorBlockId: 'gone');
      final state = [_ctx(blockId: 'b1', source: 'hello')];
      final failures = checker.checkAll(state);
      expect(failures.length, equals(1));
      expect(failures.single.invariantName, equals('CursorExists'));
    });

    test('cursorBlockId 为 null → 跳过（无光标）', () {
      final checker = InvariantChecker();
      final state = [_ctx(blockId: 'b1', source: 'hello')];
      expect(checker.checkAll(state), isEmpty);
    });
  });

  group('TC-EDIT-INV.2 SelectionValid', () {
    test('selection 在范围内 → 通过', () {
      final checker = InvariantChecker(
        selectionBlockId: 'b1',
        selectionStart: 0,
        selectionEnd: 3,
      );
      final state = [_ctx(blockId: 'b1', source: 'hello')];
      expect(checker.checkAll(state), isEmpty);
    });

    test('selection 终点越界 → 失败', () {
      final checker = InvariantChecker(
        selectionBlockId: 'b1',
        selectionStart: 0,
        selectionEnd: 100,
      );
      final state = [_ctx(blockId: 'b1', source: 'hello')];
      final failures = checker.checkAll(state);
      expect(failures.length, equals(1));
      expect(failures.single.invariantName, equals('SelectionValid'));
    });

    test('selection 起点 > 终点 → 失败', () {
      final checker = InvariantChecker(
        selectionBlockId: 'b1',
        selectionStart: 5,
        selectionEnd: 2,
      );
      final state = [_ctx(blockId: 'b1', source: 'hello')];
      final failures = checker.checkAll(state);
      expect(failures.single.invariantName, equals('SelectionValid'));
    });

    test('selection 指向已删 block → 失败', () {
      final checker = InvariantChecker(
        selectionBlockId: 'gone',
        selectionStart: 0,
        selectionEnd: 3,
      );
      final state = [_ctx(blockId: 'b1', source: 'hello')];
      final failures = checker.checkAll(state);
      expect(failures.single.invariantName, equals('SelectionValid'));
    });

    test('selection 字段全 null → 跳过', () {
      final checker = InvariantChecker();
      final state = [_ctx(blockId: 'b1', source: 'hello')];
      expect(checker.checkAll(state), isEmpty);
    });
  });

  group('TC-EDIT-INV.3 BlockTreeAcyclic', () {
    test('parentId 链无环 → 通过', () {
      final state = [
        _ctx(blockId: 'root', source: 'r'),
        _ctx(blockId: 'child', source: 'c', parentId: 'root'),
        _ctx(blockId: 'grand', source: 'g', parentId: 'child'),
      ];
      final checker = InvariantChecker();
      expect(checker.checkAll(state), isEmpty);
    });

    test('parentId 自环 → 失败', () {
      final state = [
        _ctx(blockId: 'a', source: 'a', parentId: 'a'),
      ];
      final checker = InvariantChecker();
      final failures = checker.checkAll(state);
      expect(failures.single.invariantName, equals('BlockTreeAcyclic'));
    });

    test('parentId 形成 a → b → a 环 → 失败', () {
      final state = [
        _ctx(blockId: 'a', source: 'a', parentId: 'b'),
        _ctx(blockId: 'b', source: 'b', parentId: 'a'),
      ];
      final checker = InvariantChecker();
      final failures = checker.checkAll(state);
      expect(failures.single.invariantName, equals('BlockTreeAcyclic'));
    });
  });

  group('TC-EDIT-INV.4 ParentChildValid', () {
    test('parentId 指向存在的 Block → 通过', () {
      final state = [
        _ctx(blockId: 'root', source: 'r'),
        _ctx(blockId: 'child', source: 'c', parentId: 'root'),
      ];
      final checker = InvariantChecker();
      expect(checker.checkAll(state), isEmpty);
    });

    test('parentId 悬空 → 失败', () {
      final state = [
        _ctx(blockId: 'orphan', source: 'o', parentId: 'ghost'),
      ];
      final checker = InvariantChecker();
      final failures = checker.checkAll(state);
      expect(failures.single.invariantName, equals('ParentChildValid'));
    });
  });

  group('TC-EDIT-INV.5 EditorNotEmpty', () {
    test('至少 1 个 Block → 通过', () {
      final checker = InvariantChecker();
      final state = [_ctx(blockId: 'b1', source: 'x')];
      expect(checker.checkAll(state), isEmpty);
    });

    test('编辑器为空 → 失败', () {
      final checker = InvariantChecker();
      final failures = checker.checkAll(const []);
      expect(failures.single.invariantName, equals('EditorNotEmpty'));
    });
  });

  group('TC-EDIT-INV.6 HistoryConsistent', () {
    test('history 引用现存 block → 通过', () {
      final state = [
        _ctx(
          blockId: 'b1',
          source: 'x',
          historyBlockIds: {'b1', 'b2'},
        ),
        _ctx(blockId: 'b2', source: 'y'),
      ];
      final checker = InvariantChecker();
      expect(checker.checkAll(state), isEmpty);
    });

    test('history 引用已删 block → 失败', () {
      final state = [
        _ctx(
          blockId: 'b1',
          source: 'x',
          historyBlockIds: {'b1', 'ghost'},
        ),
      ];
      final checker = InvariantChecker();
      final failures = checker.checkAll(state);
      expect(failures.single.invariantName, equals('HistoryConsistent'));
    });

    test('history 为空 → 跳过', () {
      final state = [_ctx(blockId: 'b1', source: 'x')];
      final checker = InvariantChecker();
      expect(checker.checkAll(state), isEmpty);
    });
  });

  group('TC-EDIT-INV.7 InvariantReportSnapshot 序列化（G1 修复）', () {
    test('toJson 包含 checkedAt / result / failedNames / allNames', () {
      final snap = InvariantReportSnapshot(
        checkedAt: DateTime.utc(2026, 8, 10, 12),
        result: InvariantCheckResult.failed,
        failedNames: ['SelectionValid'],
        allNames: const [
          'CursorExists',
          'SelectionValid',
          'BlockTreeAcyclic',
          'ParentChildValid',
          'EditorNotEmpty',
          'HistoryConsistent',
        ],
      );
      final json = snap.toJson();
      expect(json['result'], equals('failed'));
      expect(json['failedNames'], equals(['SelectionValid']));
      expect(json['allNames'], hasLength(6));
      expect(json['stateHash'], isNull);
    });

    test('passed 时 failedNames 为空', () {
      final snap = InvariantReportSnapshot(
        checkedAt: DateTime.utc(2026, 8, 10, 12),
        result: InvariantCheckResult.passed,
        failedNames: const [],
        allNames: const ['CursorExists'],
      );
      expect(snap.toJson()['result'], equals('passed'));
    });
  });
}