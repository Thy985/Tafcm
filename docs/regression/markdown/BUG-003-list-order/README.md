# BUG-003：列表项后紧跟段落时列表被延迟到文档末尾

**来源**: `archive/runs/adl/ADL-LOOP-RUN-008.md`（ADL Loop 闭环，已修复）
**修复位置**: `lib/core/parser/markdown_parser.dart`
**回归守护**: `flutter_app/test/parser/roundtrip_fuzz_test.dart`

## 背景

`line\nbreak\n- item\n中文测试` round-trip 后 `- item` 被移到最后。
根因：普通段落分支前未 `flushListItems()`——挂起的列表要等文档结束才 flush，顺序错乱。

**修复**：段落分支前显式 `flushListItems()`。

## 资产

- `case.json` / `input.md` / `expected.json`（顺序保持不变量）
