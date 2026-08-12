#!/usr/bin/env bash
# run_fixtures.sh — Issue Triage fixture 驱动冒烟测试（C2）
#
# 目标：让 .github/fixtures/issue-triage 下的 fixtures 在 CI 中被真正执行，
# 而非仅作文档摆设。覆盖：
#   1) architecture_test.py 不变量守门（ADR D1/D6/D10）
#   2) validate_findings.py 对合法 fixture 通过 / 对超长 body 拒绝（C4）
#   3) fetch_input.sh branch_scan 离线产出 context.md
#   4) create_issues.sh GH_MOCK=1 跑通：history 跨 run 去重 + create/suggest 三态
#
# 依赖：python3 / jq / sha256sum（CI ubuntu-24.04 与本地 Git Bash 均具备）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
FX=".github/fixtures/issue-triage"
SCR=".github/scripts/issue-triage"

PASS=0
FAIL=0
ok()  { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "== 1) architecture 不变量 =="
if python3 "$SCR/architecture_test.py"; then ok "architecture_test.py"; else bad "architecture_test.py"; fi

echo "== 2) validate 合法 fixture 应通过 =="
if python3 "$SCR/validate_findings.py" "$FX/github-mock.json" "$ROOT/.github/schemas/findings.schema.json" >/dev/null 2>&1; then
  ok "validate findings fixture"
else
  bad "validate findings fixture"; python3 "$SCR/validate_findings.py" "$FX/github-mock.json" "$ROOT/.github/schemas/findings.schema.json"
fi

echo "== 3) extractor branch_scan 离线产出 context.md =="
rm -rf .tmp/issue-triage
if bash "$SCR/fetch_input.sh" && test -s .tmp/issue-triage/context.md; then
  ok "fetch_input.sh branch_scan"
else
  bad "fetch_input.sh branch_scan"
fi

echo "== 4) executor GH_MOCK=1：history 去重 + create/suggest 三态 =="
# 预置跨 run 记忆：含 f1 同指纹 → 期望 f1 被去重跳过（D6 跨 run 去重）
FP="$(printf '%s' "bug-parser-markdown-inline-code" | sha256sum | cut -c1-16)"
printf '[{"fingerprint":"%s","issue_id":1,"key_title":"x","source":"PR #97","trust_level":"maintainer","created_at":"2026-01-01T00:00:00Z","created_issue":true,"decision":"create"}]\n' "$FP" \
  > .tmp/issue-triage/history.json
DRY_RUN=0 GH_MOCK=1 \
  FINDINGS="$FX/github-mock.json" \
  HISTORY_IN=.tmp/issue-triage/history.json \
  bash "$SCR/create_issues.sh" >/tmp/it-exec.log 2>&1 \
  && ok "create_issues.sh GH_MOCK run" \
  || { bad "create_issues.sh GH_MOCK run"; cat /tmp/it-exec.log; }
# 断言 f1 被去重命中（日志含 duplicate-of）
if grep -q "duplicate-of" /tmp/it-exec.log; then
  ok "f1 跨 run 去重命中 (D6)"
else
  bad "f1 未触发跨 run 去重"
fi

echo "== 5) validator 必须拒绝超长 body (C4) =="
python3 - "$FX/github-mock.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["findings"][0]["body"] = "x" * 70000
open("/tmp/big_body.json", "w", encoding="utf-8").write(json.dumps(d))
PY
if python3 "$SCR/validate_findings.py" /tmp/big_body.json >/dev/null 2>&1; then
  bad "validator 未拒绝超长 body"
else
  ok "validator 拒绝超长 body (C4)"
fi

rm -rf .tmp/issue-triage /tmp/big_body.json /tmp/it-exec.log

echo ""
echo "==== fixture 测试结果: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
