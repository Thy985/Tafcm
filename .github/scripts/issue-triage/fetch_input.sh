#!/usr/bin/env bash
# fetch_input.sh — Issue Triage 提取器（Deterministic Extractor）
#
# 职责（ADR-0025 D2）：把 GitHub 事件 / git log 规范化为固定 schema 的
# `context.md`，作为 Claude（Untrusted Reasoner）唯一输入。绝不把原始 payload 直接给模型。
#
# 输出：.tmp/issue-triage/context.md
# 环境变量：
#   GITHUB_REPOSITORY / GITHUB_EVENT_NAME / GITHUB_EVENT_PATH
#   PR_NUMBER        （workflow_dispatch 手动指定，可选）
#   TARGET_BRANCH / BASE_BRANCH （branch_scan 模式，可选）
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-Thy985/fixmath}"
EVENT_NAME="${GITHUB_EVENT_NAME:-workflow_dispatch}"
EVENT_PATH="${GITHUB_EVENT_PATH:-}"
PR_NUMBER="${PR_NUMBER:-}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
BASE_BRANCH="${BASE_BRANCH:-}"

OUT_DIR=".tmp/issue-triage"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/context.md"
FETCHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

OWNER="${REPO%%/*}"
NAME="${REPO#*/}"

# 从事件 payload 取 PR number
if [ -z "$PR_NUMBER" ] && [ -n "$EVENT_PATH" ] && [ -s "$EVENT_PATH" ]; then
  PR_NUMBER="$(jq -r '.pull_request.number // .issue.number // empty' "$EVENT_PATH" 2>/dev/null || true)"
fi

# ---- 判定 source type ----
TYPE="$EVENT_NAME"
case "$EVENT_NAME" in
  workflow_dispatch|schedule) TYPE="branch_scan" ;;
esac

# authorAssociation → trust_level 推导（脚本确定性，非 LLM）
derive_trust() {
  local assoc="$1"
  case "$assoc" in
    OWNER|MAINTAINER) echo "maintainer" ;;
    MEMBER)          echo "member" ;;
    COLLABORATOR|CONTRIBUTOR) echo "contributor" ;;
    *)               echo "fork" ;;   # NONE / FIRST_TIMER / FIRST_TIME_CONTRIBUTOR
  esac
}

fetch_pr() {
  local body
  body="$(gh api graphql \
    -F owner="$OWNER" -F name="$NAME" -F number="$PR_NUMBER" \
    -f query='query($owner:String!,$name:String!,$number:Int!) {
      repository(owner:$owner,name:$name){
        pullRequest(number:$number){
          title createdBy{login} authorAssociation
          baseRefName headRefName changedFiles
          commits{ totalCount }
          reviewThreads(first:100){
            nodes{
              isResolved isOutdated path line
              comments(first:100){ nodes { author{login} authorAssociation body } }
            }
          }
        }
      }
    }')"
  printf '%s' "$body"
}

if [ "$TYPE" = "branch_scan" ] && [ -z "$PR_NUMBER" ]; then
  echo "=== 模式: branch_scan ==="
  # git log base..target
  if [ -n "$TARGET_BRANCH" ] && [ -n "$BASE_BRANCH" ]; then
    RANGE="${BASE_BRANCH}...${TARGET_BRANCH}"
  else
    RANGE="HEAD"
  fi
  {
    echo "# Source"
    echo "type: branch_scan"
    echo "repository: $REPO"
    echo "pr: null"
    echo "base: ${BASE_BRANCH:-$TARGET_BRANCH}"
    echo "branch: ${TARGET_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
    echo "trust_level: maintainer"
    echo "fetched_at: $FETCHED_AT"
    echo ""
    echo "---"
    echo ""
    echo "# Git Log"
    git log --no-merges --pretty=format:'- %h %an: %s%n  %b' "origin/${RANGE}" 2>/dev/null \
      | head -c 4000 || true
    echo ""
  } > "$OUT"
  echo "context.md 已生成（branch_scan，$(wc -l < "$OUT") 行）"
  exit 0
fi

# ---- 模式: PR（pull_request_review / pull_request_review_comment）----
echo "=== 模式: PR #${PR_NUMBER} ($TYPE) ==="
PR_JSON="$(fetch_pr)"
PR_TITLE="$(echo "$PR_JSON" | jq -r '.data.repository.pullRequest.title // "?"')"
PR_ASSOC="$(echo "$PR_JSON" | jq -r '.data.repository.pullRequest.authorAssociation // "NONE"')"
TRUST="$(derive_trust "$PR_ASSOC")"
BASE_REF="$(echo "$PR_JSON" | jq -r '.data.repository.pullRequest.baseRefName // ""')"
HEAD_REF="$(echo "$PR_JSON" | jq -r '.data.repository.pullRequest.headRefName // ""')"
CHANGED_FILES="$(echo "$PR_JSON" | jq -r '.data.repository.pullRequest.changedFiles // 0')"
COMMITS="$(echo "$PR_JSON" | jq -r '.data.repository.pullRequest.commits.totalCount // 0')"
CREATED_BY="$(echo "$PR_JSON" | jq -r '.data.repository.pullRequest.createdBy.login // ""')"
IS_FORK="false"; [ "$PR_ASSOC" = "NONE" ] && IS_FORK="true"

{
  echo "# Source"
  echo "type: $TYPE"
  echo "repository: $REPO"
  echo "pr: $PR_NUMBER"
  echo "base: $BASE_REF"
  echo "branch: $HEAD_REF"
  echo "trust_level: $TRUST"
  echo "fetched_at: $FETCHED_AT"
  echo ""
  echo "---"
  echo ""
  echo "# PR Metadata"
  echo "title: $PR_TITLE"
  echo "created_by: $CREATED_BY"
  echo "author_association: $PR_ASSOC"
  echo "changed_files: $CHANGED_FILES"
  echo "commits: $COMMITS"
  echo "base_ref: $BASE_REF"
  echo "head_ref: $HEAD_REF"
  echo "is_fork: $IS_FORK"
  echo ""
  echo "---"
  echo ""
  echo "# Unresolved Review Threads (仅 isResolved=false)"
} > "$OUT"

# 将 JSON 线程转为 markdown（仅未解决）
python3 - "$OUT" "$PR_JSON" <<'PYEOF'
import json, sys
out = sys.argv[1]
raw = json.loads(sys.argv[2])
nodes = raw.get("data", {}).get("repository", {}).get("pullRequest", {}).get("reviewThreads", {}).get("nodes", [])
lines = []
for i, t in enumerate([n for n in nodes if n.get("isResolved") is False], start=1):
    status = "unresolved"
    if t.get("isOutdated"):
        status += "[OUTDATED]"
    lines.append(f"\n## Thread {i}")
    lines.append(f"status: {status}")
    lines.append(f"file: {t.get('path') or ''}")
    lines.append(f"line: {t.get('line') if t.get('line') is not None else 'null'}")
    for c in (t.get("comments") or {}).get("nodes", [])[:10]:
        body = (c.get("body") or "").replace("\r", " ").replace("\n", " ")
        lines.append(f"author: {c['author']['login'] if c.get('author') else '?'} ({c.get('authorAssociation')})")
        lines.append(f"comment: {body[:800]}")
with open(out, "a", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
PYEOF

echo "context.md 已生成（PR #${PR_NUMBER}，$(wc -l < "$OUT") 行）"
