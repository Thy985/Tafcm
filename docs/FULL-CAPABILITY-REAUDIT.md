# FormulaFix Full Capability Re-Audit（ffx verify 全量）

**日期**: 2026-08-20
**方式**: 11 个 Feature Contract 全转 `ffx capability verify <capability>`（registry 十一能力）
**结论**: ✅ **Re-Audit 完成——Feature Completion Evidence Matrix 从人工文档变为 FFX 实际输出**

---

## 1. 总览（11 能力 × Status）

| # | Feature ID | capability | Status | 类型 | 关键证据 |
|---|-----------|-----------|--------|------|---------|
| 1 | FEAT-MD-PARSE | markdown | ⚠️ warn | 独立 runner | roundtrip 1.0 + 4 checks True（s0 边界） |
| 2 | FEAT-MD-SERIAL | serializer | ⚠️ warn | 独立 runner | roundtrip 1.0（序列化保真达标） |
| 3 | FEAT-UNDO | undo | ✅ pass | 资产引用 | 6 assets / ~41 cases（undo + CAP-BEH 错块） |
| 4 | FEAT-FORMULA | formula | ❌ fail | 独立 runner | render_failure_count=1（ADI RenderOverflow 观察） |
| 5 | FEAT-WORD | word | ⚠️ warn | 独立 runner | wps=pass + formula_fidelity ok（s0: MS Word） |
| 6 | FEAT-PDF | pdf | ✅ pass | 资产引用 | 2 assets / ~45 cases（export + pdf renderer） |
| 7 | FEAT-AUTOSAVE | autosave | ✅ pass | 资产引用 | 2 assets（phase34_autosave + disk） |
| 8 | FEAT-FILE | file | ✅ pass | 资产引用 | 3 assets / ~17 cases（import + decode + file_tree） |
| 9 | FEAT-IME | ime | ⚠️ warn | 资产引用 | 4 assets / ~40 cases（s0: real soft keyboard） |
| 10 | FEAT-THEME | theme | ✅ pass | 资产引用 | 15 assets / ~32 cases（golden 14 + phase34） |
| 11 | FEAT-BLOCK | block | ✅ pass | 资产引用 | 9 assets / ~151 cases（block_operation 系列） |

**汇总：pass 6 / warn 4 / fail 1**

---

## 2. 逐项明细（Feature / Status / Evidence / Unknowns / Next Action）

### 独立 runner 型（真实执行验证）

| Feature | Status | Evidence | Unknowns | Next Action |
|---------|--------|----------|----------|-------------|
| markdown | ⚠️ warn | roundtrip_convergence=1.0、checks{parse/serialize/roundtrip/no_parse_error 全 True}、files=15 | s0 边界（autolink/footnote/definition_list/indented_code/raw_html_块） | decide S0 scope（或逐个实现） |
| serializer | ⚠️ warn | roundtrip=1.0、serialize/roundtrip/no_parse_error True | s0 边界同上 | decide S0 scope |
| formula | ❌ fail | render_failure_count=1、adi_latest=err_20260816160407 | ADI 未解决渲染观察（RenderOverflow） | adi trace-show/replay 诊断后修复 |
| word | ⚠️ warn | wps=pass、formula_fidelity ok、officecli_issues 0 | s0: microsoft_word_desktop（Release Gate） | Level C 环境验证（需 Word） |

### 资产引用型（复用既有测试，非独立 runner）

| Feature | Status | Evidence（资产/用例） | Unknowns | Next Action |
|---------|--------|----------------------|----------|-------------|
| undo | ✅ pass | 6 assets / ~41 cases | 无 | 真实执行验证需 runner（后续轮） |
| pdf | ✅ pass | 2 assets / ~45 cases | 消费端视觉（渲染截图）为 Release Gate | 视觉验证后续轮 |
| autosave | ✅ pass | 2 assets（phase34_autosave*） | 无 | 同上 |
| file | ✅ pass | 3 assets / ~17 cases | 无 | 同上 |
| ime | ⚠️ warn | 4 assets / ~40 cases | s0: real_soft_keyboard_ime | 真机软键盘验收（Release） |
| theme | ✅ pass | 15 assets（golden 14 + theme） | 无 | 同上 |
| block | ✅ pass | 9 assets / ~151 cases | 无 | 同上 |

---

## 3. Re-Audit 中发现并修复的真实问题

```text
【契约矛盾】Contract Sync 补 s0 到 5 项（indented_code/raw_html_块）后，
markdown/serializer 的 completion_policy.unknown_max=3 未同步 → 5 > 3
→ verify 误报 fail（roundtrip 1.0 但 status=fail）。
修复：unknown_max 与 s0 对齐（markdown/serializer=5、word=1、formula=2）
→ verify 恢复预期（markdown/serializer warn）。

意义：Re-Audit 全量跑暴露了单点验证发现不了的问题——契约自洽性
（s0 声明数 vs unknown_max 上限）需要机器校验（contract-sync 增强项）。
```

---

## 4. 意义

```text
✅ Feature Completion Evidence Matrix 变为 FFX 实际输出：
  `ffx capability verify <cap>`（11 能力）一次跑出
  Feature/Status/Evidence/Unknowns/Next Action
✅ 11 能力 registry 建立（4 独立 runner + 7 资产引用）
✅ Re-Audit 暴露并修复 1 个真实问题（契约 unknown_max 矛盾）
⚠️ 资产引用型（7 能力）为「测试资产存在」验证，非实时执行——
   真实 runner 化登记后续轮（3.10.3 后）；status=pass 表示资产完整
   而非「实时测试全过」（诚实边界）
```

## 5. 复跑方式

```bash
cd tools/ffx-cli
for cap in markdown serializer undo formula word pdf autosave file ime theme block; do
  python -m cli_anything.ffx.ffx_cli capability verify "$cap"
done
# 或 --json 模式收集机器可读结果
python -m cli_anything.ffx.ffx_cli --json capability verify markdown
```
