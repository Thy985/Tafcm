#!/usr/bin/env bash
# Run #006 simulator proof driver — Agent autonomous repair on a real emulator.
#
# Flow (设计见 docs/ADL-LOOP-RUN-006-PLAN.md §8，2026-08-17 无 zip 简化版):
#   Phase 0: backup code_block.dart + 清理 tools/adi/.adi
#   Phase 1: integration_test BEFORE（emulator 真实 runtime）→ RenderOverflow
#            → 设备端 .adi 目录逐文件 base64 透传（RUN006_FILE_BEFORE=...）
#   Phase 2: 解码逐文件直接落盘 tools/adi/.adi（无 zip / 无 adi import）
#   Phase 3: Agent 阶段 1（--simulator --reason-only）：
#            ffx adi latest-error → trace-show → replay → 推理 → 改码（真实 git diff）
#   Phase 4: integration_test AFTER（新 APK 重编译修复后源码）→ 无 overflow
#            → 直接覆盖 ADL_SESSION_ID 的 replay.json（not_reproduced）→ 逐文件透传落盘
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

# 从 flutter test 日志提取 RUN006_FILE_<phase>=<relpath>=<b64> 行，解码落盘。
decode_adi_files() {
  local log="$1" phase="$2"
  python - "$log" "$phase" "$ADI_STORAGE" <<'PYEOF'
import base64, os, re, sys
log, phase, adi = sys.argv[1], sys.argv[2], sys.argv[3]
pat = re.compile(r'RUN006_FILE_' + re.escape(phase) + r'=([^=]+)=(.*)')
count = 0
with open(log, encoding='utf-8', errors='replace') as f:
    for raw in f:
        line = raw.rstrip('\r\n')
        m = pat.search(line)
        if not m:
            continue
        rel, b64 = m.group(1), m.group(2)
        target = os.path.join(adi, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, 'wb') as out:
            out.write(base64.b64decode(b64))
        count += 1
print(f'[run006-sim]   decoded {count} .adi files for {phase}')
if count == 0:
    sys.exit(2)
PYEOF
}

echo "[run006-sim] Phase 1: BEFORE capability on $DEVICE (real runtime)"
(cd "$APP_DIR" && flutter test "$CAPABILITY" -d "$DEVICE" \
  --dart-define=ADL_RUN006_BEFORE=true --timeout 180s --reporter compact 2>&1 \
  | tee "$WORK/before.log")

echo "[run006-sim] Phase 2: decode + drop .adi files (no zip, no import)"
decode_adi_files "$WORK/before.log" "BEFORE"

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
# AFTER capability 直接把 replay/invariant 写到 ADL_SESSION_ID 目录（无 session 合并）
decode_adi_files "$WORK/after.log" "AFTER"
echo "[run006-sim]   target session replay: \
$(python -c "import json;print(json.load(open('$ADI_STORAGE/sessions/$SESSION_ID/replay.json'))['status'])" 2>/dev/null || echo 'missing')"

echo "[run006-sim] Phase 5: Agent validate (after-fix + capability E2E)"
python "$SCRIPT_DIR/run006_agent.py" --simulator --validate-only --root "$ROOT"

echo "[run006-sim] Phase 6: restore production source"
restore
cmp -s "$BAK" "$BLOCK" && echo "[run006-sim] PASS: code_block.dart restored (working tree clean)"
rm -rf "$WORK"
