# ADL Loop Run #006 — Autonomous Agent Repair E2E (Plan)

**日期**: 2026-08-17
**前置**: Run #001-005 已验证 ADI 诊断链 / 持久化 / 闭环编排 / fault-injection 闭环 / 真实源码修复可验证性
**状态**: 方案设计
**下一步**: 实现 Agent harness + capability 测试 + 全链路验证

---

## 1. 目标与定位

**Run #006 回答：「Agent 能否在无人工干预下完成完整自修复闭环？」**

| | Run #005 | Run #006 |
|--|---------|---------|
| 核心目标 | 真实源码修复**可验证性**（Verifiability） | Agent **自主执行**修复（Autonomy） |
| 修复动作 | `run005_apply_fix.dart` 确定性脚本 | **Agent**（ffx CLI 驱动）推理后执行 |
| 证据来源 | 测试内直接断言 | Agent 仅通过 ADI 观察，不预知 bug 位置 |
| 成功标准 | 6 predicates | 6 predicates + **3 个无人工介入条件** |

Run #005 证明「生产源码修改 + 新进程重编译 + 故障不再复现」技术链成立。
Run #006 把该技术链的**执行者**从确定性脚本换成 Agent，验证三个无人工介入条件。

---

## 2. 三个无人工介入条件（核心验证对象）

### C1: Agent 自己发现问题
- ❌ 不能提前告诉 Agent「bug 在 code_block.dart」
- ✅ Agent 只能看到 `ffx ... failed`，然后自己执行：
  ```bash
  ffx --json adi latest-error
  ffx --json adi trace-show <trace_id>
  ffx --json adi replay <session_id>
  ```
- **断言**：Agent harness 的输入不含 bug 位置；evidence 全部来自 ADI 观察。

### C2: Agent 自己决定修改
- ❌ 不能调用 `run005_apply_fix.dart apply`（预置脚本）
- ✅ Agent 从证据推理出修改内容，产生**真实 git diff**：
  ```bash
  git diff flutter_app/lib/presentation/blocks/code/code_block.dart
  ```
- **断言**：diff 是 Agent 推理后的结果（非脚本调用）；生产源码确实被修改。

### C3: Agent 自己判断修复成功
- ❌ 不能自述「我改好了」
- ✅ Agent 依据 ADI 判定：
  ```bash
  ffx --json adi validate --after-fix <session_id>
  # before=reproduced → after=not_reproduced
  # invariants.allPassed=true
  # capability E2E PASS
  ```
- **断言**：Agent 的 success 判定必须与 ADI validate 输出一致。

---

## 3. 架构：Agent harness（ffx CLI 全链路）

```
FFX capability            # 失败能力（before 测试触发 RenderOverflow）
      ↓
ffx adi latest-error      # C1: 获取 Observation（session/trace/error_type）
      ↓
ffx adi trace-show        # C1: 因果链
      ↓
ffx adi replay            # C1: 确认 reproduced
      ↓
Agent reasoning           # C2: 从证据推理（message/error_type 关键字 → 定位源码）
      ↓
Agent edits code          # C2: 真实 git diff
      ↓
fresh build + after capability   # 新进程重编译修复后源码
      ↓
ffx adi validate --after-fix     # C3: before=reproduced → after=not_reproduced
      ↓
ffx project create/info          # capability E2E 回归
      ↓
证据 JSON（3 条件 + 6 predicates）
```

### 关键设计决策

1. **Agent harness = Python 脚本**（`tools/adi/run006_agent.py`）：
   - 复用 `tools/ffx-cli` 的 adi_wrapper（定位 adi.dart + cwd=tools/adi）
   - 输入仅 capability 测试文件路径，**不含 bug 位置**
   - 每一步记录证据，最终输出结构化 JSON

2. **证据存储契约**：ffx adi 读取 `tools/adi/.adi`（adi_wrapper 固定 cwd=tools/adi → `_adiRoot` = tools/adi/.adi）。因此 Run #006 的 capability 测试必须把 evidence 写入**真实 `.adi`**（通过 `--dart-define=ADL_ADI_ROOT` 覆盖 AdiStorage 路径），而非 Run #005 的 tempDir。

3. **capability 测试**（`fault_injection_run006_test.dart`）：
   - before 模式：FaultInjection.enabled=true → 触发 RenderOverflow → 写入真实 .adi → 断言 captured
   - 由 Agent harness 驱动（`--dart-define=ADL_RUN006_CAPABILITY=true`），CI 默认跳过

4. **驱动脚本**（`tools/adi/run006_proof.sh`）：backup → run agent → restore，与 run005 同构。

---

## 4. 与 Run #005 的复用关系

