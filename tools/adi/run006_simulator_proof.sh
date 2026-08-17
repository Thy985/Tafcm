#!/usr/bin/env bash
# Run #006 simulator proof driver — Agent autonomous repair on a real emulator.
#
# Flow (设计见 docs/ADL-LOOP-RUN-006-PLAN.md §8):
#   Phase 0: backup code_block.dart + 清理 tools/adi/.adi
#   Phase 1: integration_test BEFORE（emulator 真实 runtime）→ RenderOverflow
#            → exportDiagnosticZip 导出设备端 zip（打印 RUN006_ZIP_BEFORE）
#   Phase 2: adb pull zip → ffx adi import（证据合入 tools/adi/.adi）
#   Phase 3: Agent 阶段 1（--simulator --reason-only）：
#            ffx adi latest-error → trace-show → replay → 推理 → 改码（真实 git diff）
#   Phase 4: integration_test AFTER（新 APK 重编译修复后源码）→ 无 overflow
#            → zip 导出（replay=not_reproduced）→ adb pull → ffx adi import
#   Phase 5: Agent 阶段 2（--simulator --validate-only）：
#            ffx adi validate --after-fix → after=pass + capability E2E
#   Phase 6: restore code_block.dart
#
# Usage: bash tools/adi/run006_simulator_proof.sh [device-id]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$ROOT/flutter_app"
BLOCK="$APP_DIR/lib/presentation/blocks/code/code_block.dart"
BAK="$(mktemp)"
ADI_STORAGE="$ROOT/tools/adi/.adi"
WORK="$(mktemp -d)"
DEVICE="${1:-emulator-5554}"
CAPABILITY="integration_test/run006_capability_test.dart"

restore() { cp "$BAK" "$BLOCK" 2>/dev/null || true; }
trap restore EXIT
cp "$BLOCK" "$BAK"
echo "[run006-sim] Phase 0: backup OK -> $BAK"

# 清理旧的观察（Agent 必须只看到本次运行的证据）
rm -rf "$ADI_STORAGE/observations" "$ADI_STORAGE/sessions" "$ADI_STORAGE/traces"
mkdir -p "$ADI_STORAGE"

echo "[run006-sim] Phase 1: BEFORE capability on $DEVICE (real runtime)"
(cd "$APP_DIR" && flutter test "$CAPABILITY" -d "$DEVICE" \
  --dart-define=ADL_RUN006_BEFORE=true --timeout 180s --reporter compact 2>&1 \
  | tee "$WORK/before.log")
BEFORE_B64="$(grep -o 'RUN006_ZIP_B64_BEFORE=.*' "$WORK/before.log" | head -1 | cut -d= -f2-)"
if [ -z "$BEFORE_B64" ]; then
  echo "[run006-sim] ❌ no RUN006_ZIP_B64_BEFORE in output" >&2
  exit 1
fi
# 设备私有目录对 adb shell 不可读 → base64 透传解码（GNU base64 -d）
echo "$BEFORE_B64" | base64 -d > "$WORK/before.zip"
echo "[run006-sim]   decoded before.zip: $(wc -c < "$WORK/before.zip") bytes"

echo "[run006-sim] Phase 2: import (before evidence)"
(cd "$ROOT/tools/adi" && dart run adi.dart import "$WORK/before.zip" --json | head -5)

echo "[run006-sim] Phase 3: Agent reason (observe -> infer -> patch)"
python "$SCRIPT_DIR/run006_agent.py" --simulator --reason-only --root "$ROOT" \
  | tee "$WORK/reason.json"
if ! grep -q '"status": "autonomous_agent_repair_proven"' "$WORK/reason.json" \
   && ! grep -q '"patch"' "$WORK/reason.json"; then
  echo "[run006-sim] ❌ Agent reason phase produced no patch" >&2
  exit 1
fi

echo "[run006-sim] Phase 4: AFTER capability on $DEVICE (fixed source recompiled)"
SESSION_ID="$(python -c "
import json,sys
ev=json.load(open('$WORK/reason.json'))
print(ev.get('observation',{}).get('session_id',''))")"
echo "[run006-sim]   session: $SESSION_ID"
(cd "$APP_DIR" && flutter test "$CAPABILITY" -d "$DEVICE" \
  --dart-define=ADL_RUN006_AFTER=true \
  --dart-define=ADL_SESSION_ID="$SESSION_ID" \
  --timeout 180s --reporter compact 2>&1 | tee "$WORK/after.log")
AFTER_B64="$(grep -o 'RUN006_ZIP_B64_AFTER=.*' "$WORK/after.log" | head -1 | cut -d= -f2-)"
if [ -z "$AFTER_B64" ]; then
  echo "[run006-sim] ❌ no RUN006_ZIP_B64_AFTER in output" >&2
  exit 1
fi
echo "$AFTER_B64" | base64 -d > "$WORK/after.zip"
echo "[run006-sim]   decoded after.zip: $(wc -c < "$WORK/after.zip") bytes"
(cd "$ROOT/tools/adi" && dart run adi.dart import "$WORK/after.zip" --json | head -5)

# AFTER zip 的 metadata.sessionId 是新 service 生成的（ObservabilityService
# 无法注入 sessionId），导入后 replay 落在新 session 目录；把 after 的
# replay/invariant 合并到 Agent 观察到的目标 session，validate 才能读到
# not_reproduced（与 widget 版覆盖同一 session 的语义一致）。
AFTER_SESSION="$(python -c "
import zipfile, json, sys
z = zipfile.ZipFile(r'$WORK/after.zip')
meta = json.loads(z.read('metadata.json'))
print(meta.get('sessionId', ''))")"
echo "[run006-sim]   after import session: $AFTER_SESSION (target: $SESSION_ID)"
if [ -n "$AFTER_SESSION" ] && [ "$AFTER_SESSION" != "$SESSION_ID" ]; then
  cp "$ADI_STORAGE/sessions/$AFTER_SESSION/replay.json" \
     "$ADI_STORAGE/sessions/$SESSION_ID/replay.json"
  cp "$ADI_STORAGE/sessions/$AFTER_SESSION/invariant_report.json" \
     "$ADI_STORAGE/sessions/$SESSION_ID/invariant_report.json"
  echo "[run006-sim]   merged after replay/invariant -> $SESSION_ID"
fi

echo "[run006-sim] Phase 5: Agent validate (after-fix + capability E2E)"
python "$SCRIPT_DIR/run006_agent.py" --simulator --validate-only --root "$ROOT"

echo "[run006-sim] Phase 6: restore production source"
restore
cmp -s "$BAK" "$BLOCK" && echo "[run006-sim] PASS: code_block.dart restored (working tree clean)"
rm -rf "$WORK"
