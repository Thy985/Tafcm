# docs/agent-audit —— Agent 每日观察层（Evidence Ledger）

## 本目录是什么

这是 Tafcm 持续 Maintainer 审计的**观察记录层**。每天一份，记录当天仓库的技术健康状态，以及当天发现但**未必需要行动**的 Findings。

**不是**流水账（不记录“今天看了哪些文件”），而是：
> 某一天 Tafcm 的技术健康状态 + Agent 当天发现但尚未必需要行动的 Findings。

## 三层模型（核心）

```
AGENT
  │
  ▼
DAILY AUDIT            ← 所有观察/发现（大池子，允许不确定）
  │
  ├─ 不值得行动 ──────── 留在 Audit（Status: OBSERVED）
  └─ 值得行动（Admission Gate 通过）
        ▼
GITHUB ISSUE           ← 筛选后的正式工作项（小池子）
        ▼
INVESTIGATION          ← docs/agent-investigations/ 深度调查
        ▼
FIX / RESEARCH → VERIFICATION → CLOSE
```

- **Audit** = 观察层 / Evidence Ledger（本目录）
- **Issue** = 经过 Admission Gate 筛选后，值得维护者正式管理的工作对象
- **Brief** = 每天提炼给维护者的 ≤3 条行动建议（不在本目录）

## 命名与索引

- 每日文件：`YYYY-MM-DD.md`（UTC+8 执行日）
- 索引：`INDEX.md`（每日 Findings/Ecosystem 的状态总表）

## 每日文件固定 7 节

1. Repository State（Commit / Version / CI / Tests / Build）
2. Findings（稳定 ID + Status）
3. Existing Issue Investigation
4. Ecosystem Watch
5. Architecture / Technical Debt
6. Test / Regression Gaps
7. Recommendations

## 稳定 ID

- Finding：`F-YYYY-MM-DD-NN`（如 `F-2026-09-01-01`）
- Ecosystem：`E-YYYY-MM-DD-NN`（如 `E-2026-09-01-01`）

ID 一经分配不改变，用于跨层溯源：`Observation → Finding → Issue → Investigation → Decision → Fix → Regression → Release`。

## Finding Status

| Status | 含义 |
|---|---|
| `OBSERVED` | 已记录，暂不升级 Issue（证据不足 / 不值得行动 / 保持观察） |
| `ISSUE_CREATED` | 已通过 Admission Gate 创建 GitHub Issue（正文含 `Audit Finding: F-...`） |
| `TRACKED_IN_ISSUE` | 已归入既有 Issue（写 Issue 号） |
| `RESOLVED` | 已解决（写 PR / commit） |

## Admission Gate（什么才创建 Issue）

只有以下之一才创建 Issue：
- High Confidence Bug（充分代码证据 + 明确影响）
- Strong Regression Risk
- Important Test Gap（会导致真实 Bug 无法被发现）
- Significant Architecture Drift
- Significant Ecosystem Risk

**不**创建 Issue：代码风格、轻微重构建议、“未来可能有用”、猜测性问题、大文件/复杂度观察、生态新库“发现”。

## Issue 模板（正文必须含 Audit 溯源）

```
## Summary
## Impact
## Evidence
  - lib/... / test/... / Audit: 2026-09-01 / F-2026-09-01-01
## Reproduction
## Root Cause
## Existing Investigation
## Proposed Direction
## Regression Test
## Related
  - Audit: ... / ADR: ... / PR: ...
```

## 生态三层（Observation → Evaluation → Decision）

- 生态发现先入 Audit（E-ID），只有“值得做 PoC”才建 `[Research]` Issue，PoC 后值得迁移才建 `[Architecture]` Issue。
- 不因为“发现一个新库”就建 Issue。

## 深挖放哪

- Issue 只保存当前结论；深度调查放 `docs/agent-investigations/issue-<N>-<topic>.md`。
- 模板：Question / Evidence / Root Cause / Alternatives / Ecosystem Research / Recommendation / Decision / Follow-up。

## 周度趋势

每周产出一份 `Weekly Engineering Review`（趋势分析：新增 Finding / 升级 Issue / 确认真实 Bug / 误报 / 生态结论 / 反复出现的问题 / 技术债趋势 / 下周建议），不再重复每日信息。