| 组件 | Run #005 | Run #006 |
|------|---------|---------|
| before/after 双进程验证 | ✅ 核心机制 | ✅ 复用（capability 测试） |
| 修复执行者 | `run005_apply_fix.dart` | Agent harness（推理） |
| 证据写入 | tempDir（测试隔离） | 真实 `tools/adi/.adi`（ffx 可读） |
| 谓词 P1-P6 | ✅ | ✅ 复用 + 3 条件 |

**边界**：Run #006 不新增验证机制，只替换「执行者」角色并增加 C1-C3 条件断言。

---

## 5. 成功标准

```json
{
  "run": "006",
  "status": "autonomous_agent_repair_proven",
  "conditions": {
    "C1_agent_discovers": true,
    "C2_agent_decides_patch": true,
    "C3_agent_judges_success": true
  },
  "predicates": {
    "P1_before_reproduced": true,
    "P2_patch_authenticity": true,
    "P3_fresh_runtime_fixed": true,
    "P4_invariants_pass": true,
    "P5_replay_not_reproduced": true,
    "P6_capability_e2e_pass": true
  }
}

PASS = C1 ∧ C2 ∧ C3 ∧ P1 ∧ P2 ∧ P3 ∧ P4 ∧ P5 ∧ P6
```

---

## 6. 测试计划

1. **Agent harness 单测**（python）：mock adi_wrapper 返回固定 evidence → 断言推理定位 + diff 生成
2. **capability 测试**（flutter）：before 模式捕获 RenderOverflow 写入真实 .adi
3. **端到端**：`bash tools/adi/run006_proof.sh` 全链路 → 输出证据 JSON
4. **静态检查**：flutter analyze 0 warning；TC-ARCH-7 行数 < 400

---

## 7. 风险与边界

- **推理的确定性**：Agent 推理基于 error_type/message 关键字（RenderOverflow + CodeBlock），
  对本次 bug 是确定的；真实环境需 Agent（LLM）介入，本 harness 证明**协议链路**而非 LLM 智能。
- **CI 安全**：capability 测试由 dart-define 门控，默认跳过；驱动脚本写真实 .adi 前先备份。
- **与 Run #007+ 的关系**：本 Run 证明「Agent 可自主完成闭环」的协议层，LLM 推理质量是产品层问题。

---

## 8. 模拟器实测方案（2026-08-17 增补）

widget test 双进程已在主机验证闭环；模拟器实测把 capability 换成
**integration_test**（真实 Flutter runtime），证据经 zip 同步回主机 .adi：

```text
Phase 0: 备份 code_block.dart
Phase 1: flutter test integration_test/run006_capability_test.dart -d emulator-5554
         --dart-define=ADL_RUN006_BEFORE=true
         → 真实 runtime 渲染 CodeBlock（FaultInjection gate 存在）→ 真实 RenderOverflow
         → FlutterError.onError 捕获 → exportDiagnosticZip 导出设备端 zip
Phase 2: adb pull <device zip> → ffx adi import（或 dart run tools/adi/adi.dart import）
         → 证据合并进 tools/adi/.adi（observations/traces/sessions/replay）
Phase 3: Agent 闭环（run006_agent.py --simulator，跳过 widget capability）：
         ffx adi latest-error → trace-show → replay → 推理 → 改码（真实 git diff）
Phase 4: flutter test integration_test/run006_capability_test.dart -d emulator-5554
         --dart-define=ADL_RUN006_AFTER=true --dart-define=ADL_SESSION_ID=<session>
         → 新 APK 重编译修复后源码 → 无 overflow → 导出 zip（replay=not_reproduced）
         → adb pull → ffx adi import（覆盖同一 session replay）
Phase 5: ffx adi validate --after-fix <session> → after=pass
Phase 6: 还原 code_block.dart
```

### 关键设计决策

1. **capability 复用 FaultInjection gate**（SizedBox(height:100000)，与 widget 版同一 bug）：
   Agent 的 `reason_and_patch` 推理逻辑**零改动**——运行环境从 widget test
   换成模拟器真实 runtime，但 bug 本体与修复动作一致。
2. **证据同步 = zip 链路**（复用 AS-RG.1）：模拟器上 `.adi` 在设备端
   （getApplicationDocumentsDirectory），主机 ffx 读 `tools/adi/.adi`；
   通过 exportDiagnosticZip → adb pull → `ffx adi import` 完成设备→主机同步。
3. **agent.py 增加 `--simulator` 模式**：跳过 run_before/after_capability
   （改由外部 integration_test + import 完成），只执行 observe → reason_and_patch
   → validate → capability_e2e，保持 C1/C2/C3 与 P1-P6 断言不变。
4. **真机证据更接近真实产品**：模拟器上 overflow 由真实渲染管线触发
   （非 FakeAsync zone），与 adi_real_fault_test 同等级（后者已实测通过）。
