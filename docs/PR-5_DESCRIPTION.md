## docs(agents): sync AGENTS.md §14.1 顶层目录清单 (PR-5)

### 关联文档
- 调研报告：[docs/REPO_AUDIT_2026-08-25.md](docs/REPO_AUDIT_2026-08-25.md) v4 §3.3 / §5.5
- 关联 PR：#167 + #168（已合入 origin/main `9e37e86`） + #169 (PR-2) + #170 (PR-3) + #171 (PR-4) 全部 MERGED，main HEAD = `10cbf4b`
- 本 PR：base = origin/main `10cbf4b`

### 改动说明
**What**：仅修改 `AGENTS.md` §14.1（line 841 起），97 insertions / 30 deletions。

**Why**：
- 起点：AGENTS.md §14.1 与实际仓库偏差较大（v3 报告 §3.3 已识别）
- v1 §14.1 列 4 个 tracked 顶层目录、26 篇 ADR、175 个 test、40 ffx-cli passing——**全部低估**
- v2 §14.1：17 个 tracked 顶层 + 10 个 ignored 顶层 + 临时 untracked 标注 + 完整目录树 + 14.1.1 七维治理策略表

### v1 vs v2 关键差异

| 项 | v1 | v2 | 依据 |
|------|----|----|------|
| tracked 顶层目录 | 4 (.agent/flutter_app/tools/docs) | **17** (.agent/.arts/.githooks/.github/AGENTS.md/LICENSE/README.md/contracts/design-system/docs/flutter_app/formulafix-redesign.design/skills/tests/tools + 2 git 元数据) | `git ls-tree --name-only HEAD` 实测 |
| ignored 顶层 | 0 | **10** (.adi/.claude/hooks.log/.codeartsdoer/.debug/.ffx/.openwiki/.wt/.workbuddy/flutter_app/build/ flutter_app/.dart_tool/) | PR-1 + PR-2 .gitignore 验证 |
| ADR 数量 | 26 | **29** | [docs/ADR/](docs/ADR/) 目录计数 |
| flutter_app/test | 175 | **175+** | 增量更新 |
| ffx-cli tests passing | 40 | **170+** | 增量更新（新增 E8 / harness / adapters / 视觉验证）|
| 完整目录树 | 缺大量子目录 | .agent/context/ + .agent/templates/ + .agent/tools/ + .agent/state/ + .claude/{settings.json,hooks.log} + ffx-cli/6 个子目录 + flutter_app/tool/ | git ls-tree -r 抽样 |

### 14.1.1 七维治理策略（v3 报告 §0.2 落地）

| 类别 | 治理方式 | 当前状态 |
|------|---------|---------|
| tracked source（业务代码） | intentional 跟踪 | ✅ main 已跟踪 17 个顶层 |
| project assets（设计稿 / 契约 / tokens / hooks） | intentional 跟踪 | ✅ 7 类项目资产全部 tracked |
| runtime artifacts（.adi / .ffx / .workbuddy / .wt / openwiki / debug） | **gitignore 拦截** | ✅ PR-1 + PR-2 .gitignore 规则覆盖 |
| one-shot artifacts（ui_dump.xml / 一次性根目录 md） | **删除 + gitignore 防再生** | ✅ PR-2 已 git rm 3 个 + ignore /CLAUDE.md / **/ui_dump.xml |
| generated artifacts（openwiki/、CI logs） | **明确生成策略 + ignore** | ✅ openwiki/ 由 OpenWiki GitHub Action 生成，已 ignore |
| docs | current（PR-5 已同步 §14.1） | ✅ 本 PR 提交 |
| branches | separate governed state | ✅ PR-4 已删 4 本地 + 6 远端 ref |

### 验证
- `git ls-tree --name-only HEAD` 列 17 个 tracked 顶层——与 §14.1 一致
- `git ls-files --others --exclude-standard` 列 1 个 untracked (`.atomcode/memory.md`)——已标注
- `git check-ignore -v .adi/ .ffx/ openwiki/ .claude/hooks.log flutter_app/test/golden/failures/` 全部命中——ignored 顶层正确
- pre-push hook 通过：analyze 0 error/warning + 345+ tests pass
- `git fsck --no-dangling` 零输出

### 不影响公共 API
- 0 行 Dart 代码变更
- 0 行 gitignore 变更
- 仅 AGENTS.md 文档同步（架构决策类文件，AGENTS.md §6.4 例外授权：本会话已显式获 Human Owner 授权）

### 测试方式
1. `git diff origin/main..HEAD --stat` 应 = 1 file / 97 insertions
2. `git ls-tree --name-only HEAD` 验证 17 个 tracked 顶层与 §14.1 描述一致
3. `git ls-files --others --exclude-standard` 应仅含 `.atomcode/memory.md`

### 自检清单（AGENTS.md §5.3 + §9.4）
- [x] 改动范围与 PR 描述一致（仅 AGENTS.md 1 文件）
- [x] 没有夹带未在 PR 描述中说明的改动
- [x] AGENTS.md §6.4 架构决策类文件授权例外：本会话已显式获 Human Owner 授权
- [x] 文档已同步（v3 报告 §3.3 / §5.5 描述了本 PR 策略）
- [x] 没有违反任何 Hard Rules
- [x] pre-push hook 通过（analyze + test）

### Task scope
ROADMAP repo-governance / PR-5
