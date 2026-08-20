# Contract Sync 最小版（ROADMAP 3.10.2，D1/R12 闭环）

**日期**: 2026-08-20
**状态**: ✅ 实现 + 验证完成（Matrix ↔ contracts 无漂移，机器强制生效）
**命令**: `ffx analyze contract-sync`
**背景**: Feature Capability Matrix（L2，S0-S5）↔ contracts/*.json 一致性此前靠
人工对照（Run #002 曾人工确认 autolink/footnote/definition_list 一致）——本轮
机器化（Review R12 待办 + ROADMAP 3.10.2 Dogfood 前最小版落地）。

---

## 1. 实现

### 1.1 校验模块 `tools/ffx-cli/cli_anything/ffx/core/contract_sync.py`（新建）

```text
parse_matrix_scores()   从 Matrix 表格行提取 {能力名(归一化): S级}
  - 行格式：| 类别 | 能力名 | ... | **Sx** | ... |
  - _norm：小写 + 空格/连字符 → 下划线（Matrix 名 ↔ contract s0 名对齐）
matrix_s0() / matrix_supported()   S0 集合 / S≥4 集合
check_contract_sync()   三条规则校验 → {status, errors, warnings, contracts}
render_sync_report()    人类可读报告
```

### 1.2 三条规则（机器强制）

| 规则 | 语义 | 违反 → |
|------|------|--------|
| 规则 1（反向） | Matrix 标 S0 的能力 ⊆ contract.s0_unsupported（漏声明） | ERROR |
| 规则 2（正向） | Matrix 标 S≥4 的能力 ∉ contract.s0_unsupported（误声明） | ERROR |
| 规则 3（闭合） | contract.s0_unsupported 需有 Matrix 依据（额外能力） | WARN |

### 1.3 ffx 命令

```text
ffx analyze contract-sync         # 人类可读报告
ffx --json analyze contract-sync  # JSON 报告
exit: 0=一致（可含 WARN）/ 1=漂移 ERROR
```

## 2. 验证结果

### 2.1 首跑发现真实漂移（机器强制生效）

```text
第一次运行（命名归一化前）：
  status=error
  ✗ [markdown] Matrix S0 'indented_code' 未在 contract.s0_unsupported 声明
  ✗ [markdown] Matrix S0 'raw_html_块' 未在 contract.s0_unsupported 声明

根因：Matrix 标了 5 个 S0（autolink/footnote/definition_list/indented_code/
raw_html_块），但 contract 只声明 3 个——indented_code（无实现）与
raw_html_块（无 HTML 块元素）漏声明 = 真实漂移
```

### 2.2 修复（contract 向 Matrix 对齐）

```text
contracts/markdown_parser.json + serializer.json 的 s0_unsupported
  补 'indented_code'、'raw_html_块'（与 Matrix S0 5 项对齐）
```

### 2.3 最终验证（无漂移）

```text
ffx analyze contract-sync
  contract sync: status=ok
  matrix S0       : ['indented_code', 'footnote', 'definition_list', 'raw_html_块', 'autolink']
  contracts       : ['markdown', 'serializer']
  无漂移（Matrix ↔ contracts 一致）
  exit=0
```

## 3. 意义

```text
✅ Matrix ↔ contracts 一致性从「人工对照」→「机器强制」：
  - 未来 Matrix 增删 S0 能力 / contract 增删 s0_unsupported 时，
    ffx analyze contract-sync 立即暴露漂移（exit=1）
  - 「Matrix says S4 ≠ Contract says S3」类问题可被机器发现
    （ROADMAP 3.10.2 核心目标）
✅ 修复了 1 个真实漂移（indented_code / raw_html_块 漏声明）
⚠️ serializer 非独立能力边界：contract 有 serializer.json 但 Matrix
  将其视为 Fidelity 子维度（Run #002 已确认）——规则 3 对额外能力
  给 WARN（非 ERROR），本轮无 WARN 触发
```

## 4. 资产

```text
tools/ffx-cli/cli_anything/ffx/core/contract_sync.py（新建，~180 行）
tools/ffx-cli/cli_anything/ffx/ffx_cli.py（+28 行：analyze contract-sync 命令）
contracts/markdown_parser.json（s0_unsupported 补 2 项）
contracts/serializer.json（s0_unsupported 补 2 项）

复跑：cd tools/ffx-cli && python -m cli_anything.ffx.ffx_cli analyze contract-sync
```
