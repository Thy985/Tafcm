# REPO_POLICY.md — Repository Safety Layer 总纲

> **本层的存在理由**：本仓库在 2026-07 期间被反复损坏（见 §4 事故登记册）。
> 复盘结论是——**问题不在 Git，在于协作基础设施缺位**：安全规则只存在于
> 会话记忆和临场判断里，而临场判断必然会失手。
>
> 本层把「什么能做、什么不能做、边界在哪」**外化成仓库内的文件 + 机器校验**，
> 使其可被任何 Agent / 人类在任何一次会话中无条件加载。

**适用对象**：所有 AI Agent（Claude Code / Codex / Cursor / TRAE / 自建 Agent）与人类协作者。
**加载时机**：Level 0 —— 每次会话开始、每次执行破坏性操作前，无条件加载。

---

## 1. 文件索引

| 文件 | 回答什么问题 | 何时必读 |
|------|-------------|---------|
| **REPO_POLICY.md**（本文件） | 为什么有这层？优先级？出事了怎么办？ | 每次会话开始 |
| [ENVIRONMENT.md](./ENVIRONMENT.md) | 仓库根在哪？`.git` 在哪？谁是子目录？ | **任何 git 操作前** |
| [GIT_RULES.md](./GIT_RULES.md) | 哪些 git 命令被禁？例外怎么申请？ | **任何 git 写操作前** |
| [COMMAND_SAFETY.md](./COMMAND_SAFETY.md) | 危险命令怎么写才安全？ | **任何删除/覆盖操作前** |
| [tools/guard.sh](./tools/guard.sh) | 机器强制版本（可执行断言） | 脚本中 `source`；`doctor` 子命令日常自检 |

已有的 [AI_POLICY.md](./AI_POLICY.md)（权限矩阵、停止条件）与
[GIT_POLICY.md](./GIT_POLICY.md)（分支/PR/merge 边界）**继续有效**，
本层是它们缺失的补集：**物理边界 + 命令安全**。

---

## 2. 优先级（冲突时的裁决规则）

```
Repository Safety Layer (.agent/REPO_POLICY / ENVIRONMENT / GIT_RULES / COMMAND_SAFETY)
        ↓  覆盖
AI_POLICY.md  /  GIT_POLICY.md
        ↓  覆盖
AGENTS.md
        ↓  覆盖
会话记忆 / Agent 自身判断
```

**已知冲突（已消解）**：`AGENTS.md §12.2` 原先把「临时 index + `commit-tree` +
`printf > .git/refs/heads/...`」写成**强制** commit 流程。该章节写于 L1 环境故障期，
是 L2 绕过术的**制度化根源**。

- 裁决：**以 GIT_RULES.md 为准**。
- 处置（2026-07-30，随本层同批提交，**待 Human Owner 批准**）：
  `AGENTS.md §12` 章首已加状态变更声明并指向本层；`§12.2` 标题改为
  「⚠️ 已退役 — 仅应急回退」，正文由"必须走以下流程"改为"保留供应急参考"。
- 若 Owner 不批准该修改，则本层 §2 优先级仍然生效——`AGENTS.md §12.2` 视为历史记录。

---

## 3. 三条不可协商铁律

> 违反其中任何一条都曾直接导致仓库损坏。没有"这次情况特殊"。

**铁律 1 — 边界先于操作**
任何 git 命令执行前，先确认自己站在哪个仓库里：

```bash
git rev-parse --show-toplevel   # 必须输出 D:/Projects/Active/math2
```

**铁律 2 — 目标先于删除**
任何带删除语义的命令（`rm -rf` / `rsync --delete` / `git clean` / `find -delete`）
执行前，必须**打印目标绝对路径**并**断言非空**。详见 COMMAND_SAFETY.md §2。

