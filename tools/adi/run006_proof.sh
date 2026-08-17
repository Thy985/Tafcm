#!/usr/bin/env bash
# Run #006 autonomous agent repair proof driver.
#
# Flow:
#   Phase 0: backup production source + clean .adi observations
#   Phase 1: Agent harness runs the FULL loop via ffx CLI:
#              before capability -> observe (latest-error/trace/replay)
#              -> reason -> patch (real git diff) -> after capability
#              -> validate --after-fix -> capability E2E
#   Phase 2: restore production source + verify clean
#
# Usage: bash tools/adi/run006_proof.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$ROOT/flutter_app"
BLOCK="$APP_DIR/lib/presentation/blocks/code/code_block.dart"
BAK="$(mktemp)"
ADI_STORAGE="$ROOT/tools/adi/.adi"

restore() { cp "$BAK" "$BLOCK" 2>/dev/null || true; }
trap restore EXIT
cp "$BLOCK" "$BAK"
echo "[run006] Phase 0: backup OK -> $BAK"

# 清理旧的观察（Agent 必须只看到本次运行的证据）
rm -rf "$ADI_STORAGE/observations" "$ADI_STORAGE/sessions" "$ADI_STORAGE/traces"
mkdir -p "$ADI_STORAGE"
echo "[run006] Phase 0: .adi observations cleared"

echo "[run006] Phase 1: Agent autonomous repair loop"
python "$SCRIPT_DIR/run006_agent.py" --root "$ROOT"

echo "[run006] Phase 2: restore production source"
restore
cmp -s "$BAK" "$BLOCK" && echo "[run006] PASS: code_block.dart restored (working tree clean)"
