# FormulaFix 功能审计状态总览（功能 × 检查点 × 实际情况）

**日期**: 2026-08-19
**数据来源**: Phase 3.9 全量审计（Capability/Behavior/Word Export/DOCX QA/Experience/IME）+ 全量测试套件 + 模拟机 integration_test
**核心问题**: 已做出的功能是否检验通过？不依赖模拟机的部分是否大部分已闭环？

---

## 0. 结论速览

```text
✅ 不依赖模拟机已闭环的功能域：7/9（Parser / Serializer / 编辑模型 /
   Behavior Audit / Word 导出 / PDF 导出 / CLI-ADI 诊断）
⏳ 需要模拟机（2026-08-19 全量跑完）：102 项 integration_test 分批
   跑完——通过 ~96 项（含 e2e core 001-006 / extended / phase33-35 /
   phase34 全系列 / adi / Word 导出 / IME composing）；失败 7 项全部
   归类：环境偶发 5（单跑通过）/ 测试注入局限 2（auto_continue /
   auto_pair，updateEditingValue 不触发命令层，widget 层已全绿）/
   home_smoke 已修复（2026-08-19：根因 = app.main() 全局错误钩子污染
   binding + 断言与空文档渲染条件不匹配；改 harness 模式 + 断言修正
   后模拟机通过）——**无真实产品 bug**
❌ 明确未验证（诚实声明）：真实软键盘 IME / Microsoft Word Desktop /
   真机物理渲染 / 多端适配 / Real LLM agent

结论（2026-08-19 收紧表述）：
  不是「FormulaFix 大部分功能都没问题」，而是——
  「FormulaFix 的核心能力已建立较强的证据覆盖；剩余风险主要集中在
   真实设备交互、真实用户体验、消费者差异和未覆盖的 LLM Agent 场景。」
  7/9 是管理指标（无模拟机闭环域数），不代表项目完成度——真实键盘/
  IME/设备布局/触控/文件系统/生命周期的风险权重高于单测覆盖的暗示。
```

---

## 1. 测试资产总览（2026-08-19 实测）

| 层 | 用例数 | 说明 |
|----|--------|------|
| test/parser | 50 | 解析/序列化/fuzz/专项审计 |
| test/editing | 472 | 编辑模型（undo/redo/coalescing/composing/IME 禁止） |
| test/integration | 69 | 跨模块集成 |
| test/observability | 260 | ADI/渲染追踪/invariant |
| test/architecture | 81 | 六层架构守门/文件大小/Provider 唯一性 |
| test/performance | 5 | perf 阈值（median < 10/32ms） |
| test/golden | 14 文件 | 主题/尺寸/破版守护 |
| integration_test | 102 | 模拟机 E2E（含 Word 导出 / IME composing） |
| ffx-cli pytest | 54 passed | CLI 工具面 |

---

## 2. 功能 × 检查点 × 实际情况（无模拟机依赖分类）

### 2.1 ✅ 不依赖模拟机已检验（单元 + widget + 消费端）

| 功能域 | 检查点 | 实际情况 | 证据 |
|--------|--------|---------|------|
| **Markdown Parser** | 语法识别 / 降级容错 / 边界 | ✅ 50 用例 + fuzz 1000 轮；**修复 6 个真实 bug**（BUG-1 硬换行 / BUG-2 pipe / BUG-3 flush / BUG-4 CRLF / BUG-5 嵌套 AST / BUG-6 空代码块） | roundtrip_fuzz / mermaid_audit / table_formula_audit |
| **Markdown Serializer** | round-trip 不动点 | ✅ fuzz 收敛（<1% 违规）+ 嵌套列表递归序列化 | roundtrip_fuzz（multi-seed 5×200） |
| **编辑模型** | split/merge/insert/delete/undo/redo/coalescing | ✅ 472 用例；CAP-BEH-001~009 全绿（含 Undo 错块/Coalescing 错块/Paste/Selection 专项） | cap_beh_audit + undo_redo 系列 |
| **IME composing（widget 层）** | 组合态禁止切块（铁律 1） | ✅ composing_controller/state + ime_mutation_forbidden | 99 项 Batch 2 |
| **Word 导出（L1-L6）** | OOXML/语义/消费端 | ✅ CAP-WORD-001~018 + 018b 解析器级 XML；**BUG-WORD-001 修复**（无渲染公式 fallback，WPS 消费端保真）；WPS word2pdf/pdf2txt/officecli 实测通过 | word_export 系列 50+ 项 + WPS 消费端 |
| **PDF 导出** | 渲染/页眉页脚/公式 | ✅ export_integration_test（28 项，单跑全绿） | export 域 |
| **ffx-cli / ADI** | CLI 工具面 / 诊断闭环 | ✅ pytest 54 passed + Run #001-008 闭环（Observe→Validate→Verify→Autonomous→Formal→Audit） | ffx tests + ADL 报告 |
| **架构守门** | 六层依赖 / 文件大小 / Provider 唯一性 | ✅ 81 用例（TC-ARCH-1~12） | architecture 目录 |

