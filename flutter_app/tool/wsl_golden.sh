#!/usr/bin/env bash
# wsl_golden.sh —— 在 WSL Ubuntu（与 CI 同为 ubuntu-24.04）本地验证/生成 golden 基线
#
# 背景：golden 基线由 Linux 生成（ci.yml Golden job），Windows 本机字体渲染
#       不同无法直接比对 —— 这是 "push-and-pray" 循环的根因。本脚本在 WSL
#       内用与 CI 相同的 Flutter 版本跑 golden，push 前即可确认结果。
#
# 前置：WSL Ubuntu 内已安装 Flutter（默认 ~/flutter346，与 ci.yml
#       FLUTTER_VERSION 一致）。安装：
#   wsl -d Ubuntu -- bash -lc 'curl -fsSLo f.tar.xz https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/flutter_linux_<VERSION>-stable.tar.xz && tar xJf f.tar.xz && mv flutter ~/flutter346 && rm f.tar.xz'
#
# 用法（Windows Git Bash，在仓库任意位置）：
#   bash flutter_app/tool/wsl_golden.sh           # compare 模式：与仓库基线比对
#   bash flutter_app/tool/wsl_golden.sh --update  # update 模式：生成新基线并拷回仓库
#
# 实现要点：项目会被 rsync 到 WSL 原生文件系统 (~/fx_golden) 再跑测试——
#   1) 避免 WSL 直接写 /mnt/d 下的 .dart_tool 破坏 Windows 侧 pub 解析；
#   2) WSL 原生 fs 的 I/O 比 /mnt/d 快一个数量级。

set -eu
cd "$(dirname "$0")/.."   # -> flutter_app/
APP_DIR_WIN=$(pwd -W 2>/dev/null || pwd)
# Windows 路径 D:\x\y -> WSL 路径 /mnt/d/x/y
APP_DIR_WSL=$(echo "$APP_DIR_WIN" | sed -E 's|^([A-Za-z]):|/mnt/\L\1|; s|\\|/|g')

MODE="compare"
[ "${1:-}" = "--update" ] && MODE="update"

FLUTTER_BIN='$HOME/flutter346/bin/flutter'
WORK='$HOME/fx_golden'

echo "[wsl_golden] mode=$MODE  src=$APP_DIR_WSL"

# 注意：用 set +e 包裹 wsl 调用，确保测试失败时仍能打印友好提示并正确返回退出码
#（外层 set -e 会在 wsl 失败时直接退出，跳过后面的红/绿提示）。
set +e
wsl -d Ubuntu -- bash -lc "
set -eu
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
mkdir -p $WORK
rsync -a --delete \
  --exclude .dart_tool --exclude build --exclude .git \
  '$APP_DIR_WSL/' $WORK/
cd $WORK
$FLUTTER_BIN pub get > /dev/null
if [ '$MODE' = 'update' ]; then
  $FLUTTER_BIN test --tags golden --update-goldens --reporter compact
else
  $FLUTTER_BIN test --tags golden --reporter compact
fi
"
RC=$?
set -e

if [ "$MODE" = "update" ]; then
  echo "[wsl_golden] 拷回新基线到 test/golden/golden/ ..."
  wsl -d Ubuntu -- bash -lc "cp $WORK/test/golden/golden/*.png '$APP_DIR_WSL/test/golden/golden/'"
  echo "[wsl_golden] 完成。git status 查看基线变更，确认后提交。"
else
  if [ $RC -eq 0 ]; then
    echo "🟢 golden compare 通过 —— push 后 CI Golden job 应为绿"
  else
    echo "🔴 golden compare 失败 —— 若为有意视觉变更，运行 --update 生成新基线"
  fi
fi
exit $RC
