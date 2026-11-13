#!/usr/bin/env bash
# pull.sh - 拉取另一端推送的改动
# 用法: ./tools/pull.sh [--dry]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY=0
[ "${1:-}" = "--dry" ] && DRY=1

BRANCH=$(git rev-parse --abbrev-ref HEAD)
git fetch -q origin "$BRANCH"

LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
  echo "已是最新，没有新内容 (HEAD=$(git rev-parse --short HEAD))"
  exit 0
fi

echo "=== 新增提交 ==="
git --no-pager log --oneline "$LOCAL_HEAD..origin/$BRANCH" | head -20

echo
echo "=== 变化文件 ==="
git --no-pager diff --stat "$LOCAL_HEAD" "origin/$BRANCH"

if [ "$DRY" = "1" ]; then
  echo
  echo "(--dry: 只列不落地)"
  exit 0
fi

# 中转站通常不该有本地未提交改动；有则自动 stash
git pull -q --rebase --autostash origin "$BRANCH"

echo
echo "已更新 -> $(git rev-parse --short HEAD)"
echo "文件位置: $ROOT/from-local  (服务器发来的)"
echo "          $ROOT/from-server (本地发来的)"
