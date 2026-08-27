# BUG-002：`|` 开头非表格行被静默吞掉

**来源**: `archive/runs/adl/ADL-LOOP-RUN-008.md`（ADL Loop 闭环，已修复）
**修复位置**: `lib/core/parser/markdown_parser.dart`
**回归守护**: `flutter_app/test/parser/roundtrip_fuzz_test.dart`

## 背景

`|pipe| a_b trailing`（不以 `|` 结尾、非合法表格行）在 parse→serialize 后整行消失。
根因：`trimmedLine.startsWith('|')` 分支中 `_parseTableRow` 返回 null 时仍 `continue`，
未降级为段落。

**修复**：cells == null 时不再 continue，flushTable 后降级为普通段落解析。

## 资产

- `case.json` / `input.md` / `expected.json`（行保留不变量）
