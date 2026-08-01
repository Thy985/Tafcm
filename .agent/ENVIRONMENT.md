# ENVIRONMENT.md — 仓库物理边界与环境事实

> **本文件回答一个问题：我现在到底站在哪个仓库里？**
>
> 2026-07-30 的次生事故完全源于这个问题答错了——把 `flutter_app/` 当成了独立仓库。
> 本文件是该问题的**唯一权威答案**，任何 git 操作前必须与之核对。

---

## 1. 仓库拓扑（唯一真相）

```
D:/Projects/Active/math2/          ← ✅ 仓库根（Repository root）
├── .git/                          ← ✅ 唯一的 Git 目录（Git root）
├── .agent/                        AI 治理层（本安全层所在）
├── .githooks/                     core.hooksPath 指向此处
├── .github/workflows/             CI
├── design-system/                 设计 tokens（权威 tokens.json）
├── docs/                          架构文档 + ADR + UI_FIX_PLAN.md
├── formulafix-redesign.design/    设计稿（HTML）
└── flutter_app/                   ← ⚠️ 仅是子目录，不是仓库
    ├── lib/  test/  tool/
    └── pubspec.yaml               （有 pubspec 不代表是 git 仓库）
```

| 项 | 值 |
|----|-----|
| Repository root | `D:/Projects/Active/math2` |
| Git root | `D:/Projects/Active/math2/.git` |
| remote `origin` | `git@github.com:Thy985/fixmath.git` |
| 主分支 | `main`（受保护，仅 PR 合入） |
| `flutter_app` 身份 | **subdirectory only** |
| 远端路径前缀 | 所有 Flutter 文件在远端均为 `flutter_app/...` |

### 1.1 绝对禁止

```bash
cd flutter_app && git init          # ❌ 制造冒牌仓库（7/30 事故）
cd flutter_app && git remote add …  # ❌ 同上
```

**为什么危险**：`git init` 不会阻止你在已有仓库的子目录里建新仓库。
建成后该子目录会遮蔽父仓库，且远端树里所有路径都带 `flutter_app/` 前缀，
而冒牌仓库把 `flutter_app` 当成根 → **516 个文件全被判定为"已删除"，索引路径全错**。

**在 `flutter_app/` 里跑 git 命令本身是合法的**——git 会自动向上找到 `math2/.git`。
需要禁止的只是 `git init` 这类**创建/改写仓库身份**的命令。

### 1.2 强制自检

任何 git 写操作前：

```bash
git rev-parse --show-toplevel
# 必须输出：D:/Projects/Active/math2
# 输出任何其它路径 → 立即停止，按 REPO_POLICY §5 处置
```

发现意外的嵌套 `.git`：

```bash
find . -mindepth 2 -name .git -not -path "./.git/*"
# 期望：无输出
# 有输出 → 用 mv 移到 /tmp（绝不用 rm），再核对父仓库 git status
```

---

## 2. 关联工作树（Linked Worktrees）

| 路径 | 分支 | 状态 |
|------|------|------|
| `D:/Projects/Active/math2` | 主工作树 | 正常 |
| `D:/Projects/Active/math2-intent` | `fix/editor-intent-layer` @ `6c17aa6` | ⚠️ **目录已于 2026-07-30 被 rsync 事故删除** |

**关于 `math2-intent`**：目录没了，但**没有丢任何提交**——
分支 `fix/editor-intent-layer` 在本地 `refs/heads/` 与远端 `refs/remotes/origin/` 均存在，
SHA 一致（`6c17aa6`）。需要时可重建：

```bash
git worktree prune                                              # 清理失效元数据
git worktree add D:/Projects/Active/math2-intent fix/editor-intent-layer
```

**规则**：清理分支时**必须跳过** `fix/editor-intent-layer`。
被工作树占用的分支 git 会拒绝删除；即便工作树暂时缺失，该分支仍属在研工作。

---

## 3. 工具链位置