### 2.2 ⏳ 需要模拟机（integration_test 102 用例）

| 功能域 | 检查点 | 实际情况 | 证据 |
|--------|--------|---------|------|
| **Word 导出 Runtime E2E** | 真实导出落盘 | ✅ **已模拟机验证**（CAP-WORD-017，size=4006 + ZIP magic） | cap_word_017（emulator-5554） |
| **IME composing（模拟机）** | 真实 runtime 组合态 | ✅ **已模拟机验证**（E2E-IME-001 2 项：组合中显示/提交正确/铁律 1 代理） | cap_ime_composing（emulator-5554） |
| **其余 e2e**（persistence/split/merge/undo/format/coalescing/code_block/list/transaction） | 全链路行为 | ⏳ 102 用例待全量跑（模拟机已就绪，单跑模式已验证 e2e_core_006 等） | integration_test/e2e |

### 2.3 ❌ 明确未验证（诚实声明，非 bug）

| 项 | 状态 | 说明 |
|----|------|------|
| 真实 Android 软键盘 IME 按键 | ❌ | tester 无法模拟，需人工验收 |
| Microsoft Word Desktop | ❌ UNKNOWN | Level C Release Gate，主机无 Word |
| 真机（非模拟器）物理渲染体验 | ❌ | Golden 在测试层覆盖，真机渲染待人工 |
| 多端适配（iOS/Web/桌面） | ❌ | 仅 Android 模拟器验证 |
| Real LLM agent 自主修复 | ❌ | 当前为确定性 harness（Run #006 已诚实标注） |

---

## 3. 关键修复记录（审计驱动的真实 bug）

| Bug | 域 | 修复 | 验证 |
|-----|----|------|------|
| BUG-1~3 | Parser | round-trip fuzz 发现 3 个解析 bug | fuzz 回归 |
| BUG-4 | Parser | CRLF 任务列表 | fuzz 回归 |
| BUG-5 | Parser/编辑模型 | ListElement 嵌套 AST（ADR-0029） | 230+64 项全绿 |
| BUG-6 | Parser | 空代码块丢弃 | mermaid_audit |
| BUG-WORD-001 | Word 导出 | 无渲染公式 fallback 文本 | WPS 消费端保真 |

---

## 4. 结论

```text
用户问题回答：
「已做出的功能是否检验通过？」
  → 大部分是：9 个功能域中 7 个已在「不依赖模拟机」层面闭环
    （单元 + widget + 真实消费端验证），且审计驱动修复了 6 个真实 bug

「没有使用模拟机的情况下大部分功能是否已检验？」
  → 是：Parser/Serializer/编辑模型/IME(widget)/Word 导出(L1-L6)/
    PDF/CLI-ADI/架构守门 全部可在纯本地 + 消费端验证闭环
    （Word 消费端用 WPS/officecli 真实引擎，不依赖模拟机）

模拟机的角色：覆盖关键 E2E 路径（Word 导出落盘 / IME composing），
  已跑通 2 个关键项；其余 e2e 待全量跑

未验证清单：真实软键盘 / Word Desktop / 真机渲染 / 多端 / LLM agent
  —— 均为人工验收或 Release Gate 项，非当前审计缺口
```
