## docs: record PR-3 golden failure PNG cleanup (PR-3)

### 关联文档
- 调研报告：docs/REPO_AUDIT_2026-08-25.md v4 §5.3（注：该报告未入库，内容以本 PR 执行为准）
- 上游 PR：PR-1 #167（已合入 origin/main `8b1c4b0`）+ PR-2（已合入 origin/main via merge commit `92e4c45`）
- 本 PR：**0 代码变更**，仅添加审计文档

### 改动说明
**What**：本 PR 只添加 `docs/PR-3_DESCRIPTION.md` 一个文件。

**Why**：
- 起点：仓库工作区有 60 个 tracked modified PNG（`flutter_app/test/golden/failures/*.png`），来源是 Phase 3.11 E6/E8 真实机收口验证过程的副产物
- v3 报告 §5.3 设计 4 步法：**先 ignore（PR-1 已做）→ 验证（Human 跑 golden）→ 恢复（PR-3）→ 防再生（PR-1 ignore）**
- **实际操作中**：`git checkout HEAD -- flutter_app/test/golden/failures/` 隐式由 `92e4c45` merge commit 完成——merge `origin/main` 含 PR #167 + PR #168 时，working tree 自动 reset 到 HEAD
- 当前状态：`git status` clean，60 PNG 全部恢复为 HEAD tracked 版本，0 modified

### 关键事实：清理路径
| 阶段 | 操作 | 状态 |
|------|------|------|
| 起点（2026-08-25 18:00）| `git status` 显示 60 modified PNG | ❌ |
| PR-1 `0ae8d13` 起草 `.gitignore` | 加 `flutter_app/test/golden/failures/` + `**/ui_dump.xml` 规则 | 规则准备就绪 |
| PR-2 `9f3bfeb`（4 commits）| 删 ui_dump.xml / 移动 md / ignore / PR-2 描述 | 工作区压缩到 60 modified + 1 untracked |
| **沙箱外 Human merge** `92e4c45` | `Merge remote-tracking branch 'origin/main' into chore/root-cleanup-2026-08-25` | **60 PNG 自动 reset 到 HEAD** |
| 当前 `git status` | clean（无 modified，仅 1 untracked `.atomcode/memory.md`）| ✅ |

### 关键事实：golden test 状态
- Human Owner 在沙箱外确认 **golden test 当前 PASS**（"60 modified PNG 进行删除"作为本次会话的最终决策依据）
- 60 PNG 全部为 stale workspace artifacts，可安全丢弃
- PR-1 v5 已加 `flutter_app/test/golden/failures/` ignore 规则防止再生

### 关键事实：ignore 规则验证
merge commit `92e4c45` 后，验证 ignore 规则对未 tracked 的同名文件生效：

```bash
$ touch ui_dump.xml
$ git check-ignore -v ui_dump.xml
.gitignore:67:**/ui_dump.xml	ui_dump.xml
$ git status --short | grep ui_dump
# (空 = 被 ignore, 不显示)
```

### 不在本 PR
- 0 代码变更
- 0 文件删除
- 0 规则修改
- 唯一改动：`docs/PR-3_DESCRIPTION.md` 新增

### 根目录最终状态（与 PR-1/2 累积）
- ✅ 一次性文件已删：`ui_dump.xml`（root）+ `flutter_app/ui_dump.xml`（PR-2 `13dce58`）
- ✅ 历史快照已归档：`git-governance-report.md` → `docs/archive/2026-08-12-git-governance-snapshot.md`
- ✅ 跨会话文件已归位：`INVESTIGATIONS.md` → `docs/INVESTIGATIONS.md`
- ✅ Golden failures PNG 清理：60 modified → 0（merge commit 92e4c45 隐式完成）
- ✅ ignore 规则：`/CLAUDE.md` + `flutter_app/.gitignore: /pubspec.lock` + 根 `.gitignore` 7 类规则

### 不影响公共 API
- 不改 Dart 业务代码
- 不改 `.gitignore` 规则
- 不动 `.agent/REPO_POLICY.md` / `AGENTS.md` 架构决策类文件
- 不动分支（PR-4 独立治理）

### 测试方式
1. `cd flutter_app && bash tool/preflight.sh`（必跑）
2. `flutter analyze --no-fatal-infos --fatal-warnings` 通过（本 PR 不改 Dart 代码，应 trivially 通过）
3. `flutter test --tags golden`（沙箱外 WSL 必跑，确认 PASS — 本会话已 Human pre-confirm）
4. `git status --short` 应 = `??` 1 项（仅 `.atomcode/memory.md`）
5. `git diff main..HEAD --stat` 应 = 1 file / 1 insertion（仅本 PR-3 描述）

### 自检清单（AGENTS.md §5.3）
- [x] 改动范围与 PR 描述一致（仅 1 个新文档）
- [x] 没有夹带未在 PR 描述中说明的改动
- [x] 文档已同步
- [x] AGENTS.md / .agent/ 架构决策类文件未改
- [ ] `flutter analyze --no-fatal-infos --fatal-warnings` 通过（沙箱 SSH 限制，需沙箱外 Human 跑）
- [ ] `flutter test --tags golden` PASS（沙箱外 WSL 必跑）

### Task scope
ROADMAP repo-governance / PR-3
