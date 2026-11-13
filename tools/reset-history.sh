#!/usr/bin/env bash
# reset-history.sh - 清空中转目录并把 git 历史压缩成单个 commit（中转站用久了体积膨胀时使用）
# 注意: 会强推，另一端下次必须 `git reset --hard origin/main`
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
BEFORE=$(du -sh .git 2>/dev/null | cut -f1)

echo "仓库: $ROOT"
echo "分支: $BRANCH"
echo ".git 当前体积: $BEFORE"
echo
echo "将执行:"
echo "  1. 删除 from-local/ 与 from-server/ 下所有已传文件（保留 .gitkeep）"
echo "  2. 用 orphan commit 重建历史（旧历史作废）"
echo "  3. 强推 origin/$BRANCH"
echo "  4. 清理本地 .git 垃圾对象"
echo
echo "另一端（服务器/本地）下次必须: git fetch && git reset --hard origin/$BRANCH"

read -r -p "输入 yes 继续: " ans
[ "$ans" = "yes" ] || { echo "已取消"; exit 1; }

find from-local from-server -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
touch from-local/.gitkeep from-server/.gitkeep

git checkout -q --orphan "__clean_$$"
git add -A
git commit -q -m "reset: 清空中转目录，历史归零 ($(date +%Y-%m-%d))"

git branch -D "$BRANCH" >/dev/null 2>&1 || true
git branch -m "$BRANCH"
git push -q -f origin "$BRANCH"

git reflog expire --expire=now --all 2>/dev/null || true
git gc --prune=now --quiet 2>/dev/null || true

echo
echo "完成。HEAD=$(git rev-parse --short HEAD)  .git=$(du -sh .git | cut -f1)"
echo "提醒: 另一端执行 git fetch && git reset --hard origin/$BRANCH"