**铁律 3 — 底层操作需授权**
绕过 git 安全护栏、直接操作 `.git/` 内部存储的命令（`git init` / `update-ref` /
`commit-tree` / 直接写 `.git/*`）默认禁止。
例外仅在「**用户明确授权 + 备份完成 + 记录在案**」三条件同时满足时成立。详见 GIT_RULES.md §2。

---

## 4. 事故登记册（规则的出处）

> 每条规则都对应一次真实损坏。删规则前先读这里。

| 日期 | 事故 | 直接原因 | 产生的规则 |
|------|------|---------|-----------|
| 2026-07-26 | 对象库缺 blob `a36ac27`；`refs/heads` 子目录整体消失 | 长期手搓 `printf > .git/refs/...` 等底层写操作的累积副作用 | GIT_RULES §2 红线；§4 绕过术退役 |
| 2026-07-30 | `rsync --delete` 目标塌缩为 `/`，删除 WSL 根 + `/mnt/d` 大量文件；`flutter_app/.git` 被删；`math2-intent` 工作树目录被删 | `wsl -- bash -lc "... \$WORK/"`：`\$WORK` 被转义 → Windows 侧不展开 → WSL 内该变量从未定义 → 展开为空 → 目标变成 `/` | COMMAND_SAFETY §2 三条强制；§3 跨 shell 变量展开陷阱 |
| 2026-07-30（次生） | 在 `flutter_app/` 内 `git init` 造出冒牌仓库 → 516 条假删除、索引路径全错；`reset --mixed` 又把源文件覆盖成别的分支版本 → diff 假性放大成 558 行全文件重写 | 误把子目录当独立仓库（错误心智模型） | ENVIRONMENT.md §1 物理边界声明；GIT_RULES §2 禁 `git init`；§5 损坏应急 SOP |

**根因分层**（复盘结论）：

```
L1 环境层  Windows 壳扩展 + SearchIndexer 持锁 .git   ← 真正的病根
   ↓ 迫使
L2 应对层  长期手搓底层 git 绕过护栏                  ← 损坏的实际发生地
   ↓ 叠加
L3 认知层  把 flutter_app 误认为独立仓库
   ↓ 叠加
L4 操作层  危险命令无断言、变量可为空
```

**L1 已于 2026-07-30 处理**（关闭 Explorer git 壳扩展）：
原生 `git commit` ×5 连续成功（~420ms/次），`add`/`checkout`/`reset --soft` 全通过，
`git fsck` 零输出。→ **L2 绕过术自此退役**（GIT_RULES §4）。

---

## 5. 出事了怎么办（30 秒版）

完整流程见 GIT_RULES.md §5。核心顺序**不可颠倒**：

```
1. 止损     停掉正在跑的破坏性进程（wsl --terminate / kill）
2. 定边界   git rev-parse --show-toplevel   +   git ls-files | grep <子目录>/
3. 隔离     可疑 .git 用 mv 移到 /tmp，绝不用 rm
4. 自证     在真仓库跑 git status / git fsck，让仓库自己证明是否受损
5. 校基线   git checkout origin/main -- <文件> 取回正确基线，再重放改动
```

**最容易犯的错**：跳过第 2 步直接抢修。2026-07-30 我花了半小时抢修一个
**自己凭空造出来的**坏仓库，而真正的 `math2/.git` 从头到尾都是好的。

**第 5 步的意义**：在错误基线上叠改动会让 diff 假性放大成全文件重写，
既看不出真实改动，也可能把别的分支代码误提交进 PR。

---

## 6. 本层的变更权限

`.agent/` 下的安全层文件属**架构决策类文件**（AGENTS.md §6.4）。

- AI Agent：可**提案**（在 PR 中标注 `Requesting Approval:`），**不得自行合入**。
- Human Owner：唯一批准人。
- 新增规则时**必须同时在 §4 事故登记册补充出处**——没有事故支撑的规则会被当噪音忽略，
  这是规则腐化的开始。

---

**版本 v1.0，生效日期 2026-07-30。由 Human Owner 维护。**
