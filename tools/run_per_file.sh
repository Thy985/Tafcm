#!/usr/bin/env bash
# 方案 A：按文件粒度拆分 matrix —— 逐文件构建 APK + 上传 Test Lab + 记录 matrix ID
# 用法: bash run_per_file.sh <文件列表> <输出记录文件>
# 每个文件: patrol build android --target <file> → gcloud 上传 → 记录 "file|matrix_id"

set -u

GCLOUD="D:/ProgramFiles/Google/google-cloud-sdk/bin/gcloud.cmd"
PATROL="D:/pub-cache/bin/patrol.bat"
APP="D:/Projects/Active/math2/flutter_app/build/app/outputs/apk/debug/app-debug.apk"
TEST_APK="D:/Projects/Active/math2/flutter_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
FLUTTER_DIR="D:/Projects/Active/math2/flutter_app"
OUT_FILE="$2"
MATRIX_IDS=()

export HTTPS_PROXY=http://127.0.0.1:7897
export HTTP_PROXY=http://127.0.0.1:7897
export CLOUDSDK_CORE_PROJECT=tafcm-ecd22

: > "$OUT_FILE"

run_one() {
  local target="$1"
  # 脚本已在 FLUTTER_DIR（flutter_app）内构建，target 需为相对该目录的路径
  local name
  name=$(basename "$target" .dart)
  echo "[$(date +%H:%M:%S)] === Building $target ==="

  # 1. patrol build（每个文件单独构建）
  (cd "$FLUTTER_DIR" && "$PATROL" build android --target "${target#flutter_app/}" > "/tmp/build_${name}.log" 2>&1)
  local build_rc=$?
  if [ $build_rc -ne 0 ]; then
    echo "[$(date +%H:%M:%S)] BUILD FAILED for $target (rc=$build_rc)"
    echo "$name|BUILD_FAILED" >> "$OUT_FILE"
    return 1
  fi

  # 2. gcloud 上传（async，等待 matrix ID）
  echo "[$(date +%H:%M:%S)] Uploading $target ..."
  local up_log="/tmp/upload_${name}.log"
  rm -f "$up_log"
  "$GCLOUD" firebase test android run \
    --type instrumentation \
    --app "$APP" \
    --test "$TEST_APK" \
    --device model=CPH2449,version=34 \
    --timeout 15m \
    --async > "$up_log" 2>&1

  local matrix_id
  matrix_id=$(grep -oE "matrix-[a-z0-9]+" "$up_log" | head -1)
  if [ -z "$matrix_id" ]; then
    echo "[$(date +%H:%M:%S)] UPLOAD FAILED for $target"
    echo "$name|UPLOAD_FAILED" >> "$OUT_FILE"
    tail -5 "$up_log"
    return 1
  fi

  echo "[$(date +%H:%M:%S)] $target → $matrix_id"
  echo "$name|$matrix_id" >> "$OUT_FILE"
  MATRIX_IDS+=("$matrix_id")
  return 0
}

while IFS= read -r file; do
  [ -z "$file" ] && continue
  run_one "$file"
done < "$1"

echo ""
echo "=== 全部完成，matrix 记录 ==="
cat "$OUT_FILE"
