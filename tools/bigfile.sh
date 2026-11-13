#!/usr/bin/env bash
# bigfile.sh - 超 100MB 文件走 GitHub Release 附件（单文件上限 2GB，不占仓库体积）
# 用法:
#   ./tools/bigfile.sh put  <本地文件> [标签]
#   ./tools/bigfile.sh get  <关键字> [输出路径]
#   ./tools/bigfile.sh list
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OWNER="HerlockShelomes"
REPO="file-bridge"
API="https://api.github.com/repos/$OWNER/$REPO"
UPAPI="https://uploads.github.com/repos/$OWNER/$REPO"

# 本地需代理，服务器直连。优先 FILE_BRIDGE_PROXY，其次仓库级 http.proxy。
PROXY="${FILE_BRIDGE_PROXY:-$(git config --get http.proxy || true)}"
CURL_P=()
if [ -n "${PROXY:-}" ]; then CURL_P=(-x "$PROXY"); fi

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p' || true)
fi
[ -n "$TOKEN" ] || { echo "错误: 取不到 GitHub token。设 GH_TOKEN 或先跑 tools/setup-server.sh" >&2; exit 2; }

api() { curl -sS "${CURL_P[@]}" -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

# 从 stdin 的 JSON 按点路径取值
jget() {
  python3 -c '
import sys, json
d = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d = d[int(k)] if k.isdigit() else d[k]
print(d)
' "$1"
}

human() {
  awk -v s="$1" 'BEGIN{
    if (s<1024) printf "%d B", s;
    else if (s<1048576) printf "%.1f KB", s/1024;
    else if (s<1073741824) printf "%.1f MB", s/1048576;
    else printf "%.2f GB", s/1073741824
  }'
}

# 私有仓库的 release 附件不能匿名下载，必须走 assets API。
# 该接口会 302 到 objects.githubusercontent.com，而这个域名经本地代理常握手失败
# （直连反而正常），所以：先取签名 URL，再直连下载，失败回退代理。
fetch_asset() {
  local aid="$1" out="$2" loc
  loc=$(curl -sS "${CURL_P[@]}" -H "Authorization: token $TOKEN" \
        -H "Accept: application/octet-stream" \
        -o /dev/null -w '%{redirect_url}' "$API/releases/assets/$aid") || return 1

  if [ -z "$loc" ]; then
    curl -sSL "${CURL_P[@]}" -H "Authorization: token $TOKEN" \
         -H "Accept: application/octet-stream" -o "$out" -# "$API/releases/assets/$aid"
    return $?
  fi

  if curl -sSL --noproxy '*' -o "$out" -# "$loc" 2>/dev/null; then
    return 0
  fi
  rm -f "$out"
  echo "  直连失败，回退代理重试..." >&2
  curl -sSL "${CURL_P[@]}" -o "$out" -# "$loc"
}

cmd_put() {
  local SRC="$1" LABEL="${2:-}"
  [ -f "$SRC" ] || { echo "错误: 文件不存在: $SRC" >&2; exit 2; }

  local BASE SIZE SHA TAG NAME PAYLOAD JSON REL_ID URL
  BASE=$(basename "$SRC")
  SIZE=$(wc -c < "$SRC" | tr -d ' ')
  SHA=$(sha256sum "$SRC" | awk '{print $1}')
  TAG="blob-$(date +%Y%m%d-%H%M%S)"
  NAME="${LABEL:-$BASE}"

  echo "文件: $BASE  $(human "$SIZE")"
  echo "sha256: $SHA"

  PAYLOAD=$(python3 -c 'import json,sys
print(json.dumps({"tag_name":sys.argv[1],"name":sys.argv[2],
  "body":"sha256:%s | %s bytes | from %s at %s" % (sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6])}))' \
    "$TAG" "$NAME" "$SHA" "$SIZE" "$(hostname)" "$(date -Is)")

  echo "创建 release: $TAG"
  JSON=$(api -X POST "$API/releases" -d "$PAYLOAD")
  REL_ID=$(printf '%s' "$JSON" | jget id 2>/dev/null) || {
    echo "错误: 创建 release 失败:" >&2; printf '%s\n' "$JSON" | head -20 >&2; exit 4; }

  echo "上传附件 (2GB 内可能耗时数分钟)..."
  URL=$(api -X POST "$UPAPI/releases/$REL_ID/assets?name=$BASE" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @"$SRC" -# | jget browser_download_url) || {
    echo "错误: 上传失败" >&2; exit 5; }

  echo
  echo "完成。另一端执行:"
  echo "  ./tools/bigfile.sh get \"$NAME\""
}

cmd_get() {
  local KEY="$1" OUT="${2:-}"
  local ENTRIES
  ENTRIES=$(api "$API/releases?per_page=100" | python3 -c '
import sys, json
key = sys.argv[1].lower()
for r in json.load(sys.stdin):
    hay = (str(r.get("name","")) + " " + str(r.get("tag_name",""))).lower()
    if key and key not in hay:
        continue
    for a in r.get("assets", []):
        print("%s\t%s\t%s\t%s\t%s" % (
            r.get("name",""), a.get("name",""), a.get("size",0),
            a.get("id",""), r.get("body","").replace("\t"," ")))
' "$KEY")

  [ -n "$ENTRIES" ] || { echo "没有匹配 \"$KEY\" 的大文件" >&2; exit 6; }

  local N TOTAL
  N=$(printf '%s\n' "$ENTRIES" | wc -l)
  echo "匹配到 $N 个附件:"
  printf '%s\n' "$ENTRIES" | while IFS=$'\t' read -r rn an asz aid body; do
      printf '  %-40s %10s   [%s]\n' "$an" "$(human "$asz")" "$rn"
    done

  local A_NAME A_SIZE A_ID A_BODY
  IFS=$'\t' read -r _ A_NAME A_SIZE A_ID A_BODY <<< "$(printf '%s\n' "$ENTRIES" | head -1)"

  if [ -z "$OUT" ]; then OUT="$ROOT/downloads/$A_NAME"; fi
  mkdir -p "$(dirname "$OUT")"

  echo
  echo "下载 $A_NAME ($(human "$A_SIZE"))  ->  $OUT"
  fetch_asset "$A_ID" "$OUT" || { echo "错误: 下载失败" >&2; exit 8; }

  local WANT GOT
  WANT=$(printf '%s' "$A_BODY" | sed -n 's/.*sha256:\([0-9a-f]\{64\}\).*/\1/p')
  GOT=$(sha256sum "$OUT" | awk '{print $1}')
  echo "sha256 实际: $GOT"
  if [ -n "$WANT" ]; then
    echo "sha256 期望: $WANT"
    if [ "$WANT" = "$GOT" ]; then echo "校验通过"; else echo "校验失败: 文件损坏" >&2; exit 7; fi
  fi
}

cmd_list() {
  api "$API/releases?per_page=100" | python3 -c '
import sys, json
rows = []
for r in json.load(sys.stdin):
    for a in r.get("assets", []):
        rows.append((r.get("name",""), a.get("name",""), a.get("size",0)))
if not rows:
    print("（空）")
for n, an, sz in rows:
    print("  %-32s %-38s %8.1f MB" % (n, an, sz/1048576))
'
}

case "${1:-}" in
  put)  shift; [ $# -ge 1 ] || { echo "用法: $0 put <文件> [标签]" >&2; exit 2; }; cmd_put "$@" ;;
  get)  shift; [ $# -ge 1 ] || { echo "用法: $0 get <关键字> [输出路径]" >&2; exit 2; }; cmd_get "$@" ;;
  list) cmd_list ;;
  *) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
