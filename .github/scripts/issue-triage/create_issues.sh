#!/usr/bin/env bash
# create_issues.sh — Issue Triage 执行器（Trusted Executor）
#
# 职责（ADR-0025 D4/D5/D6/D7）：对 validate_findings.py 已通过的 findings.json 执行
#   1) 白名单校验（标签/mention，D4）
#   2) 置信度三态 + trust 覆盖（D5）
#   3) fingerprint 确定性去重（D6）＋ history 更新（artifact workflow state）
#   4) gh issue create / PR 回帖建议；DRY_RUN=1 时零 GitHub 副作用
# 绝不产生任何代码仓库文件写入（零 contents:write）。
#
# 环境变量：
#   FINDINGS / HISTORY_IN / HISTORY_OUT / DRY_RUN / GH_MOCK
#   HIGH_THRESHOLD / MED_THRESHOLD / REPO / PR_NUMBER / MENTION_WHITELIST
set -euo pipefail

# ---------- 常量（白名单，D4）----------
LABEL_MAP_bug="bug"
LABEL_MAP_security="security"
LABEL_MAP_performance="performance"
LABEL_MAP_tech_debt="tech-debt"
LABEL_MAP_refactor="refactor"
LABEL_MAP_feature_request="enhancement"
LABEL_MAP_documentation="documentation"

# ---------- 参数 ----------
: "${FINDINGS:=.tmp/issue-triage/findings.json}"
: "${HISTORY_IN:=}"
: "${HISTORY_OUT:=.tmp/issue-triage/history.json}"
: "${DRY_RUN:=0}"
: "${GH_MOCK:=0}"
# 归一化：workflow 经 env 传入的是布尔型字符串 "true"/"false"，
# 下方守卫（[ "$DRY_RUN" = "1" ] / [ "$DRY_RUN" = "0" ]）只认整数形态。
# 若不做归一化，DRY_RUN="true" 既不等于 "1" 也不等于 "0"：
#   - dry-run 安全网失效 → "true" 落到 else 分支直接走真实写路径（误建 Issue）
#   - PR 回帖守卫（= "0"）永不被触发
# 统一映射为 1/0，消除上述歧义。
case "$DRY_RUN" in
  true|1) DRY_RUN=1 ;;
  *)      DRY_RUN=0 ;;
esac
case "$GH_MOCK" in
  true|1) GH_MOCK=1 ;;
  *)      GH_MOCK=0 ;;
esac
: "${HIGH_THRESHOLD:=0.8}"
: "${MED_THRESHOLD:=0.5}"
: "${REPO:=Thy985/fixmath}"
: "${PR_NUMBER:=}"
: "${MENTION_WHITELIST:=Thy985}"

if [ ! -f "$FINDINGS" ]; then
  echo "FATAL: findings.json 不存在: $FINDINGS" >&2
  exit 1
fi

# ---------- 辅助 ----------
log() { printf '%s\n' "$*"; }

# fingerprint = sha256(category-component-root_cause)[:16]（D6，脚本确定性）
fingerprint() {
  local key="$1-$2-$3"
  printf '%s' "$key" | sha256sum | cut -c1-16
}

# 置信度三态 + trust 覆盖（D5）：create|suggest|drop
decision() {
  local c="$1" trust="$2"
  if [ "$trust" = "contributor" ] || [ "$trust" = "fork" ]; then
    echo "suggest"   # 外部来源：任何 confidence 都不自动创建
  elif awk -v c="$c" -v hi="$HIGH_THRESHOLD" 'BEGIN{exit !(c>=hi)}'; then
    echo "create"
  elif awk -v c="$c" -v med="$MED_THRESHOLD" 'BEGIN{exit !(c>=med)}'; then
    echo "suggest"
  else
    echo "drop"
  fi
}

mention_whitelist() {
  if [ "$GH_MOCK" = "1" ]; then
    printf '%s' "$MENTION_WHITELIST"
    return
  fi
  {
    gh api "repos/$REPO/contributors" --paginate --jq '.[].login' 2>/dev/null || true
    printf '%s\n' "$MENTION_WHITELIST" | tr ' ' '\n'
  } | sort -u
}

