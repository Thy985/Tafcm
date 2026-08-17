#!/usr/bin/env bash
# Run #005 two-process proof driver — real production code repair proof.
#
# Flow:
#   Phase 1: before test (bug present)  -> P1 reproduced
#   Phase 2: apply agent fix to production source (git-diff auditable, B 层 P2)
#   Phase 3: after test in a FRESH process (recompiles fixed source)
#            -> P3 no overflow, P4 invariants, P5 not_reproduced, P6 pipeline
#   Phase 4: restore production source (authoritative cp restore)
#
# Usage: bash tools/adi/run005_proof.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 仓库根 = tools/adi 上两级；flutter_app 是仓库根的子目录
APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/flutter_app"
BLOCK="$APP_DIR/lib/presentation/blocks/code/code_block.dart"
BAK="$(mktemp)"
APPLY_FIX="$SCRIPT_DIR/run005_apply_fix.dart"

restore() { cp "$BAK" "$BLOCK" 2>/dev/null || true; }
trap restore EXIT
cp "$BLOCK" "$BAK"
echo "[run005] Phase 0: backup OK -> $BAK"

echo "[run005] Phase 1: before test (bug present -> P1 reproduced)"
(cd "$APP_DIR" && flutter test test/observability/fault_injection_run005_before_test.dart)

echo "[run005] Phase 2: apply agent fix to production source"
dart run "$APPLY_FIX" apply "$BLOCK"
git -C "$SCRIPT_DIR/.." diff --stat -- flutter_app/lib/presentation/blocks/code/code_block.dart || true

echo "[run005] Phase 3: after test (fixed source recompiled -> P3/P4/P5/P6)"
(cd "$APP_DIR" && flutter test --dart-define=ADL_RUN005_AFTER=true \
  test/observability/fault_injection_run005_after_test.dart)

echo "[run005] Phase 4: restore production source"
restore
cmp -s "$BAK" "$BLOCK" && echo "[run005] PASS: code_block.dart restored (working tree clean)"
