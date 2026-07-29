#!/usr/bin/env bash
# preflight.sh —— push 前本地复刻 CI 门禁（与 .github/workflows/ci.yml 保持一致）
#
# 用途：杜绝 "到 CI 才发现" 的重复失败（duplicate_import / unused_import /
#       unused_local_variable 等 --fatal-warnings 级问题，以及测试回归）。
#
# 用法（在 flutter_app/ 目录或仓库任意位置）：
#   bash flutter_app/tool/preflight.sh          # analyze + test
#   bash flutter_app/tool/preflight.sh --quick  # 仅 analyze（秒级）
#
# 注意：
# 1. 不要用 `flutter analyze | tail` —— 管道会吞掉真实退出码（历史踩坑）。
# 2. golden 测试不在本脚本范围：Windows 本机渲染与 Linux 基线不匹配，
#    请用 tool/wsl_golden.sh 在 WSL 中验证，或 CI 的 update-goldens 手动 job。

set -u
cd "$(dirname "$0")/.."   # -> flutter_app/

FAIL=0

echo "==================================================="
echo "[1/2] flutter analyze --no-fatal-infos --fatal-warnings"
echo "==================================================="
flutter analyze --no-fatal-infos --fatal-warnings
ANALYZE_EXIT=$?
if [ $ANALYZE_EXIT -ne 0 ]; then
  echo ""
  echo "❌ ANALYZE FAILED (exit=$ANALYZE_EXIT) —— CI 的 Analyze job 会挂，请先修复上面的 warning/error"
  FAIL=1
else
  echo "✅ analyze passed"
fi

if [ "${1:-}" = "--quick" ]; then
  exit $FAIL
fi

echo ""
echo "==================================================="
echo "[2/2] flutter test（与 CI Test job 同参数：排除 golden/perf）"
echo "==================================================="
# 与 ci.yml test job 完全一致的文件集与排除标签
flutter test --exclude-tags golden --exclude-tags perf --reporter compact \
  $(find test -name "*_test.dart" ! -path "test/golden/*")
TEST_EXIT=$?
if [ $TEST_EXIT -ne 0 ]; then
  echo ""
  echo "❌ TEST FAILED (exit=$TEST_EXIT)"
  FAIL=1
else
  echo "✅ tests passed"
fi

echo ""
if [ $FAIL -eq 0 ]; then
  echo "🟢 PREFLIGHT PASSED —— 可以 push"
else
  echo "🔴 PREFLIGHT FAILED —— 不要 push，先修复"
fi
exit $FAIL
