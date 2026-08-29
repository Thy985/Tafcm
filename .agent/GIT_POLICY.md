# GIT_POLICY.md — Agent 仓库策略（Repository Reliability System）

> 本文件定义 **Agent（AI 协作者）** 在 Tafcm 仓库中的 Git 行为边界。
> 它是 AGENTS.md 的运行时约束补充：AGENTS.md 规定「AI 提交分工」，
> 本文件规定「Agent 能/不能改哪些仓库状态」，是治理闭环的第四层。

---

## 0. 设计原则

仓库治理分四层，形成 **双保险 + 闭环**：

```
                 Repository Governance
                         |
 ------------------------------------------------
 |                 |               |             |
Branch         CI Gate       Golden       Agent Policy
生命周期       验证入口       环境稳定      行为边界
```

- **① Branch（生命周期）**：创建 → PR → merge → 自动 delete，闭环。
  由 `.github/workflows/branch-cleanup.yml` 周清 + 白名单保护实现。
- **② CI Gate（验证入口）**：本地 `pre-push` + 远程 `branch protection` 双保险。
  由 `.githooks/pre-push` + GitHub 分支保护设置实现。
- **③ Golden（环境稳定）**：本地 WSL 跑 golden（`flutter_app/tool/wsl_golden.sh`）
  + CI `workflow_dispatch` 一键更新基线（`update_goldens`）实现。
- **④ Agent Policy（行为边界）**：本文件。Agent 不能越过的人类责任边界。

---

## 1. Branch（分支）

Agent **允许**：
- 创建 feature/fix 分支（`feat/<scope>-<desc>` / `fix/<scope>-<desc>`，见 AGENTS.md §5.2）。
- 在自有分支上 commit（符合 Conventional Commits + Task scope）。
- push 自有分支到 `origin`（push 前必须先过 `preflight.sh`，见 §2）。

Agent **禁止**：
- 删除 `main` / `develop` / `release/*` 等受保护分支。
- `git push --force` / `--force-with-lease` 到任何受保护分支。
- 改写已合并历史（`git rebase` 已合入 main 的 commit）。
- 直接 push 到 `main`。

---

## 2. Push（推送前守门）

Agent 在 **任何 `git push` 之前必须**：

```
bash flutter_app/tool/preflight.sh
```

`preflight.sh` = 本地版 CI 守门（`flutter analyze --no-fatal-infos --fatal-warnings`
+ 同参数非 golden/perf 测试）。**未通过不得 push。**

- 紧急绕过（仅限本地确实无法跑的场景，如离线）：`SKIP_PREFLIGHT=1 git push`。
- Agent 不应自行决定绕过；确需绕过应明示用户。
- 本机需在 clone/worktree 执行一次 `bash flutter_app/tool/setup-hooks.sh`
  以启用 `core.hooksPath=.githooks`，使 `pre-push` hook 自动拦截。

---

## 3. Merge（合并 —— 人类专属）

Agent **禁止** 未经明确授权执行：
- `git merge` 受保护分支 / 在 GitHub 上 **merge PR**。
- 删除已合并分支（由 `branch-cleanup.yml` 自动化，不属 Agent 职责）。
- 修改分支保护规则、required status checks、token 权限等仓库设置。

上述操作归 **Human Owner** 专属（AGENTS.md §5.0 / §6.1）。

---

## 4. Golden（视觉基线）

- 本地验证 golden：先跑 `bash flutter_app/tool/wsl_golden.sh`（WSL 环境，
  与 CI Linux 基线一致，根治「push-and-pray」重复错误）。
- 跨平台渲染漂移导致基线需更新：CI 页 `Actions → CI → Run workflow →
  勾选 update_goldens`，由 `golden-update` job 重新生成产物，人工确认后提交。
- Agent 不得自行 `--update-goldens` 后沉默合入；基线变更须人类复核。

---

## 5. 故障自检清单

| 现象 | 原因 | 处置 |
|------|------|------|
| push 被 pre-push 拦 | preflight 未过 / 未跑 | 先跑 `preflight.sh` 修复；勿习惯性 `SKIP_PREFLIGHT=1` |
| push 不触发 CI | feature 分支 push 已不触发（设计如此） | 开 PR 即触发 PR CI；勿误以为 CI 挂了 |
| 同 commit 跑两次 | 理论已消除（push 仅 main） | 若仍见，检查 ci.yml `on` 作用域是否被改回 `['**']` |
| 分支越积越多 | branch-cleanup 未合入/未跑 | 确认 `.github/workflows/branch-cleanup.yml` 在 main 且已启用 |
