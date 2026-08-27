# BUG-001：多行段落合并丢失硬换行

**来源**: `archive/runs/adl/ADL-LOOP-RUN-008.md`（ADL Loop 闭环，已修复）
**修复位置**: `lib/core/parser/markdown_parser.dart`（+17/-3）
**回归守护**: `flutter_app/test/parser/roundtrip_fuzz_test.dart`（1000 轮常驻）

## 背景

parser 合并多行段落到 `pendingParagraph` 时用 `children.addAll(inline)` 直接拼接，
`\n`（Markdown hard-break）未保留 → round-trip 后换行信息丢失，结构不一致。

**修复**：合并前若 children 非空，先 `add(TextElement('\n'))`。

## 资产

- `case.json`：元数据（id / 来源 / 状态 / 回归测试）
- `input.md`：最小复现输入
- `expected.json`：期望结构不变量（inline 数量 + hard-break 保留）

## 复现

```bash
cd flutter_app && flutter test test/parser/roundtrip_fuzz_test.dart
```
