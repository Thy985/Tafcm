# Tafcm Audit Frontier — 未闭合审查任务队列

> **定位**：Cline 增量审查的"审查前沿"（审查任务队列，不是报告）。每条 Entry 是一条**未闭合的证据链**，记录"审到哪里了、还差什么、下一步做什么"。
> **配套**：POLICY.md §2.3.2（SUP-04 Audit Frontier 模型）· PROMPT.md §1/§11（审查优先级与每日流程）· validate_audit.py（frontier 格式校验）。
> **生命周期**：candidate → active → deepening → blocked → verified → cooling → retired
> **更新者**：Cline 每日更新；周度 Supervisor Pass（SUP-01）校准 depth target。

## Entry 字段规范

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | ✅ | `FR-NNN`（递增，永不复用） |
| `area` | ✅ | 审查区域（模块 / 文件 / 机制） |
| `depth` | ✅ | `current: N` 已追深度 / `target: N` 目标深度（周度校准，非 Cline 自定） |
| `open_question` | ✅ | 未回答的具体问题（一条或多条） |
| `next_action` | ✅ | 下一步（`type: targeted-test / static-trace / code-read / device-validation / regression-check` + `target: <路径>`） |
| `blocking_reason` | ✅ | `null` 或阻塞原因 |
| `last_verified_at` | ✅ | `YYYY-MM-DD` |
| `activation_reason` | ✅ | `changed-code / new-issue / test-failure / new-evidence / risk-driven` |
| `verification_status` | ✅ | `in-progress / needs-device-validation / confirmed / rejected` |
| `handoff` | ⭕ | 越界时：`executor: supervisor|human` + `reason` |

> **生命周期（区块归属）vs `verification_status`（字段值）**——两个不同维度，勿混淆：
> - **生命周期**是 Entry 在队列中的**阶段**（candidate → active → deepening → blocked → verified → cooling → retired），由 Entry 所在区块 / 状态迁移决定。
> - **`verification_status`** 是**证据链验证结论**，枚举：`in-progress / needs-device-validation / confirmed / rejected`。
> - 对应关系：`blocked` 阶段 → `verification_status: needs-device-validation`（有 handoff）；`verified` 阶段 → `verification_status: confirmed`（确认）或 `rejected`（排除）。**Entry 字段里不用 `verified` 作为 verification_status 值**。
> - **闭合产出物**：`verification_status: confirmed/rejected` 时必须附 `related_issue: #NNN`（Issue 链接）或 `evidence: <落点>`（文件路径 / 测试结果 / 提交 sha）字段——不允许「追到 target 但什么都没留下」。

## 活跃队列（active / deepening / blocked）

### FR-001 — C-01 Android 模拟器集成测试管道
- id: FR-001
- area: CI/android-emulator-integration
- depth: current: 1 / target: 3
- open_question: "smoke 链路通后，如何扩展至 editor/export/formula 全链路 device-level 集成测试？"
- next_action: type: targeted-test / target: flutter_app/integration_test/phase35_home_smoke_test.dart（已通）→ 扩展至 editor_screen + export_path
- blocking_reason: null
- last_verified_at: 2026-09-05
- activation_reason: test-failure
- verification_status: confirmed
- evidence: CI #840（databaseId=33879645265）Android Device Integration job success；smoke_test.dart + phase35_home_smoke_test.dart 各 🎉 1 test passed
- handoff: null

## 冷却区（cooling — 连续 3 轮无代码变化 / 无新证据 / 无新异常）

<!-- 冷却不是关闭：一旦新代码命中 / 新 Issue / 测试失败 / 新 Evidence → 回 active -->

### FR-002 — tools/adi analyze 错误备案
- id: FR-002
- area: tools/adi/test/import_zip_test.dart
- depth: current: 1 / target: 1（记录级，无需深挖）
- open_question: "是否需要在 CI 中增加 dart test 于 tools/adi？"
- next_action: type: decision / target: .github/workflows/ci.yml（低优先级，宽限期至 2026-09-16 Node.js 20 退役）
- blocking_reason: null
- last_verified_at: 2026-09-05
- activation_reason: new-evidence
- verification_status: in-progress
- handoff: null

## 归档区（retired — 保留 retired_at + retire_reason，未来可重激活）

<!-- 归档不是删除，是项目技术记忆 -->

## 操作规则

1. **每日**：从最高优先 active Entry 继续，depth N→N+1（"这一次永远比上一次更深"）
2. **闭合必须有产出**：verified 时附 Issue 链接或 confirmed/rejected 证据落点——不允许"追到 target 但什么都没留下"
3. **冷却**：连续 3 轮无代码变化 / 无新证据 / 无新异常 → 移入冷却区（释放审查预算）
4. **重激活**：新代码命中 / 新 Issue / 测试失败 / 新 Evidence → cooling → active
5. **越界**：真机 / WebView 渲染 / 设备行为无法在沙箱验证 → `verification_status: needs-device-validation` + `handoff` → SUP-03 交 Supervisor / 人工，Evidence 回流后从 Frontier 恢复
6. **depth target 校准**：由 Cline 提议，周度 Supervisor Pass 确认——不允许自定 target 提前闭合
