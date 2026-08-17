/// Run #005 proof driver helper: applies the agent fix to production source.
///
/// Usage:
///   dart run tools/adi/run005_apply_fix.dart apply <path>
///   dart run tools/adi/run005_apply_fix.dart revert <path>
///
/// `apply` removes the fault-injection block (and its now-unused import) from
/// code_block.dart — the git-diff-auditable production change (B 层, P2).
/// `revert` re-inserts both, used as a safety fallback; the driver script's
/// authoritative restore is `cp <backup>`.
library;

import 'dart:io';

/// 被移除的 fault-injection 块（与 code_block.dart:184-188 逐字符一致）。
const _faultBlock = "            // Fault injection (ADR-0024 §9): when enabled, inject a child that\n"
    "            // deterministically overflows its bounded parent so the observability\n"
    "            // layer captures a known RenderOverflow — no flaky real bug required.\n"
    "            if (FaultInjection.renderOverflowEnabled)\n"
    "              const SizedBox(height: 100000),\n";

/// import 锚点（revert 时在 block_types 之后重新插入 fault_injection import）。
const _importAnchor = "import '../../../core/editing/block_types.dart';\n";
const _faultImport = "import '../../../core/observability/fault_injection.dart';\n";

/// 块插入锚点（revert 时在 HighlightView 之后、children 列表闭合前插入）。
const _blockAnchor = "            ),\n"
    "          ],\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "  }\n"
    "\n"
    "  /// 记录代码块主题渲染可观测事件";

void main(List<String> args) {
  final mode = args.isNotEmpty ? args[0] : 'apply';
  final path = args.length > 1
      ? args[1]
      : 'flutter_app/lib/presentation/blocks/code/code_block.dart';
  final file = File(path);
  final content = file.readAsStringSync();
  final out = switch (mode) {
    'apply' => _applyFix(content),
    'revert' => _revertFix(content),
    _ => throw ArgumentError('unknown mode: $mode (use apply|revert)'),
  };
  file.writeAsStringSync(out);
  stdout.writeln(
    '[run005-fix] $mode -> $path (${content.length} -> ${out.length} chars)',
  );
}

/// 移除 fault-injection 块 + 已无用的 import（生产修复本体）。
String _applyFix(String content) {
  var out = content.replaceAll(_faultBlock, '');
  out = out.replaceAll(_faultImport, '');
  return out;
}

/// 重新插入 import + fault-injection 块（应急回退，权威还原走 cp backup）。
String _revertFix(String content) {
  var out = content.replaceAll(
    _importAnchor,
    '$_importAnchor$_faultImport',
  );
  out = out.replaceAll(
    _blockAnchor,
    "            ),\n"
        "            // Fault injection (ADR-0024 §9): when enabled, inject a child that\n"
        "            // deterministically overflows its bounded parent so the observability\n"
        "            // layer captures a known RenderOverflow — no flaky real bug required.\n"
        "            if (FaultInjection.renderOverflowEnabled)\n"
        "              const SizedBox(height: 100000),\n"
        "          ],\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n"
        "\n"
        "  /// 记录代码块主题渲染可观测事件",
  );
  return out;
}
