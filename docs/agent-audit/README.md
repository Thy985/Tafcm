# Agent Audit（Maintainer 每日审计存档）

**定位**：Tafcm 持续 Maintainer 审计的**每日存档区**。
每天一份，记录当天对仓库真实状态的审查结论：
新发现 / Issue 调查 / 生态观察 / 架构与技术债 / 测试缺口 / 建议动作。

**原则**（与 .agent/ 治理一致）：
- 默认只读、只分析；仅在满足 Issue Admission 条件时建议创建 Issue。
- 不轻易宣布 Bug：每个 Finding 尽量给出代码位置、触发路径、证据与影响。
- 允许每天结论为 `No significant findings.`（这也是有效结果）。
- 不为了产出工作量而提建议。

## 命名约定

`YYYY-MM-DD-maintainer-audit.md`（日期为审计执行日的本地日期，UTC+8）。

## 索引

| 日期 | 主题 | 链接 |
|------|------|------|
| 2026-09-01 | 公式导出空白（#216）根因 / CI Golden 持续红 / ADR-0032 缺失 | [2026-09-01-maintainer-audit.md](2026-09-01-maintainer-audit.md) |

## 自动化（tafcm-maintainer workflow）

- **INDEX.md**：Audit 历史索引表，由 `update_index.py` 自动追加（Agent 去重记忆的持久层）。
- **TEMPLATE.md**：格式模板示例（供 Agent 与人类核对格式）。
- **机器校验**：`validate_audit.py` 强制校验每日 Audit 格式（失败 → workflow 失败，不伪装成功）。
- **行为协议 / 权限 / 格式**：见 `.agent/tafcm-maintainer/`（PROMPT / POLICY / SCHEMA）。
- **深度调查**：复杂 Issue 完整分析见 `../agent-investigations/`（GitHub Issue 只放结论）。

## 状态图例

- Finding Status：`new`（新发现）/ `open`（未解决）/ `resolved`（已解决）/ `won't-fix`（判定不值得修）/ `duplicate`（重复）
- 无重要发现时，当日 Audit 明确写 `No significant findings.`
