# Agent Audit（Maintainer 每日审计存档）

**定位**：Tafcm 持续 Maintainer 审计的**每日存档区（事实账本）**。
每天一份，记录当天观察到的**新事实及其状态**，不是"今天做了什么"的聊天记录。

**原则**（与 .agent/ 治理一致）：
- 默认只读、只分析；仅在满足 Issue Admission 条件时建议创建 Issue。
- 不轻易宣布 Bug：每个 Finding 尽量给出代码位置、触发路径、证据与影响。
- 允许每天结论为 `No significant findings.`（这也是有效结果）。
- 不为了产出工作量而提建议。

**输出协议（三问原则）**：
- **Audit 记全**：Agent 到底发现了什么？证据是什么？（本目录）
- **Issue 管住**：项目现在到底需要处理什么？（GitHub Issue 工作对象）
- **Email 提醒决策**：维护者现在需要知道 / 决定什么？（立即邮件 + 每周 Digest）

## 命名约定

`YYYY-MM-DD-maintainer-audit.md`（日期为审计执行日的本地日期，UTC+8）。

## Audit 固定五块

| 块 | 内容 |
|----|------|
| `Repository Health` | Commit / Version / CI / Tests / Build |
| `New Findings` | 今日新事实（含状态机 Status：NEW/UNCHANGED/UPDATED/RESOLVED/REJECTED/DUPLICATE/WAITING_FOR_HUMAN） |
| `Existing Issue Updates` | 今日对既有 Issue 的延续（UPDATED/UNCHANGED/RESOLVED/WAITING_FOR_HUMAN + 新证据 + 下一步） |
| `Ecosystem Findings` | 生态观察（E-ID，含 PoC 决策；仅"值得 PoC"才建 `[Research]` Issue） |
| `Pending Decisions` | 需要维护者决策的事项清单 |

## 索引

| 日期 | 主题 | 链接 |
|------|------|------|
| 2026-09-01 | 公式导出空白（#216）根因 / CI Golden 持续红 / ADR-0032 缺失 | [2026-09-01-maintainer-audit.md](2026-09-01-maintainer-audit.md) |

## 自动化（tafcm-maintainer workflow）

- **INDEX.md**：Audit 历史索引表，由 `update_index.py` 自动追加（状态计数：New/Updated/Resolved/Issues/Ecosystem/Pending；Agent 去重记忆的持久层）。
- **TEMPLATE.md**：格式模板示例（供 Agent 与人类核对格式）。
- **机器校验**：`validate_audit.py` 强制校验每日 Audit（五块结构 + 枚举），失败 → workflow 失败，不伪装成功。
- **双邮件**：`send_report.py` —— P0/P1 立即邮件（Maintainer Alert）当天发；正常事项每周一 Weekly Digest（状态变化摘要，非每日复述）。
- **行为协议 / 权限 / 格式**：见 `.agent/tafcm-maintainer/`（PROMPT / POLICY / SCHEMA）。
- **深度调查**：复杂 Issue 完整分析见 `../agent-investigations/`（GitHub Issue 只放结论）。

## 状态图例（状态机）

- `NEW` 首次发现 · `UNCHANGED` 复查无变化 · `UPDATED` 获得新证据 · `RESOLVED` 已解决 · `REJECTED` 判定不值得修 · `DUPLICATE` 与既有项重复 · `WAITING_FOR_HUMAN` 等待维护者决策
- 第二天不得把旧 Finding 标成 NEW——必须给出延续状态
- 无重要发现时，当日 Audit 明确写 `No significant findings.`
