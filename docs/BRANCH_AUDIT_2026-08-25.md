## Branch Audit 2026-08-25 (PR-4 治理基线 + 执行结果)

> **生成时间**：2026-08-25
> **依据**：[v3 报告 §5.4](file:///D:/Projects/Active/math2/docs/REPO_AUDIT_2026-08-25.md) + [gh CLI 实时 PR 状态](file:///D:/Projects/Active/math2/.agent/REPO_POLICY.md)
> **前置 PR**：#167 (chore: restore root .gitignore) MERGED + #168 (fix preflight Windows) MERGED + #169 (chore: root cleanup) OPEN
> **本文件目的**：登记所有候选分支的 PR 状态 + ahead/behind 计数 + 决策建议 + **PR-4 执行结果**
> **PR-4 执行结果**：已删除 4 个本地 + 6 个远端 ref（含 GitHub 自动清理）

### PR-4 治理成果（执行后）

**远端**（`git fetch --prune origin` 后）：
| 保留 | 备注 |
|------|------|
| `origin/main` | 当前主线 |
| `origin/chore/root-cleanup-2026-08-25` | PR-169 OPEN（v2 PR-2）|
| `origin/chore/golden-failures-cleanup-2026-08-25` | PR-3 远端已 push（等开 PR）|

**本地**：
| 保留 | 备注 |
|------|------|
| `main` | 主线 |
| `chore/branch-governance-2026-08-25` | 本 PR 工作分支（merge 后删） |
| `chore/golden-failures-cleanup-2026-08-25` | PR-3 分支（merge 后删）|
| `chore/restore-root-gitignore` | v1 PR-1 工作分支（PR-167 已 merge, 待删）|
| `chore/root-cleanup-2026-08-25` | v2 PR-2 分支（PR-169 OPEN, merge 后删）|
| `feat/ffx-orchestrator-clean` | **E 类保留**（ahead=1，本地独有） |
| `feat/issue-triage-workflow` | **E 类保留**（ahead=3，base 落后 33）|
| `issue-change` | **E 类保留**（ahead=2） |

**已删除**（A+B+C 类）：
- 本地 4 个：`feat/adi-mcp-causality` / `feat/ffx-verification-orchestrator` / `feat/phase3.9-batch5` / `fix/preflight-windows-cmd-length`
- 远端 6 个：`feat/adi-mcp-causality` / `feat/ffx-verification-orchestrator` / `feat/issue-triage-workflow-clean` / `feat/phase3.9-batch5` / `test/issue-triage-e2e` / `fix/preflight-windows-cmd-length`（**全部由 GitHub PR-merge 后自动清理**）

---

### 方法
- `git for-each-ref refs/heads` 列出所有本地分支
- `git for-each-ref refs/remotes` 列出所有远端跟踪分支
- `gh pr list --state all --limit 30 --json number,title,state,headRefName,baseRefName,mergedAt,closedAt` 获取每分支对应的 PR 状态
- `git rev-list --count <branch> ^main` 计算 ahead
- `git rev-list --count main ^<branch>` 计算 behind
- **执行验证**：`git fetch --prune origin` 同步远端 ref 状态
- 分类：A=已合入 main 可删 / B=stale 镜像可删 / C=throwaway 可删 / D=OPEN PR 不能删 / E=本地独有需评估

### PR-4 黄线操作三段记录（per [.agent/GIT_RULES.md §3](file:///D:/Projects/Active/math2/.agent/GIT_RULES.md)）

**目标**: 4 个本地分支（feat/adi-mcp-causality, feat/ffx-verification-orchestrator, feat/phase3.9-batch5, fix/preflight-windows-cmd-length）+ 6 个远端 ref
**影响**: 删除 4 个本地 ref + 6 个远端 ref. 原 SHA 仍在 git reflog + 远端 main history（squash-merge 后内容已合入, 仅原 SHA 不可见）
**备份**: reflog（本地 90 天）+ origin/main（squash 后内容）+ fsck --no-dangling 零输出（执行后验证）

### 决策矩阵

#### A 类：已合入 main，删除（黄线 `git branch -d` + `git push --delete`）

| 分支 (本地 + 远端) | PR | 合并时间 | ahead/behind main | 备注 |
|--------------------|----|---------|------------------|------|
| `feat/adi-mcp-causality` (本地+远端) | #154 | 2026-08-18 06:35 | 35/13 | 已合入 7 天 |
| `feat/ffx-verification-orchestrator` (本地+远端) | #166 | 2026-08-25 09:42 | 29/3 | 已合入今日 |
| `feat/phase3.9-batch5` (本地+远端) | #157 | 2026-08-19 10:04 | 24/11 | 已合入 6 天 |
| `fix/preflight-windows-cmd-length` (本地+远端) | #168 | 2026-08-25 12:56 | 1/0 | **新发现**：本会话合并引入 |
| `chore/restore-root-gitignore` (远端) | #167 | 2026-08-25 12:44 | 1/2 | v1 PR-1 已被 PR-167 替代 |

#### B 类：stale 远端镜像（黄线 `git push --delete`）

| 远端分支 | 最新 PR | 状态 | 备注 |
|---------|---------|------|------|
| `origin/feat/issue-triage-workflow-clean` | #142 CLOSED | 8/12 close，base 落后 main 30 commit | **stale 镜像**，可删 |

#### C 类：throwaway（黄线 `git push --delete`）

| 远端分支 | commit msg | PR | 备注 |
|---------|-----------|----|----|
| `origin/test/issue-triage-e2e` | `test: add issue-triage e2e probe file (throwaway)` | #145 CLOSED | 名字 + commit msg 都明示 throwaway |

#### D 类：OPEN PR（不能删，PR 合入后再删）

| 分支 | PR | 状态 | 备注 |
|------|----|----|------|
| `chore/root-cleanup-2026-08-25` (本地+远端) | #169 | OPEN / MERGEABLE | **v2 PR-2**，7 files / +123/-4，等 merge |
| `chore/golden-failures-cleanup-2026-08-25` (本地+远端) | 无 PR | 本会话刚 push | 等 Human Owner 开 PR（基于 origin/main base） |

#### E 类：本地独有，需 Human 评估

| 分支 | PR | ahead/behind main | 评估需求 |
|------|----|------------------|---------|
| `feat/ffx-orchestrator-clean` (本地) | 无 | 1/5 | ahead=1 表示本地有 main 没的 commit，**可能是未推送的修复**——需 Human 查看 diff 后决定 push 或丢 |
| `issue-change` (本地) | #144 MERGED (历史) | 2/28 | ahead=2 表示本地有 main 没的 commit，**可能是后续未推送的修复**——需 Human 查看 diff 后决定 |
| `feat/issue-triage-workflow` (本地) | #142 (远端不同名 stale) | 3/33 | ahead=3 + behind=33，**base 严重落后 main**——需 Human rebase 或 rebase 后提新 PR |

### v1 报告偏差

| v1 报告项 | 实际状态 |
|-----------|---------|
| 7 本地分支 | ✅ 一致（含 `fix/preflight-windows-cmd-length` 是 v1 漏列的）|
| 5 远程 feature 分支 | ❌ 实际 6+：origin/feat/issue-triage-workflow-clean (stale) + origin/test/issue-triage-e2e (throwaway) + origin/fix/preflight-windows-cmd-length + 3 个 chore/* (PR-1/2/3) |
| `feat/issue-triage-workflow` 远端 | ❌ v1 说"无 clean 版"——实际是本地分支 ≠ 远端 clean 分支 |
| `feat/ffx-orchestrator-clean` / `issue-change` "local-only 不要现在删" | ✅ 仍然如此（ahead=1/2 表示有未推送内容）|

### 推荐执行顺序（PR-4 = branch governance）

1. **PR-4 单一 commit** = 删 A+B+C 类分支（先 `git branch -d` 本地，再 `git push origin --delete` 远端）
2. **E 类先列在 PR 描述里**——等 Human Owner 决定 push/丢/rebase
3. **D 类保留**——PR-169 + PR-3 (待开) 合入后再清理

### 不在本 PR（黄线保护）

- **不动 D 类**——OPEN PR 必须等合入
- **不动 E 类**——本地独有，ahead ≠ 0 表示有未推送内容，**不能盲删**
- **不** `git branch -D`（强删未合并）—— 全程用 `git branch -d`（已合并检测）
- **不** `--force` push——黄线，按 [.agent/GIT_RULES.md §3](file:///D:/Projects/Active/math2/.agent/GIT_RULES.md) 三段记录

### 沙箱外 Human 决策项

请确认以下 3 项 E 类分支处置：
1. `feat/ffx-orchestrator-clean` ahead=1 — push 远端 + 开新 PR / 丢弃本地 1 commit / 保留
2. `issue-change` ahead=2 — 同上
3. `feat/issue-triage-workflow` ahead=3 behind=33 — rebase origin/main 后 push / 丢弃 / 保留

### 不影响公共 API
- 不改任何代码
- 不开新功能 PR
- 只删已合入 + 关闭 + throwaway 分支
- E 类分支保留等待 Human 决策
