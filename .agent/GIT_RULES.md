# GIT_RULES.md — Git 命令红线

> **本文件回答：哪些 git 命令我不能自己决定执行？**
>
> 与 [GIT_POLICY.md](./GIT_POLICY.md) 的分工：
> GIT_POLICY 管**协作权限**（谁能 merge、能不能推 main）；
> 本文件管**命令安全**（哪些命令会破坏仓库物理状态）。
> 两者都必须遵守。

前置：执行任何 git 写操作前，先满足 [ENVIRONMENT.md §1.2](./ENVIRONMENT.md) 的边界自检。

---

## 1. 分级总览

| 级别 | 含义 | 处置 |
|:----:|------|------|
| 🔴 **红** | 绕过 git 安全护栏 / 直接改写仓库物理状态 | **禁止**，除非满足 §2 三条件 |
| 🟡 **黄** | 会丢失未提交工作或改写历史 | 先备份 + 说明影响范围，再执行 |
| 🟢 **绿** | 常规操作 | 自由使用 |

---

## 2. 🔴 红线命令（默认禁止）

```bash
git init                      # 在仓库内/子目录内制造冒牌仓库（7/30 事故）
git update-ref                # 手写 ref，绕过 git 一致性检查
git commit-tree               # 手搓 commit，绕过 index/hook/校验
git symbolic-ref HEAD …       # 手改 HEAD 指向
git hash-object -w + update-index --cacheinfo   # 手工塞对象与索引条目

echo   … >  .git/HEAD         # 任何形式的直接写 .git/* 都在此列
printf … >  .git/refs/heads/… # 7/26 refs/heads 子目录消失的直接成因
rm  -f      .git/index        # 删索引"修复"问题 —— 通常只会掩盖真因
rm  -rf     .git              # 毁灭级
```

**统一判据**：凡是**不经 git 前端、直接读写 `.git/` 内部存储**的操作，一律红线。
这类操作单次成功率很高，但每次都有小概率写坏 ref 或 index，**长期必然累积成损坏**——
2026-07-26 的两次损坏就是这么来的。

### 例外授权（三条件必须同时满足，缺一不可）

1. **用户明确授权** —— 针对本次具体操作的明示同意。
   「之前允许过」「一直都这么干」**不构成**授权。
2. **备份完成并已验证** —— 执行前完成下列之一，且已确认备份可用：
   ```bash
   cp -r .git /tmp/git_backup_$(date +%Y%m%d_%H%M%S)     # 整库快照
   git bundle create /tmp/repo_$(date +%s).bundle --all  # 全 ref 打包
   ```
3. **记录在案** —— 在会话中写明：为什么必须用红线命令、备份位置、失败回滚步骤。

授权成立后仍须：执行前打印完整命令、执行后立即 `git fsck --no-dangling` 自证。

---

## 3. 🟡 黄线命令（先备份 + 先说明）

```bash
git reset --hard <ref>     # 丢弃工作区改动，不可逆
git clean -fd / -fdx       # 删未跟踪文件（-x 连 .gitignore 的也删）
git checkout -- <path>     # 丢弃单文件改动
git push --force-with-lease  # 仅限自有 feature 分支；受保护分支见 GIT_POLICY §1
git rebase                 # 改写历史；已合入 main 的 commit 禁止 rebase
git worktree remove        # 可能删掉在研工作树（math2-intent 前车之鉴）
git branch -D              # 强删未合并分支
```

执行前必须输出：

```
目标: <绝对路径 / ref>
影响: <将丢失哪些改动，文件数量>
备份: <备份位置，或"已确认无未提交改动">
```

**`git clean` 特别提醒**：先跑 `git clean -nd`（dry-run）看清单，确认后再去掉 `n`。

---

## 4. 🟢 绿线：标准流程（现行）

**L1 环境问题已于 2026-07-30 缓解**（见 ENVIRONMENT.md §4），
`AGENTS.md §12.2` 的临时 index / `commit-tree` 绕过术**正式退役**。
现在使用原生 git：

