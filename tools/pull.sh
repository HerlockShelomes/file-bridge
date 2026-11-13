#!/usr/bin/env bash
# pull.sh - 拉取另一端推送的改动
# 用法: ./tools/pull.sh [--dry]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY=0
[ "${1:-}" = "--dry" ] && DRY=1

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 国内直连 GitHub 的 TLS 连接偶发中断（GnuTLS -110 / schannel reset），必须重试
FETCH_OK=0
for i in 1 2 3 4 5; do
  if git fetch -q origin "$BRANCH" 2>"$ROOT/.fetch_err"; then FETCH_OK=1; break; fi
  echo "fetch 失败（第 $i/5 次），3 秒后重试:" >&2
  tail -2 "$ROOT/.fetch_err" >&2
  sleep 3
done
rm -f "$ROOT/.fetch_err"
[ "$FETCH_OK" = "1" ] || { echo "错误: 连续 5 次拉取失败，检查网络或代理设置" >&2; exit 1; }

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
echo "  from-local/   本地 -> 服务器   放本地投递的文件"
echo "  from-server/  服务器 -> 本地   放服务器投递的文件"
