# COMMAND_SAFETY.md — 危险命令协议

> **本文件回答：一条会删东西的命令，怎么写才不会失控？**
>
> 2026-07-30 一条 `rsync --delete` 因为目标变量展开为空，把目标塌缩成 `/`，
> 开始删除 WSL 根文件系统与挂载的整个 D 盘。
> 大部分删除撞上 `Permission denied` 被挡下，但 `flutter_app/.git` 和
> `math2-intent` 工作树目录没能幸免。
>
> **这不是手滑，是缺少断言。** 本文件把断言变成强制流程。

---

## 1. 危险命令清单

| 命令 | 危险点 |
|------|--------|
| `rm -rf <path>` | 路径为空/为 `/` 时毁灭；无回收站 |
| `rsync -a --delete SRC/ DST/` | **DST 为空 → 变成 `/`**；语义是"把 DST 改造成 SRC 的样子，删掉多余的一切" |
| `git reset --hard` | 丢弃工作区改动，不可逆 |
| `git clean -fd(x)` | 删未跟踪文件；`-x` 连 `.gitignore` 的产物一起删 |
| `find <path> -delete` / `-exec rm` | 路径为空则从当前目录起递归 |
| `mv <src> <dst>` | dst 已存在时静默覆盖 |
| `> file` / `truncate` | 静默清空 |
| `docker system prune -a` / `npm cache clean --force` | 影响范围远超直觉 |

**判据**：只要命令**可能删除或覆盖你没有逐一列举的文件**，就适用本文件。

---

## 2. 三条强制前置（缺一不可）

执行任何危险命令前，**必须**：

### ① 显示目标路径

把目标解析成**绝对路径并打印出来**，不能只在脑子里算。

```bash
echo "[danger] target = $DEST"
```

### ② 断言非空 + 断言不是根

```bash
[ -n "$DEST" ] || { echo "FATAL: DEST 为空，中止"; exit 1; }
case "$DEST" in
  /|/mnt|/mnt/*/|"$HOME"|C:/|D:/) echo "FATAL: DEST 指向根/盘符，中止"; exit 1 ;;
esac
```

**这一条就能完全阻止 7/30 事故。**

### ③ 输出影响范围

先用 dry-run 看清单，再实跑：

```bash
rsync -a --delete --dry-run "$SRC/" "$DEST/" | head -50
rm -rf ... → 先 find "$DEST" -maxdepth 1 | head -50
git clean -fd → 先 git clean -nd
```

危险度高时打印计数：`find "$DEST" -type f | wc -l`。

---

## 3. 跨 shell 边界：变量展开陷阱（7/30 事故的真正成因）

**出事的命令**：

```bash
# ❌ 千万不要这样写
wsl -d Ubuntu -- bash -lc "rsync -a --delete '$SRC/' \$WORK/"
```

逐层拆解为什么会炸：

| 片段 | Windows 侧 bash | 传进 WSL 后 | 结果 |
|------|----------------|------------|------|
| `'$SRC/'` | 未转义 → **展开**为真实路径 | 已是字面路径 | ✅ 正常 |
| `\$WORK/` | 转义 → **不展开**，原样传递 | WSL 内 `WORK` **从未定义** → 展开为**空** | 💥 目标变成 `/` |

`WORK` 只在 Windows 侧定义过。反斜杠让它躲过了 Windows 侧展开，
又在 WSL 侧找不到定义，于是静默变成空字符串——**`rsync --delete` 配空目标 = 核弹**。

### 规则

1. **`wsl -- bash -lc "…"` 内禁止使用 `\$VAR` 转义形式。**
2. 需要 WSL 侧变量 → **在 WSL 脚本块内部定义**：
   ```bash
   wsl -d Ubuntu -- bash -lc '
     set -euo pipefail
     WORK="$HOME/fx_golden"          # 在 WSL 内定义
     [ -n "$WORK" ] || exit 1
     mkdir -p "$WORK"
     rsync -a --delete "/mnt/d/Projects/Active/math2/flutter_app/" "$WORK/"
   '
   ```
3. 或者**直接写字面量** `~/fx_golden`，不用变量。
4. WSL 块开头一律 `set -euo pipefail`（`-u` 会让未定义变量直接报错退出，
   这本身就是一道免费的保险栓）。
5. **优先用仓库内已审核过的脚本**（`flutter_app/tool/wsl_golden.sh`），
   不要临时手搓 wsl 命令。手搓的每一条都是新的未审核代码。

⚠️ **牢记**：在 WSL 里，D 盘挂载为 `/mnt/d`。**WSL 内的删除命令能删到 Windows 文件。**
跨 shell 不代表跨越了危险边界。

---

## 4. 安全模板

### rsync（同步 + 删除多余）

```bash
set -euo pipefail
SRC="/mnt/d/Projects/Active/math2/flutter_app"
DEST="$HOME/fx_golden"

[ -n "$SRC" ]  || { echo "FATAL: SRC 为空"; exit 1; }
[ -n "$DEST" ] || { echo "FATAL: DEST 为空"; exit 1; }
[ -d "$SRC" ]  || { echo "FATAL: SRC 不存在: $SRC"; exit 1; }
case "$DEST" in /|/mnt|/mnt/*|"$HOME") echo "FATAL: DEST 太危险: $DEST"; exit 1 ;; esac

echo "[rsync] $SRC/  ->  $DEST/"
mkdir -p "$DEST"
rsync -a --delete --dry-run "$SRC/" "$DEST/" | tail -20     # 先看
rsync -a --delete "$SRC/" "$DEST/"                          # 再做
```

> 注意上面把 `"$HOME"` 本身也列为禁止目标——只允许 `$HOME` 的**子目录**。

### rm -rf

```bash
TARGET="/tmp/fx_build_cache"
[ -n "$TARGET" ] || { echo "FATAL: TARGET 为空"; exit 1; }
case "$TARGET" in /|/*/|"$HOME"|C:/*|D:/) echo "FATAL: 拒绝"; exit 1 ;; esac
echo "[rm] 即将删除 $TARGET（$(find "$TARGET" -type f 2>/dev/null | wc -l) 个文件）"
rm -rf "$TARGET"
```

### 一行式最小保险栓（临时命令也要带）

```bash
[ -n "$DEST" ] || exit 1
```

**没有这一行，就不要按回车。**

---

## 5. 个人文件的额外红线

对 桌面 / 下载 / 文档 / 用户主目录 / 系统目录（`C:\`、`/`、`AppData`、`~/.config`）：

- **禁止**递归删除，禁止通配删除（`*.tmp`、`*.log`），即使用户要求。
- 「扫描/整理」类请求 → **只读**：生成清单（路径、大小、时间），不移动不删除。
- 确需删除 → 走系统回收站（`gio trash` / Recycle Bin API），不用 `rm`。
- 每批 ≤ 10 个文件，逐批核对，任一失败立即停。

本仓库范围内的构建产物（`build/`、`.dart_tool/`）不适用此条，但仍需满足 §2。

---

## 6. 机器强制版本

上述断言已实现为可复用函数：

```bash
source .agent/tools/guard.sh

assert_safe_target "$DEST"        # 空 / 根 / 盘符 → 直接 exit 1
safe_rsync "$SRC" "$DEST"         # 内建三条强制 + dry-run 预览
check_no_nested_git               # 扫描意外的嵌套 .git
```

日常自检：

```bash
bash .agent/tools/guard.sh doctor
```

`pre-push` 钩子已接入 `check_no_nested_git`，把 7/30 类事故挡在推送之前。

---

**版本 v1.0，生效日期 2026-07-30。**