| 工具 | 路径 | 用途 |
|------|------|------|
| Flutter（Windows） | `C:/Users/lenovo/SDK/flutter/bin/flutter` | 日常 `analyze` / 非 golden 测试 / 构建 |
| Flutter（WSL Ubuntu） | `~/flutter346/bin/flutter`（`HOME=/home/lenovo`） | **golden 基线生成的唯一合法环境** |
| golden 脚本 | `flutter_app/tool/wsl_golden.sh` | 已内建安全变量展开，**优先用它，不要手搓 wsl 命令** |
| 本地守门 | `flutter_app/tool/preflight.sh` | `analyze --no-fatal-infos --fatal-warnings` + 非 golden 全量测试 |
| hooks | `core.hooksPath = .githooks` | `pre-push` 自动跑 preflight |

**版本约束**：WSL Flutter 与 CI 均为 **3.44.6**（`ubuntu-24.04`）。
版本不一致会导致 golden 基线与 CI 不匹配。

**golden 铁律**：
- 基线**只能**在 WSL/Linux 生成（字体渲染与 CI 一致）。
- Windows **永不**执行 `--tags golden`；`preflight.sh` 已用 `--exclude-tags golden` 排除。
- WSL 路径映射：D 盘 = `/mnt/d`。**这意味着 WSL 里的删除命令能删到 D 盘**（7/30 事故的传导路径）。

---

## 4. L1 环境风险状态

**历史问题**：Windows 资源管理器 git 壳扩展（TortoiseGit 图标缓存等）+ SearchIndexer
常驻持锁 `.git` 内文件 → `git commit` / `checkout` / `reset` 长期不可靠。
这是 2026-07 全部损坏事故的**根因层（L1）**。

**当前状态：已缓解（2026-07-30 验证）**

| 验证项 | 结果 |
|--------|------|
| `TGitCache` / `TSVNCache` / GitHub Desktop / SourceTree 进程 | 均不在运行 |
| `.git` 内残留 `*.lock` | 无 |
| 原生 `git commit` ×5 | 全部成功，~420ms/次 |
| `git add` / `checkout HEAD --` / `reset --soft` | 全部一次通过 |
| `git fsck --no-dangling` | 零输出 |

**结论**：可以使用原生 git 命令，GIT_RULES §4 的绕过术正式退役。

**未尽项（建议 Human Owner 确认）**：
- `WSearch` 服务仍在运行 → 「索引选项」中确认已排除 `D:\Projects`。
- Defender 排除列表需管理员权限读取 → 在「病毒和威胁防护 → 排除项」核对 `D:\Projects`。

**若 git 再次报错或卡住 → 任务管理器排查顺序**：

| 进程 | 身份 | 处置 |
|------|------|------|
| `TGitCache.exe` | TortoiseGit 图标缓存（头号惯犯） | 结束进程 + 禁用 icon overlay |
| `SearchIndexer.exe` | Windows 搜索索引 | 索引选项排除 `D:\Projects` |
| `MsMpEng.exe`（Antimalware Service Executable） | Defender 实时扫描 | 排除项加 `D:\Projects` |
| `explorer.exe` | 打开着仓库文件夹的壳扩展 | 关闭该窗口或重启 explorer |

精确定位持句柄进程：`handle.exe D:\Projects\Active\math2\.git`（Sysinternals）。

**长期最优解**：把仓库迁到 WSL 原生文件系统（如 `~/dev/math2`），Windows 侧只读访问。
既根除全部 Windows 文件锁，又顺带解决「golden 只能在 Linux 生成」的跨环境麻烦。

---

## 5. 开工自检（建议每日首次会话执行）

```bash
bash .agent/tools/guard.sh doctor
```

等价的手工版本：

```bash
git -C D:/Projects/Active/math2 rev-parse --show-toplevel   # = D:/Projects/Active/math2
git -C D:/Projects/Active/math2 fsck --no-dangling          # 期望零输出
find D:/Projects/Active/math2 -mindepth 2 -name .git -not -path "*/.git/*"   # 期望无输出
git -C D:/Projects/Active/math2 status --short              # 确认工作区符合预期
```

---

**版本 v1.0，生效日期 2026-07-30。**
