#!/usr/bin/env bash
# setup-server.sh - 服务器端一次性配置，clone 后在本仓库根目录执行
# token 来源优先级: 环境变量 GH_TOKEN > 已有的凭据文件 > 交互输入
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CRED_FILE="${FILE_BRIDGE_CRED:-/data/xyfang/.git-credentials}"
mkdir -p "$(dirname "$CRED_FILE")"

TOKEN="${GH_TOKEN:-}"
if [ -z "$TOKEN" ] && [ ! -s "$CRED_FILE" ]; then
  printf 'GitHub token (repo scope): '
  read -rs TOKEN
  echo
fi

if [ -n "$TOKEN" ]; then
  printf 'https://HerlockShelomes:%s@github.com\n' "$TOKEN" > "$CRED_FILE"
  chmod 600 "$CRED_FILE"
  echo "凭据写入 $CRED_FILE (权限 600)"
fi

git config --global credential.helper "store --file=$CRED_FILE"
git config --global core.autocrlf false
git config --global pull.rebase true
git config --global user.name "HerlockShelomes"
git config --global user.email "xiaoyangfang4ever@163.com"

chmod +x "$ROOT/tools/"*.sh 2>/dev/null || true

echo "配置完成"
echo "  credential.helper = $(git config --global --get credential.helper)"
echo "  仓库路径          = $ROOT"