label_exists() { gh label list -R "$REPO" --json name --jq '.[].name' 2>/dev/null | grep -qx "$1"; }
ensure_label() {
  [ "$GH_MOCK" = "1" ] && return 0
  if ! label_exists "$1"; then
    gh label create "$1" -R "$REPO" --color "c2e0c6" --description "issue-triage auto" >/dev/null 2>&1 || true
  fi
}

# 已开 Issue 标题近似命中 → 视为重复（D6 第二步）
# 必须在主循环调用前定义（bash 运行时解析）
title_exists() {
  [ "$GH_MOCK" = "1" ] && return 1
  local q="$1" n
  n="$(gh issue list -R "$REPO" --state open --search "in:title \"$q\"" --json number --jq 'length' 2>/dev/null || echo 0)"
  [ "$n" -gt 0 ]
}


# ---------- 读取 source 上下文 ----------
TRUST_LEVEL="$(jq -r '.source.trust_level // "maintainer"' "$FINDINGS")"
SRC_TYPE="$(jq -r '.source.type // ""' "$FINDINGS")"
[ -z "$PR_NUMBER" ] && PR_NUMBER="$(jq -r '.source.pr // empty' "$FINDINGS")"
SRC_REF="PR #${PR_NUMBER}"
[ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ] && SRC_REF="branch scan"

log "=== 执行器：repo=$REPO trust=$TRUST_LEVEL 类型=$SRC_TYPE DRY_RUN=$DRY_RUN ==="
log "阈值：HIGH=$HIGH_THRESHOLD MED=$MED_THRESHOLD"

# ---------- 加载上一 run 的去重记忆（D6）----------
declare -A SEEN
mkdir -p "$(dirname "$HISTORY_OUT")"
RECORDS_TMP="$(mktemp)"
HIST_SAFE=0
if [ -n "$HISTORY_IN" ] && [ -f "$HISTORY_IN" ]; then
  HIST_SAFE=1
  while IFS= read -r fp; do
    [ -n "$fp" ] && SEEN["$fp"]=1
  done < <(jq -r '.[].fingerprint // empty' "$HISTORY_IN")
  log "已加载上一 run 记忆：$(jq 'length' "$HISTORY_IN") 条"
else
  log "无上一 run 记忆（首次或工件过期）"
fi

# 正在本 run 新建的指纹（避免同 run 重复）
declare -A SEEN_RUN

MENTION_OK="$(mention_whitelist)"
log "mention 白名单：$(echo "$MENTION_OK" | tr '\n' ' ')"

# ---------- 主循环 ----------
COUNT="$(jq '.findings | length' "$FINDINGS")"
CREATED=0
SUGGESTIONS=""
SUMMARY=""
for ((i=0; i<COUNT; i++)); do
  cat="$(jq -r ".findings[$i].category" "$FINDINGS")"
  comp="$(jq -r ".findings[$i].component // \"\"" "$FINDINGS")"
  root="$(jq -r ".findings[$i].root_cause // \"\"" "$FINDINGS")"
  conf="$(jq -r ".findings[$i].confidence" "$FINDINGS")"
  sev="$(jq -r ".findings[$i].severity // \"low\"" "$FINDINGS")"
  prio="$(jq -r ".findings[$i].priority // \"low\"" "$FINDINGS")"
  # 去除 title 中的换行，防注入
  title="$(jq -r ".findings[$i].title // \"\"" "$FINDINGS" | tr '\n\r' ' ' | sed 's/  */ /g')"
  body="$(jq -r ".findings[$i].body // \"\"" "$FINDINGS")"
  src_ref="$(jq -r ".findings[$i].source_ref // \"\"" "$FINDINGS")"

  # 标签白名单（D4）— 间接展开动态变量名
  _lvar="LABEL_MAP_${cat//-/_}"
  label="${!_lvar:-}"
  if [ -z "$label" ]; then
    log "  ✗ findings[$i] category 无映射标签（$cat），跳过"
    continue
  fi
  # security 强制入人工视野（D3）：仍走 decision，但记 priority
  [ "$cat" = "security" ] && log "  (security) severity=$sev priority=$prio → 入人工视野"

  fp="$(fingerprint "$cat" "$comp" "$root")"
  DUP=""
  if [ -n "${SEEN[$fp]:-}" ] || [ -n "${SEEN_RUN[$fp]:-}" ]; then
    DUP="duplicate-of"
  elif title_exists "$title"; then
    DUP="title-match open issue"
  fi

  if [ -n "$DUP" ]; then
    log "  ✗ [$fp] 去重命中（$DUP）：$title"
    SUMMARY="$SUMMARY
