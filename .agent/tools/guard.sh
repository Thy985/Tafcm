#!/usr/bin/env bash
# guard.sh — Repository Safety Layer 的机器强制层。
#
# 规则文本见 .agent/COMMAND_SAFETY.md / GIT_RULES.md / ENVIRONMENT.md。
# 本文件把其中的断言变成可执行代码，让"忘记检查"在物理上不可能发生。
#
# 用法：
#   source .agent/tools/guard.sh          # 在脚本中引入断言函数
#   bash   .agent/tools/guard.sh doctor   # 日常体检
#   bash   .agent/tools/guard.sh nested   # 仅扫描嵌套 .git（pre-push 用）
#   bash   .agent/tools/guard.sh target <path>   # 单独校验一个危险目标
#
# 兼容 Git Bash (Windows) 与 WSL/Linux。
# 注意：所有 git 调用一律 `cd "$root" && git ...`，不用 `git -C`——
#       Git for Windows 不接受 MSYS 风格路径（/d/...）作为 -C 参数。

# ---------- 基础 ----------

guard_err() { echo "[guard] FATAL: $*" >&2; }

# 仓库根：从本脚本位置推导（.agent/tools/guard.sh -> 上两级），避免硬编码绝对路径。
# 返回当前 shell 原生格式（Git Bash 下为 /d/...），供 cd / find 使用。
guard_repo_root() {
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  (cd "$self_dir/../.." && pwd)
}

