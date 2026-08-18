# ADL Loop Run #008 — Phase 3.9 Capability Audit Batch 1

**日期**: 2026-08-18
**前置**: Run #001-007 已完成 ADI 全链路（Observe → Persist → Orchestrate → Validate → Verify → Autonomous → Formal）
**状态**: ✅ Batch 1 审计完成（12 项全部执行；发现 3 个真实 bug，已修复并产出 Regression Asset）
**下一步**: Batch 2（Behavior Audit 或 Batch 1 扩展审计项）

---

## 执行摘要

Run #008 执行 Phase 3.9 第一步：**Capability Audit Batch 1**（见
ADL-LOOP-RUN-008-PLAN.md）。审计覆盖 4 域 12 项，核心成果：

1. **CAP-008 round-trip fuzz 发现 3 个真实 parser bug**（全部已修复）
2. 其余 11 项审计全部通过现有测试基线（无新发现）
3. 新增 `roundtrip_fuzz_test.dart` 作为 Regression Asset（1000 轮随机语料常驻 CI）

## 审计执行明细

### 基线审计（CAP-001/002/003/004/005/006/007 Parser）

| 审计项 | 覆盖文件 | 结果 |
|--------|---------|------|
| CAP-001/002/004/005/007（heading/list/code/formula/inline） | markdown_parser_test + inline_parser_test + serializer_test | ✅ 65 项全绿 |
| CAP-008 round-trip fuzz | **roundtrip_fuzz_test.dart（新增）** | ✅ 1000 轮 + sanity 全绿 |
| CAP-009 boundary | edge_case_test（未配对 `* _ ~ \` [ ] ~` 20 用例）+ resilience | ✅ 34 项全绿 |
| CAP-010/011 editing | undo_redo 3 文件 + transaction 原子性 3 文件 | ✅ 56 项全绿 |
| CAP-012 export | export_integration + svg_to_pdf + word_ooxml | ✅ 64 项全绿 |

## 发现并修复的 3 个真实 bug（ADL Loop 闭环）

> fuzz 测试（CAP-008）第 1 轮即发现 round-trip 结构不一致；逐一最小
> 复现 → 定位根因 → 修复 → 回归。修复全部位于
> `lib/core/parser/markdown_parser.dart`（+17/-3），现有 126 项 parser 相关
> 测试 + fuzz 1000 轮全部通过。

### BUG-1：多行段落合并丢失硬换行（round-trip 不保真）

**现象**：`α β γ   leading\n--- tab...` parse 后 4 个 inline → serialize →
重新 parse 只剩 3 个 inline（换行信息丢失，结构不一致）。

**根因**：parser 合并多行段落到 `pendingParagraph` 时用
`children.addAll(inline)` 直接拼接，`\n`（Markdown hard-break）未保留。

**修复**：合并前若 children 非空，先 `add(TextElement('\n'))`。

### BUG-2：`|` 开头非表格行被静默吞掉（数据丢失）

**现象**：`|pipe| a_b trailing`（不以 `|` 结尾、非合法表格行）在
parse→serialize 后**整行消失**。

**根因**：parser 的 `trimmedLine.startsWith('|')` 分支中 `_parseTableRow`
返回 null 时仍 `continue`，未降级为段落。

**修复**：cells == null 时不再 continue，flushTable 后降级为普通段落解析。

### BUG-3：列表项后紧跟段落时列表被延迟到文档末尾（顺序错误）

**现象**：`line\nbreak\n- item\n中文测试` round-trip 后 `- item` 被移到最后。

**根因**：普通段落分支前未 `flushListItems()`——挂起的列表要等文档结束
才 flush，顺序错乱。

**修复**：段落分支前显式 `flushListItems()`。

## Regression Asset

```text
flutter_app/test/parser/roundtrip_fuzz_test.dart（新增，~240 行）
  - MarkdownCorpusGenerator：固定 seed（20260817）可复现随机语料
  - 1000 轮：不崩溃 + parse→serialize→parse→serialize 收敛不动点
  - AST 结构等价比较器（sealed switch，覆盖全部 DocumentElement 类型）
```

