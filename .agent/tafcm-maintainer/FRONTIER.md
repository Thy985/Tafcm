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

## 活跃队列（active / deepening / blocked）

Cline 每日在此登记/推进 Entry。每条 Entry 以 `### FR-NNN` 三级标题开头，字段如下（示例）：

```
### FR-001
- area: Formula PDF export
- depth: current: 2 / target: 4
- open_question: "Opacity(0) 捕获是否导致 toImage 全透明？"
- next_action: type: static-trace / target: lib/core/export/formula_pdf_renderer.dart
- blocking_reason: null
- last_verified_at: 2026-09-03
- activation_reason: risk-driven
- verification_status: in-progress
```

## 冷却区（cooling — 连续 3 轮无代码变化 / 无新证据 / 无新异常）

<!-- 冷却不是关闭：一旦新代码命中 / 新 Issue / 测试失败 / 新 Evidence → 回 active -->

## 归档区（retired — 保留 retired_at + retire_reason，未来可重激活）

<!-- 归档不是删除，是项目技术记忆 -->

## 操作规则

1. **每日**：从最高优先 active Entry 继续，depth N→N+1（"这一次永远比上一次更深"）
2. **闭合必须有产出**：verified 时附 Issue 链接或 confirmed/rejected 证据落点——不允许"追到 target 但什么都没留下"
3. **冷却**：连续 3 轮无代码变化 / 无新证据 / 无新异常 → 移入冷却区（释放审查预算）
4. **重激活**：新代码命中 / 新 Issue / 测试失败 / 新 Evidence → cooling → active
5. **越界**：真机 / WebView 渲染 / 设备行为无法在沙箱验证 → `verification_status: needs-device-validation` + `handoff` → SUP-03 交 Supervisor / 人工，Evidence 回流后从 Frontier 恢复
6. **depth target 校准**：由 Cline 提议，周度 Supervisor Pass 确认——不允许自定 target 提前闭合
