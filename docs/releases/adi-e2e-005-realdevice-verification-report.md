# E2E-ADI-005 真机闭环验证报告（Real-Device Full Maintenance Loop）

> **状态**：🟡 部分完成（v0.1 标准 ✅ 全过；v0.2 标准受 AS-RG.1 已知缺口阻塞，安全网行为验证 ✅）
> **执行日期**：2026-08-16
> **设备**：Xiaomi 24117RK2CC（Android 16 / API 36），adb 序列号 `63cfc8cf`
> **关联**：ADR-0024 §9.4 E2E-ADI-005 · ROADMAP 3.8.5 · [进度+验收报告](./adi-phase38-progress-realdevice-acceptance.md)

---

## 0. 结论（TL;DR）

**本报告完成 ADR-0024 §9.4 E2E-ADI-005 真机闭环验证的首次真实执行**（非合成 fixture、非离线导入），在真实设备上走通了"真机故障注入 → 诊断 zip 采集 → `adi import` → `adi latest-error` 分类 → `adi trace show` 6 层因果链路"的完整证据链。v0.1 标准 5 步全部达成。

**v0.2 标准（`adi replay` → `reproduced` + `adi validate --after-fix` → `pass`）未能达成**：`adi replay` 如实返回 `inconclusive`——这**不是**新缺陷，而是 ADR-0024 §9.4 明示的已知证据缺口（AS-RG.1：ExportPipeline 真机采集时未同步录制 replay 序列，`import_zip.dart` 有意不合成 replay.json 以防假 pass）。本次验证同时确认了该安全网行为正确：`validate --after-fix` 在 replay 证据缺失时返回 `after=inconclusive` + invariants `allPassed`，**绝不误判 pass**（与 ADR "Respect invariant report" 契约一致）。

**附带环境治理**：本次执行修复了本地工具链 2 个环境级障碍（gradle wrapper 悬空符号链接 + Java 直连网络超时），详见 §4。

---

## 1. v0.1 真机测试标准（证明 "Agent 能拿到可靠且因果完整的证据"）—— ✅ 全部通过

| 步 | 操作 | 验证标准 | 实测结果 | 判定 |
|----|------|---------|---------|------|
| 1 | 真机 APK 部署 + 故障注入（`FaultInjection.enabled` 使真机 CodeBlock 在真实渲染引擎上溢出） | 真实触发 RenderOverflow | `flutter drive` 真机执行 `integration_test/adi_fault_injection_test.dart` → **All tests passed**，日志确认 `RenderFlex overflowed by 99860 pixels` | ✅ |
| 2 | `adb` 导出诊断 zip | zip 非空 + 含 metadata/snapshot/trace/invariant_report | `formula_fix_debug_20260816_160407.zip`（1992B，**5 件套**：metadata / trace / snapshot / invariant_report / README） | ✅ |
| 3 | `adi import <zip> --json` | `status=ok` + 生成 `.adi/` | `{"status":"ok","imported_from":"...zip","target":"...tools/adi/.adi"}` | ✅ |
| 4 | `adi latest-error --json` | `error_type=RenderOverflow` + `snapshot_available=true` + `session_id`/`trace_id` | `error_type:"RenderOverflow"`（raw `GlobalError` 经 classify 归一）、`snapshot_available:true`、`session_id:sess_2239`、`trace_id:trc_5b98ca4687546592` | ✅ |
| 5 | `adi trace show <trace_id> --json` | chain 6 层完整（interaction → command → transaction → render → render → error），**非手工构造** | 6 层 span 链 + `causality{rootSpanId, failureSpanId, reachable:true, orphanSpanIds:[], valid:true}` | ✅ |

**v0.1 证据链（真机采集，非 fixture）**：

```json
{"sessionId":"sess_2239","chain":[
  {"layer":"interaction","description":"UserInput","parent":null},
  {"layer":"command","description":"InsertTextCommand","parent":"interaction_0"},
  {"layer":"transaction","description":"Transaction","parent":"command_0"},
  {"layer":"render","description":"CodeBlockThemeRendered","parent":"transaction_0"},
  {"layer":"render","description":"CodeBlockLanguageChipRendered","parent":"render_0"},
  {"layer":"error","description":"RenderParagraph overflow","parent":"render_1"}],
 "causality":{"rootSpanId":"interaction_0","failureSpanId":"error_0","reachable":true,"orphanSpanIds":[],"valid":true}}
```

> 与 E2E-004（离线 fixture 导入）的本质区别：本报告链路全部来自真机 `ExportPipeline` 运行时采集，非手工构造 JSON。

---

## 2. v0.2 真机测试标准（证明 "Agent 能基于 ADI 完成维护闭环"）—— 🟡 部分达成

| 步 | 操作 | 验证标准 | 实测结果 | 判定 |
|----|------|---------|---------|------|
| 1 | 制造 Bug（真实代码 fault） | 真实故障注入 | 本次用 `FaultInjection.enabled` 确定性注入（真实渲染引擎溢出）；**尚未**做"CodeBlockRenderer 删 SingleChildScrollView"式真实代码 fault | 🟡 等价替代 |
| 2 | 真机输入超长字符串 | 真实触发 overflow | ✅ 真机触发 `RenderFlex overflowed by 99860 pixels` | ✅ |
| 3 | `adi latest-error` | Agent 拿到 `sess_xxx` | ✅ `sess_2239`（无需人工解释） | ✅ |
| 4 | `adi replay sess_xxx` | `status=reproduced`（**非 inconclusive**） | ❌ `{"status":"inconclusive","message":"Replay data exists but no replay result cached. Run replay from App."}` —— **AS-RG.1 已知缺口**（见 §3） | ❌ 阻塞 |
| 5 | Agent 真实代码修复（真实 commit） | 真实修复 | ⏳ 未执行（replay 未 reproduced，修复闭环无法闭环） | ⏳ |
| 6 | `adi validate --after-fix sess_xxx` | `after=pass` | 🟡 安全网行为验证 ✅：`{"before":"unknown","after":"inconclusive","replay":{"status":"no_data"},"invariants":{"violated":[],"checked":[6 项], "allPassed":true}}` —— **正确 resolve 为 inconclusive，未误判 pass** | 🟡 |

