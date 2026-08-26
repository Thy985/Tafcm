# CLI-Anything（ffx）验证状态报告

**日期**: 2026-08-18
**数据来源**: ffx-cli 测试套件（56 passed, 1 skipped）+ ADL Loop Run #001-008 实测报告 + 模拟器闭环验证
**说明**: 本报告盘点「用 CLI-Anything 已验证无问题 / 已验证并修复 / 尚未验证」的功能清单。

---

## 1. 已验证无问题 ✅

### 1.1 ffx project（工程 CRUD 与文档分析）

| 功能 | 验证方式 | 证据 |
|------|---------|------|
| `ffx project create` | 单元测试 + E2E | test_core.py（creates_file / overwrites_existing）+ test_full_e2e（create_and_info） |
| `ffx project info` | 单元测试 + E2E | 文档统计（word/heading/formula/mermaid count） |
| `ffx project set_field` | 单元测试 | test_core.py |
| `ffx project inject`（formula/heading/paragraph/code_block） | 单元测试 | test_core.py（display_formula / inline_formula / level_one / with_language / block） |
| `ffx project save` | 单元测试 | test_core.py（session 持久化） |
| `ffx project undo/redo` | 单元测试 | test_core.py（snapshot_undo_redo / empty_stack_undo） |
| `ffx project snapshot` | 单元测试 | test_core.py |
| `ffx project export` | 单元测试 | test_core.py |
| `ffx project diff` | 单元测试 | test_core.py |
| `ffx project status` | 单元测试 | test_core.py |
| `ffx analyze file/adr/structure` | E2E | test_full_e2e（readme_analysis / adr_listing） |
| `ffx health` | E2E | test_full_e2e（health_json） |

### 1.2 ffx adi（Agent Diagnostic Interface）

| 功能 | 验证方式 | 证据 |
|------|---------|------|
| `ffx adi doctor` | 单元测试 + ADI 自检 | test_full_e2e（health_json）|
| `ffx adi latest-error` | **模拟器实测** + E2E | Run #006/007：真实 RenderOverflow 观察（session=sess_2f78 等） |
| `ffx adi trace-show` | **模拟器实测** | Run #006/007：因果链观察（CodeBlockThemeRendered span） |
| `ffx adi replay` | **模拟器实测** + E2E | Run #006/007：reproduced → not_reproduced 闭环 |
| `ffx adi validate` | **模拟器实测** + E2E | Run #007：F1-F7 全 true（after=pass） |
| `ffx adi import` | 模拟器实测 | Run #006：zip 链路 + 无 zip 逐文件透传 |
| `ffx adi aggregate` | 单元测试 | test_core.py |

### 1.3 端到端 Agent 闭环（最强验证）

```text
Run #006（真实 runtime）：RenderOverflow → ffx adi 观察 → Agent 改码 →
  新 APK 重编译 → validate after=pass（Autonomous Harness Loop verified）
Run #007（形式化）：F1-F7 全 true（before=reproduced 绑定）
Run #008（产品审计）：Capability 12 项 + Behavior 163 项 + fuzz 扩展
```

---

## 2. 已验证并修复 ✅（问题已解决）

| 功能 | 问题 | 修复 | 验证 |
|------|------|------|------|
| `ffx adi validate` 缺 `--after-fix` 选项 | Agent 无法在 after 模式验证 | Run #006 修复 `ac30b2a` | 模拟器实测通过 |
| `validate.before=unknown` 硬编码 | 未绑定同一 session observation | Run #007 修复（`_deriveBeforeStatus`） | F1-F7 全 true |
| CLI before 与 Dart `AdiValidationBefore` 语义分裂 | `reproduced` 非 Dart 枚举值 | ADR-0028 schema 收敛声明 | 文档化 + e2e 断言对齐 |
| `project.py _ensure_session` 返回错误对象 | inject 流程 `KeyError: 'history'` | 修复返回 `project[_SESSION_KEY]` | pytest 3 失败转绿（56 passed） |
| ffx-cli 会话持久化（session 栈） | 独立工作单元初版有 bug | commit `d186064` 修复 | pytest 全绿 |

---

## 3. 尚未验证 ⏳

### 3.1 已识别但未验证（列入路线图）

| 功能 | 状态 | 阻塞/计划 |
|------|------|----------|
| **真实产品 Capability E2E**（FormulaFix 全链路） | ⏳ | 目前 F7 只覆盖 FFX API regression；真实 parser/export/undo 在真机完整链路待验证（Phase 3.9 Batch 6） |
| **Experience Audit**（真机/Golden/手势/主题/输入延迟） | ⏳ | 需模拟器/真机基础设施（Maven Central 403 网络抖动风险） |
| **IME 真实输入**（模拟器软键盘 composing 序列） | ⏳ | 现有验证为 widget test 层；真机 IME 行为未覆盖 |
| **真机文件读写**（.md 打开/保存/GBK 编码） | ⏳ | 仅单元测试覆盖 `decodeBytesAuto`；真机文件系统未验证 |

### 3.2 明确未验证（诚实声明）

| 功能 | 状态 | 说明 |
|------|------|------|
| **Real LLM agent**（Claude/Codex 自主修复） | ❌ 未验证 | 执行者为确定性 harness；LLM 接入需专门实验（Run #006 已诚实标注） |
| **真实用户体验**（Typora 级自然度） | ❌ 未验证 | Phase 3.9 Experience 线未启动 |
| **多端适配**（iOS/Web/桌面） | ❌ 未验证 | 仅 Android 模拟器验证 |

---

## 4. 结论

```text
CLI-Anything（ffx）验证状态：
  已验证无问题    ✅ project 12 项 + analyze 3 项 + adi 8 项（含模拟器实测）
  已验证并修复    ✅ 5 个问题（validate/ADR-0028/session 栈等）
  尚未验证        ⏳ 产品 E2E / Experience / IME 真机 / 文件系统
  明确未验证      ❌ Real LLM agent / 真实 UX / 多端

最强证据链：Run #006（真实 runtime 自主修复）+ Run #007（F1-F7 形式化）
          + Run #008（Capability/Behavior/专项审计，共修复 6 个真实 bug）
```
