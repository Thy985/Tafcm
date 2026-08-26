## chore: root cleanup + tracked state corrections (PR-2)

### 关联文档
- 调研报告：[docs/REPO_AUDIT_2026-08-25.md](docs/REPO_AUDIT_2026-08-25.md) v4（注：该报告 v3 章节有事实错误，实际以本 PR 执行为准）
- 上游 PR：PR-1 `chore/restore-root-gitignore`（必须先合入）

### 改动说明
**What**：PR-2 由 4 个独立 commit 组成，每个 commit 单一职责。

**Why**（v5 修正）：
- v1 调研报告 §3.2 / v3 / v4 报告将 3 个根目录 md 文件 + ui_dump.xml **错误地标为 untracked**
- 实际这 4 个文件都是 main HEAD tracked（`git ls-files` 验证）
- v1 调研报告 §3.3 还将 3 个项目资产（`.claude/settings.json` / `.github/workflows/openwiki-update.yml` / `tools/adi/pubspec.lock`）**错误地列在 untracked**
- 实际这 3 个文件**从未存在过**——v1 报告基于缓存/幻影数据
- v2 期间按错误前提执行了"伪 move"（`mv` + `git add`，没 `git rm` 原文件，导致 6 个文件并存）—— **commit message 撒谎**
- v3 期间我主动 `git reset --hard 199a413` 回退 v2，重新按正确流程 `git rm` / `git mv` 重做

### Commits (4 个)

| # | SHA | Commit | 作用 |
|---|-----|--------|------|
| 1 | `da6fd90` | chore(flutter_app): ignore pubspec.lock | App 项目不提交锁文件（AGENTS.md §6.2.3） |
| 2 | `98df27d` | chore: ignore /CLAUDE.md | 避免与 AGENTS.md 末 OPENWIKI 块双源 |
| 3 | `13dce58` | chore: remove 2 ui_dump.xml + relocate 2 root md files | **真正的 git rm + git mv**，不是伪 move |
| 4 | (本 commit) | docs: add PR-2_DESCRIPTION | 本 PR 描述存档 |

### 关键 diff 摘要

| 文件 | 变化 |
|------|------|
| `flutter_app/.gitignore` | +3 行（`/pubspec.lock` App-scoped 规则） |
| `.gitignore`（根） | +6 行（`/CLAUDE.md` ignore 规则） |
| `ui_dump.xml` | **git rm**（19,152 B） |
| `flutter_app/ui_dump.xml` | **git rm**（8,467 B） |
| `INVESTIGATIONS.md` | **git mv** → `docs/INVESTIGATIONS.md`（63% similarity, git rename detection） |
| `git-governance-report.md` | **git mv** → `docs/archive/2026-08-12-git-governance-snapshot.md`（89% similarity） |
| `docs/INVESTIGATIONS.md` | +13 行（位置 / 定位 / 层级说明） |
| `docs/archive/2026-08-12-git-governance-snapshot.md` | +4 行（⚠️ 过期标注） |

### 验证
- `git check-ignore -v ui_dump.xml` 命中（行 66）—— PR-1 起草的 `**/ui_dump.xml` 规则
- `git check-ignore -v flutter_app/ui_dump.xml` 命中（行 66）
- `git check-ignore -v CLAUDE.md` 命中（PR-2 commit 2）
- `git check-ignore -v flutter_app/pubspec.lock` 命中（PR-2 commit 1）
- `git fsck --no-dangling` 零输出
- 4 个 commit 都在 `chore/root-cleanup-2026-08-25` 分支，**未推送**（沙箱无 push 能力）

### 根目录最终状态
- 一次性文件已删：`ui_dump.xml` + `flutter_app/ui_dump.xml`
- 历史快照已归档：`git-governance-report.md` → `docs/archive/2026-08-12-git-governance-snapshot.md`
- 跨会话文件已归位：`INVESTIGATIONS.md` → `docs/INVESTIGATIONS.md`
- ignore 规则新增：`/CLAUDE.md` + `flutter_app/.gitignore: /pubspec.lock`

### 不在本 PR（待后续）
- **PR-3**：60 个 tracked modified PNG（golden failures）— **需 Human pre-confirm golden test 当前状态**
- **PR-4**：分支治理（7 本地 + 5 远程）— 独立 PR，Human 主导
- **PR-5**：AGENTS.md §14.1 顶层目录清单同步
- **后续 PR**：`.atomcode/memory.md`（1 个 untracked）— 评估 ignore 或 add

### v1 报告错误登记
本 PR 修正了 v1 调研报告的 2 处事实错误：
1. 3 个根目录 md + ui_dump.xml + flutter_app/ui_dump.xml 实际都是 tracked，**不是** untracked
2. 3 个项目资产（.claude/settings.json / openwiki-update.yml / tools/adi/pubspec.lock）**从未存在**

### 不影响公共 API
- 不改 Dart 业务代码
- 不动 `.agent/REPO_POLICY.md` / `AGENTS.md` 架构决策类文件
- 不动分支（PR-4 独立治理）

### 测试方式
1. `cd flutter_app && bash tool/preflight.sh`（必跑）
2. `flutter analyze --no-fatal-infos --fatal-warnings` 通过（PR-2 不改 Dart 代码，应 trivially 通过）
3. `git check-ignore -v ui_dump.xml flutter_app/ui_dump.xml CLAUDE.md flutter_app/pubspec.lock` 全部命中
4. `git fsck --no-dangling` 零输出
5. `git log --oneline chore/root-cleanup-2026-08-25 ^chore/restore-root-gitignore` 应 = 4 commits

### 自检清单（AGENTS.md §5.3）
- [x] 改动范围与 PR 描述一致（4 个 commit，每个单一职责）
- [x] 没有夹带未在 PR 描述中说明的改动
- [x] commit message 真实反映改动（commit 3 是真正的 git rm + git mv，不是伪 move）
- [x] 文档已同步
- [x] AGENTS.md / .agent/ 架构决策类文件未改
- [ ] `flutter analyze --no-fatal-infos --fatal-warnings` 通过（沙箱 SSH 限制，需沙箱外 Human 跑）
- [ ] `flutter test` 通过（同上）

### Task scope
ROADMAP repo-governance / PR-2
