#!/usr/bin/env bash
# send.sh - 把文件放进中转目录并推送到 GitHub
# 用法: ./tools/send.sh <源文件> <local|server> [备注]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIMIT=$((100 * 1024 * 1024))

if [ $# -lt 2 ]; then
  echo "用法: $0 <源文件> <local|server> [备注]" >&2
  exit 2
fi

SRC="$1"
SIDE="$2"
NOTE="${3:-}"

[ -e "$SRC" ] || { echo "错误: 源文件不存在: $SRC" >&2; exit 2; }
[ -f "$SRC" ] || { echo "错误: 只支持单个文件，目录请先打包" >&2; exit 2; }

case "$SIDE" in
  local)  DEST_DIR="$ROOT/from-local"  ;;
  server) DEST_DIR="$ROOT/from-server" ;;
  *) echo "错误: 第二参数必须是 local 或 server（当前: $SIDE）" >&2; exit 2 ;;
esac

SIZE=$(wc -c < "$SRC" | tr -d ' ')
HUMAN=$(awk -v s="$SIZE" 'BEGIN{ if(s<1024) printf "%d B",s; else if(s<1048576) printf "%.1f KB",s/1024; else if(s<1073741824) printf "%.1f MB",s/1048576; else printf "%.2f GB",s/1073741824 }')

if [ "$SIZE" -gt "$LIMIT" ]; then
  echo "错误: 文件 ${HUMAN} 超过 GitHub 单文件 100 MB 上限" >&2
  echo "改用大文件通道: $ROOT/tools/bigfile.sh put \"$SRC\" \"${NOTE:-文件名}\"" >&2
  exit 3
fi

BASE=$(basename "$SRC")
STAMP=$(date +%Y%m%d-%H%M%S)
DEST="$DEST_DIR/${STAMP}__${BASE}"

mkdir -p "$DEST_DIR"
cp -f "$SRC" "$DEST"
echo "复制 -> ${DEST#$ROOT/}  (${HUMAN})"

cd "$ROOT"
git add -A
if git diff --cached --quiet; then
  echo "无实际改动，跳过提交"
  exit 0
fi

MSG="send($SIDE): ${BASE} (${HUMAN})"
[ -n "$NOTE" ] && MSG="$MSG - $NOTE"
git commit -q -m "$MSG"

# 国内直连 GitHub 的 TLS 连接偶发中断，推 5 次
PUSH_OK=0
for i in 1 2 3 4 5; do
  if git push -q origin HEAD 2>"$ROOT/.push_err"; then PUSH_OK=1; break; fi
  echo "push 失败（第 $i/5 次），3 秒后重试:" >&2
  tail -2 "$ROOT/.push_err" >&2
  sleep 3
done
rm -f "$ROOT/.push_err"
[ "$PUSH_OK" = "1" ] || { echo "错误: 连续 5 次推送失败（提交已在本地）。网络恢复后手动 git push origin HEAD" >&2; exit 4; }

echo "已推送 $(git rev-parse --short HEAD)"
echo "另一端执行: ./tools/pull.sh"