- (dup) $title [$cat]"
    continue
  fi

  DEC="$(decision "$conf" "$TRUST_LEVEL")"
  # mention 白名单（D4）
  MENTIONS=""
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    if echo "$MENTION_OK" | grep -qx "$m"; then
      MENTIONS="$MENTIONS $m"
    fi
  done < <(jq -r ".findings[$i].mentions[]? // empty" "$FINDINGS")
  CC_LINE=""
  if [ -n "$MENTIONS" ]; then
    CC_LINE="
CC: $(printf '%s\n' $MENTIONS | sed 's/^/@/' | tr '\n' ' ' | sed 's/ $//')"
  fi

  case "$DEC" in
    create)
      ensure_label "$label"
      ISSUE_BODY="$body

---
*来源: $src_ref · category=$cat · severity=$sev · priority=$prio · confidence=$conf · fingerprint=\`$fp\`*$CC_LINE"
      if [ "$DRY_RUN" = "1" ] || [ "$GH_MOCK" = "1" ]; then
        log "  [dry/mock] 将创建 Issue: $title  (label=$label, conf=$conf)"
        ISSUE_ID="MOCK-$i"
      else
        ISSUE_ID="$(gh issue create -R "$REPO" --title "$title" --body "$ISSUE_BODY" --label "$label" | grep -oE '[0-9]+$')"
        log "  ✓ 已创建 Issue #$ISSUE_ID: $title"
      fi
      CREATED=$((CREATED+1))
      SEEN_RUN["$fp"]=1
      DEAD="create"
      ;;
    suggest)
      log "  ~ 建议（conf=$conf, trust=$TRUST_LEVEL）: $title"
      SUGGESTIONS="$SUGGESTIONS
- [c=$conf] $title  (label=$label, $src_ref)"
      DEAD="suggest"
      ISSUE_ID=""
      ;;
    *)
      log "  · 丢弃（conf=$conf 过低）: $title"
      DEAD="drop"
      ISSUE_ID=""
      ;;
  esac

  printf '{"fingerprint":"%s","issue_id":%s,"key_title":"%s","source":"%s","trust_level":"%s","created_at":"%s","created_issue":%s,"decision":"%s"}\n' \
    "$fp" "${ISSUE_ID:-null}" "$title" "$SRC_REF" "$TRUST_LEVEL" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$([ "$DEC" = "create" ] && echo true || echo false)" "$DEAD" >> "$RECORDS_TMP"
done

# ---------- 合并 history（D6，JSON-lines → 数组）----------
if [ "$HIST_SAFE" = "1" ]; then
  { jq -c '.[]' "$HISTORY_IN"; cat "$RECORDS_TMP"; } | jq -s '.' > "${HISTORY_OUT}.tmp"
else
  jq -s '.' "$RECORDS_TMP" > "${HISTORY_OUT}.tmp" 2>/dev/null \
    || printf '[]\n' > "${HISTORY_OUT}.tmp"
fi
mv "${HISTORY_OUT}.tmp" "$HISTORY_OUT"
rm -f "$RECORDS_TMP"

log "=== 结果：created=$CREATED | suggestions=$(printf '%s' "$SUGGESTIONS" | grep -c '^- ' || true) ==="

# ---------- PR 回帖（Medium 建议，D5）----------
if [ -n "$SUGGESTIONS" ] && [ -n "$PR_NUMBER" ] && [ "$DRY_RUN" = "0" ] && [ "$GH_MOCK" = "0" ]; then
  MSG="### 🤖 Issue Triage 建议（未自动创建）
以下为中等置信度/外部来源建议，供维护者决定：
$SUGGESTIONS"
  gh pr comment "$PR_NUMBER" -R "$REPO" --body "$MSG" >/dev/null 2>&1 || true
  log "已回帖 PR #$PR_NUMBER 建议清单"
fi

if [ "$DRY_RUN" = "1" ]; then
  log "DRY-RUN：未执行任何写操作（不建 Issue / 不回帖 / 不上传 history 工件）"
fi