此测试是 Batch 1 发现 3 个 bug 的直接工具，常驻 test 套件防止回归。

## 关键设计决策

1. **fuzz 语料设计**：fragment 池（含中文/公式/边界字符）+ block 池
   （heading/list/code/table/hr/formula），随机拼接；固定 seed 保证可复现。
   两个边界契约明确记录：
   - 不生成空行（EmptyLineElement 是块分隔符，serializer 契约要求调用方过滤）
   - 行内前缀从 fragment 池取（从 block 池取会拿到 ` ``` ` 未闭合 fence）
2. **AST 比较器用显式类型检查**而非双类型 record pattern（本 SDK 版本
   pattern 变量绑定不稳定，AGENTS.md §11.3 教训：保守写法优先）。
3. **fuzz 断言 = 不动点 + 结构等价**：`serialize(parse(serialize(parse(md))))
   == serialize(parse(md))`（二次 round-trip 收敛），比逐字 round-trip
   宽松但能捕获真实保真问题（本次即命中 3 个）。

## 审计结论

```text
Capability Audit Batch 1: 12 项执行完毕
  Parser 7 项    ✅ 基线全绿（fuzz 发现并修复 3 bug）
  Serializer 2 项 ✅（round-trip fuzz 覆盖 + boundary 34 项）
  Editing 2 项   ✅ 56 项全绿（undo-redo / transaction 原子性不变量）
  Export 1 项    ✅ 64 项全绿（markdown/word/pdf 导出集成）

发现 bug: 3（BUG-1 硬换行丢失 / BUG-2 `|` 行吞掉 / BUG-3 列表顺序）
修复:    3（markdown_parser.dart +17/-3，ADL Loop 闭环）
Regression Asset: roundtrip_fuzz_test.dart（1000 轮常驻 CI）
```

## 遗留与下一步

1. **Batch 2（Behavior Audit，2026-08-18 已执行）**：Enter/Backspace/Block
   split-merge 操作语义（split/merge 29 项 + CommandHandler 分派 35 项）+ 
   IME/composing/selection/focus（9 文件 99 项）**全部通过，未发现新 bug**。
2. **Batch 3 候选**：fuzz 覆盖率扩展（嵌套列表、表格 cell 内公式、Mermaid 块、
   CRLF 混合、多 seed 参数化）；或 Experience Audit（真机/Golden/手势）。
3. **CAP-003/006**（table/mermaid）由 fuzz 随机覆盖 + 一致性测试间接覆盖；
   如需专项审计可加入 Batch 3。

---

## 附录：Batch 2 Behavior Audit（2026-08-18）

Batch 1（Capability）聚焦「能不能正确做」；Batch 2（Behavior）聚焦
「用户这么操作后系统行为是否正确」。

### 审计范围与结果

| 行为域 | 覆盖 | 结果 |
|--------|------|------|
| Block split/merge | block_operations_split_transform / split_undo / split_merge_domain | ✅ 29 项全绿 |
| Enter/Backspace 操作语义 | CommandHandler 分派（SplitBlockCommand / MergeWithPreviousCommand / DeleteBlockCommand / InsertTextCommand / PairInsertCommand 等） | ✅ 35 项全绿 |
| IME composing 状态机 | composing_controller / composing_state / ime_mutation_forbidden | ✅ 全绿 |
| Selection/Focus | selection_cursor_domain / selection_sync / coordinator_state_focuson | ✅ 全绿 |
| IME 事件观测 | p0_ime_composing_event / p0_selection_changed_event（ADI 观测面） | ✅ 全绿 |
| IME 事务集成 | ime_transaction_integration | ✅ 全绿 |

**合计：163 项全绿，未发现新 bug**（Batch 1 的 3 个 parser bug 已修复，
Batch 2 未触发新回归）。

### Batch 2 结论

```text
Behavior Audit: 操作语义 + IME/Selection/Focus 共 163 项全绿 ✅
发现 bug: 0（Batch 1 修复的 3 个 parser bug 无回归）
Regression Asset: 无新增（Batch 1 roundtrip_fuzz_test.dart 已常驻）
```