```bash
# 1. 边界自检
git rev-parse --show-toplevel        # 必须 = D:/Projects/Active/math2

# 2. 切分支（从 origin/main）
git fetch origin
git switch -c feat/<scope>-<desc> origin/main

# 3. 精确 stage（禁止 git add -A / git add .）
git add <显式文件路径…>
git status --short                    # 核对：只有本次改动

# 4. 提交（Conventional Commits + Task scope，见 AGENTS.md §5.1）
git commit -m "feat(scope): subject" -m "body" -m "Task scope: …"

# 5. 推送（触发 pre-push → preflight 守门）
git push -u origin HEAD

# 6. 开 PR（AI 必须开 PR，禁止直推 main）
gh pr create --fill
```

### 绕过术的回退条件

仅当**原生 git 被实测证明失败**时，才允许考虑回退到临时 index 方案，且必须：

1. 先贴出原生命令的**完整报错**；
2. 先按 ENVIRONMENT.md §4 的任务管理器清单**定位持锁进程**并尝试解除；
3. 仍失败 → 按 §2 例外授权流程申请（临时 index + `commit-tree` 属红线）。

**不允许**在没有实测失败的情况下"预防性"使用绕过术。

---

## 5. 仓库损坏应急 SOP

顺序不可颠倒。**最容易犯的错是跳过第 2 步直接抢修。**

### 第 1 步 · 止损

停掉正在跑的破坏性进程：

```bash
wsl --terminate Ubuntu          # WSL 内失控进程
# Windows 侧：tasklist 定位后 taskkill
```

### 第 2 步 · 定边界（最关键）

**先证明哪个仓库真的坏了，再动手。**

```bash
git -C D:/Projects/Active/math2 rev-parse --show-toplevel
git -C D:/Projects/Active/math2 ls-files | grep '^flutter_app/' | head
git -C D:/Projects/Active/math2 fsck --no-dangling
```

2026-07-30 的教训：真正的 `math2/.git` 从头到尾都是好的，
我却花了半小时抢修一个**自己 `git init` 造出来的**坏仓库。

### 第 3 步 · 隔离可疑 `.git`

```bash
mv <可疑路径>/.git /tmp/bogus_git_$(date +%s)    # 用 mv，绝不用 rm
```

保留可回滚余地。确认无误后再删。

### 第 4 步 · 让真仓库自证

```bash
git -C D:/Projects/Active/math2 status --short
git -C D:/Projects/Active/math2 fsck --no-dangling
```

输出符合预期（只剩本次改动、fsck 无输出）→ 真仓库无损，损坏是"幻觉"。

### 第 5 步 · 校准基线再重放改动

```bash
git checkout origin/main -- <涉事文件…>     # 取回正确基线
# 然后重新施加本次改动
git diff origin/main --stat                 # 验证 diff 收敛到预期规模
```

**为什么必须做**：`reset --mixed` 等操作可能把文件覆盖成**别的分支**的版本。
在错误基线上叠改动 → `git diff` 假性放大成全文件重写（7/30 实测：真实改动 33 行，
diff 显示 558 行），既看不出真实改动，也可能把别的分支代码误提交进 PR。

**判据**：diff 行数应与你实际改动量同量级。数量级不符 = 基线错了，别急着提交。

### 第 6 步 · 重放脚本要求原子性

批量重放改动时，脚本必须：**对每处 `old_string` 断言唯一匹配，任一处不匹配就整体不写盘**。
禁止"改一半留中间态"——中间态比原损坏更难排查。

---

## 6. 与其它文件的关系

| 场景 | 看哪里 |
|------|--------|
| 能不能 merge / 推 main / 删分支 | [GIT_POLICY.md](./GIT_POLICY.md) |
| 我在哪个仓库、`.git` 在哪 | [ENVIRONMENT.md](./ENVIRONMENT.md) |
| `rm -rf` / `rsync --delete` 怎么写 | [COMMAND_SAFETY.md](./COMMAND_SAFETY.md) |
| Commit message 格式 / PR 清单 | `AGENTS.md §5` |

---

**版本 v1.0，生效日期 2026-07-30。**