# ---------- 断言 1：危险目标路径 ----------
# COMMAND_SAFETY.md §2 —— 空 / 根 / 盘符 / HOME 本身，一律拒绝。
# 返回 0 = 安全放行；返回 1 = 拒绝（调用方必须检查返回值）。
assert_safe_target() {
  local target="${1:-}"

  if [ -z "$target" ]; then
    guard_err "目标路径为空（这正是 2026-07-30 事故的成因）"
    return 1
  fi

  # 先判根类路径，再去尾斜杠（否则 "/" 会被剥成空串，报错信息失真）
  case "$target" in
    "/"|"//")
      guard_err "目标是文件系统根: '$target'"; return 1 ;;
    [A-Za-z]:|[A-Za-z]:/|[A-Za-z]:\\)
      guard_err "目标是 Windows 盘符根: '$target'"; return 1 ;;
  esac

  local norm="${target%/}"
  if [ -z "$norm" ]; then
    guard_err "目标路径规范化后为空: '$target'"; return 1
  fi

  case "$norm" in
    "/mnt"|"/root"|"/home"|"/usr"|"/etc"|"/var"|"/bin"|"/lib"|"/opt")
      guard_err "目标指向系统目录: '$target'"; return 1 ;;
    "/mnt/"[a-z]|"/"[a-z])
      # /mnt/d = 整个 D 盘；/c、/d = Git Bash 下的盘符根
      guard_err "目标是挂载盘根（等于整个磁盘）: '$target'"; return 1 ;;
  esac

  if [ -n "${HOME:-}" ] && [ "$norm" = "${HOME%/}" ]; then
    guard_err "目标就是 HOME 本身（只允许 HOME 的子目录）: '$target'"; return 1
  fi

  # 相对路径容易在 cd 之后指向意外位置
  case "$norm" in
    /*|[A-Za-z]:/*) : ;;
    *) guard_err "目标必须是绝对路径: '$target'"; return 1 ;;
  esac

  echo "[guard] ✅ target OK: $norm"
  return 0
}

# ---------- 断言 2：安全 rsync ----------
# COMMAND_SAFETY.md §4 —— 强制 dry-run 预览 + 目标断言。
safe_rsync() {
  local src="${1:-}" dest="${2:-}"
  shift 2 2>/dev/null || true

  if [ -z "$src" ]; then guard_err "safe_rsync: SRC 为空"; return 1; fi
  if [ ! -d "$src" ]; then guard_err "safe_rsync: SRC 不存在: $src"; return 1; fi
  assert_safe_target "$dest" || return 1

  echo "[guard] rsync  ${src%/}/  ->  ${dest%/}/"
  mkdir -p "$dest" || { guard_err "无法创建目标目录: $dest"; return 1; }

  echo "[guard] --- dry-run 预览（末 20 行）---"
  rsync -a --delete --dry-run "$@" "${src%/}/" "${dest%/}/" | tail -20

  echo "[guard] --- 实际执行 ---"
  rsync -a --delete "$@" "${src%/}/" "${dest%/}/"
}

# ---------- 断言 3：嵌套 .git ----------
# ENVIRONMENT.md §1 —— flutter_app 等子目录永远不得成为独立仓库。
check_no_nested_git() {
  local root found
  root="$(guard_repo_root)"

  found="$(find "$root" -mindepth 2 -name .git -not -path "$root/.git/*" 2>/dev/null)"

  if [ -n "$found" ]; then
    echo "[guard] ❌ 检测到嵌套 .git（冒牌仓库，2026-07-30 同款事故）:" >&2
    echo "$found" >&2
    echo "[guard]    处置：用 mv 移到 /tmp（绝不用 rm），再核对父仓库 git status" >&2
    echo "[guard]    参见 .agent/GIT_RULES.md §5 损坏应急 SOP" >&2
    return 1
  fi

  echo "[guard] ✅ 无嵌套 .git"
  return 0
}

# ---------- 断言 4：仓库边界 ----------
# GIT_RULES.md 前置检查 —— .agent 的父目录必须就是 git 顶层。
check_repo_root() {
  local self_root toplevel actual
  self_root="$(guard_repo_root)"

  toplevel="$(cd "$self_root" && git rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$toplevel" ]; then
    guard_err "无法解析 git 仓库根（$self_root 不在任何 git 仓库内？）"
    return 1
  fi

  # 把 git 返回的路径（可能是 D:/... 形式）归一到当前 shell 原生形式再比较
  actual="$(cd "$toplevel" 2>/dev/null && pwd)" || actual="$toplevel"

  if [ "$self_root" != "$actual" ]; then
    echo "[guard] ❌ 仓库边界异常：.agent 的父目录不是 git 顶层" >&2
    echo "[guard]    .agent 父目录: $self_root" >&2
    echo "[guard]    git 顶层:      $actual" >&2
    echo "[guard]    很可能存在冒牌仓库，参见 .agent/ENVIRONMENT.md §1" >&2
    return 1
  fi

  echo "[guard] ✅ 仓库根: $actual"
  return 0
}

# ---------- doctor：日常体检 ----------
guard_doctor() {
  local root rc=0 fsck_out locks
  root="$(guard_repo_root)"
  echo "=== Repository Safety Doctor ==="
  echo "root = $root"
  echo

  check_repo_root      || rc=1
  check_no_nested_git  || rc=1

  echo
  echo "--- git fsck（期望零输出）---"
  fsck_out="$(cd "$root" && git fsck --no-dangling 2>&1)"
  if [ -n "$fsck_out" ]; then
    echo "$fsck_out" | head -10
    echo "[guard] ❌ fsck 有输出，仓库可能受损"
    rc=1
  else
    echo "[guard] ✅ fsck 干净"
  fi

  echo
  echo "--- .git 内残留 lock（期望无）---"
  locks="$(find "$root/.git" -maxdepth 2 -name '*.lock' 2>/dev/null)"
  if [ -n "$locks" ]; then
    echo "$locks"
    echo "[guard] ⚠️  存在残留锁文件，可能有进程持锁（见 ENVIRONMENT.md §4）"
    rc=1
  else
    echo "[guard] ✅ 无残留锁"
  fi

  echo
  echo "--- worktree ---"
  (cd "$root" && git worktree list 2>&1)

  echo
  echo "--- 工作区（前 15 行）---"
  (cd "$root" && git status --short 2>&1 | head -15)

  echo
  if [ "$rc" -eq 0 ]; then
    echo "[guard] ✅ 全部检查通过"
  else
    echo "[guard] ❌ 存在问题，处置见 .agent/GIT_RULES.md §5"
  fi
  return "$rc"
}

# ---------- CLI ----------
# 仅在被直接执行时运行；被 source 时只定义函数。
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  set -uo pipefail
  case "${1:-doctor}" in
    doctor)  guard_doctor ;;
    nested)  check_no_nested_git ;;
    root)    check_repo_root ;;
    target)  assert_safe_target "${2:-}" ;;
    *)
      echo "用法: bash .agent/tools/guard.sh [doctor|nested|root|target <path>]" >&2
      exit 2 ;;
  esac
  exit $?
fi