**v0.2 结论**：`adi replay` → `reproduced` 的前置（真机采集同步录制 replay 序列）当前缺失，属 ADR-0024 §9.4 明示的 005 必须解决的证据缺口（AS-RG.1）。本次执行确认 CLI/存储/校验链路本身工作正常，且**安全网契约（缺失证据绝不假 pass）被真机数据验证**。

---

## 3. AS-RG.1 缺口确认（v0.2 阻塞项）

**症状**：`adi replay sess_2239` → `inconclusive`："Replay data exists but no replay result cached. Run replay from App."

**根因**（代码实证）：
- `tools/adi/import_zip.dart:83-85`：`replay.json is intentionally NOT synthesized. A real-device export carries no replay evidence, so adi validate must resolve to inconclusive rather than a false pass.` —— CLI 侧**有意不合成** replay 结果（防假 pass 安全网）。
- `flutter_app/lib/core/observability/export_pipeline.dart`：导出 zip 仅含 metadata/trace/snapshot/invariant_report/README，**未录制 replay 序列**（无 `commands.jsonl` / replay 结果）。
- `adi_replay_adapter.dart`：ReplayEngine 重放结果需在 App 端执行并缓存（`executorFactory` 依赖 presentation 层注入）。

**修复方向**（与 [进度+验收报告 §10 建议 4](./adi-phase38-progress-realdevice-acceptance.md) 一致）：
1. `ExportPipeline` 增录 replay 序列（`commands.jsonl`，AS-RG.1）；
2. 真机采集时由 App 端运行 `CommandReplayer` 并缓存 replay.json 到 `.adi/`；
3. `adi import` 透传 replay 证据（保留"证据缺失 → inconclusive"安全网）。

---

## 4. 环境治理记录（本次执行修复的 2 个障碍）

> 背景：进度报告 §9 记载"本地 Dart/Flutter 工具链存在系统性环境故障"。本次真机执行实际命中并修复了其中 2 项：

| # | 障碍 | 现象 | 根因 | 修复 |
|---|------|------|------|------|
| 1 | **gradle wrapper 悬空符号链接** | `gradle-8.12.1-all.zip.lck` 打不开、wrapper 反复下载发行版 | `C:\Users\lenovo\.gradle` 是指向 `D:\DevCaches\gradle` 的符号链接，目标目录被清理 | 重建 `D:/DevCaches/gradle` 目录 + 手动下载/解压 gradle-8.12.1-all 并打 `.ok` 标记 |
| 2 | **Java 直连网络超时** | wrapper 下载 `Connection timed out`；gradle 解析依赖卡死 | 系统代理 `127.0.0.1:7897` 只对 curl 生效，Java HttpURLConnection 不读代理环境变量 | `~/.gradle/gradle.properties` 增加 `systemProp.http(s).proxyHost/Port` |

**执行方式**（供复现）：`flutter drive --driver=test_driver/integration_test.dart --target=integration_test/adi_fault_injection_test.dart --keep-app-running -d <device>`，通过 Windows 计划任务脱离 bash 进程树运行（避免命令行工具超时杀进程）；测试结束保留应用，`adb exec-out run-as` 导出 zip。

---

## 5. 遗留项（需 Human Owner / 后续排期）

| 优先级 | 项 | 状态 |
|--------|----|------|
| **P0** | **AS-RG.1 补录 replay 序列**（`ExportPipeline` 增录 `commands.jsonl` + App 端缓存 replay.json）—— v0.2 `reproduced` 的前置 | ⏳ 待排期 |
| **P0** | v0.2 真实代码 fault（CodeBlockRenderer 删 SingleChildScrollView）→ replay reproduced → 真实修复 → validate pass 完整闭环 | ⏳ 依赖 AS-RG.1 |
| **P1** | CI 接入 `integration_test` job（当前 CI 仅 `flutter build apk`，不跑 integration_test） | ⏳ 待补 |
| **P1** | ADI Fault Scenario Suite（scenario-001~004 + 确定性流水线） | ⏳ 待建 |
| **P1** | 真机 zip 在测试结束即被卸载删除的运维问题（本次用 `--keep-app-running` + `run-as` 导出解决，建议正式化到工具文档） | 🟡 已绕过，待固化 |

---

## 6. 验收判定

- [x] **v0.1 真机测试标准：全部 5 步 PASS**（真机采集 zip → import → latest-error 分类 → trace show 6 层因果链，非手工 fixture）
- [x] **安全网契约：真机数据验证**（replay 证据缺失 → `validate` 正确返回 `inconclusive`，invariants 6 项 allPassed，未误判 pass）
- [ ] **v0.2 真机测试标准：`replay → reproduced` + `validate --after-fix → pass`** —— 受 AS-RG.1 阻塞（ADR 已知缺口），前置补录后重跑

**结论**：E2E-ADI-005 首次真机执行完成"证据采集 → Agent 消费"链路验证（v0.1 全过）；v0.2 维护闭环需先落地 AS-RG.1（replay 证据录制），再执行"真实代码 fault → replay reproduced → 真实修复 → validate pass"完整闭环。

---

*本报告由 AI 协作开发者于 2026-08-16 真机执行后产出，证据为实测输出（设备 24117RK2CC / sess_2239 / trc_5b98ca4687546592 / formula_fix_debug_20260816_160407.zip）。*
