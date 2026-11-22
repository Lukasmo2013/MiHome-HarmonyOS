#!/usr/bin/env bash
# 一键把本仓库推送到 GitHub。
#
# 用法（token 只从环境变量读取，不写入文件、不进 git 历史）：
#   export GITHUB_TOKEN=ghp_xxxxxxxx
#   bash tools/push_to_github.sh
#
# 可选环境变量：
#   GITHUB_OWNER    默认 annst
#   GITHUB_REPO     默认 MiHome-HarmonyOS
#   GITHUB_PRIVATE  默认 true（私有仓库；填 false 则公开）
#
# Token 需要权限：repo（私有仓库还需 workflow 若含 Actions）。
# 生成地址：https://github.com/settings/tokens
set -euo pipefail

: "${GITHUB_TOKEN:?请先 export GITHUB_TOKEN=ghp_xxx（不要写进命令行历史）}"
OWNER="${GITHUB_OWNER:-annst}"
REPO="${GITHUB_REPO:-MiHome-HarmonyOS}"
PRIVATE="${GITHUB_PRIVATE:-true}"

cd "$(dirname "$0")/.."

echo "==> 目标仓库：${OWNER}/${REPO}（private=${PRIVATE}）"

# 1. 创建仓库；已存在时 GitHub 返回 422，忽略
code=$(curl -sS -o /tmp/gh_create.json -w '%{http_code}' \
  -X POST https://api.github.com/user/repos \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -d "{\"name\":\"${REPO}\",\"private\":${PRIVATE},\"description\":\"MiHome - HarmonyOS NEXT 第三方米家客户端\"}")
if [ "$code" = "201" ]; then
  echo "==> 已创建仓库"
elif [ "$code" = "422" ]; then
  echo "==> 仓库已存在，直接推送"
else
  echo "!! 创建仓库失败 HTTP ${code}"; cat /tmp/gh_create.json; exit 1
fi

# 2. 推送（token 只出现在本次进程的 remote URL 中，推完立即移除）
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER}/${REPO}.git"
git push -u origin main
git remote set-url origin "https://github.com/${OWNER}/${REPO}.git"

echo "==> 推送完成：https://github.com/${OWNER}/${REPO}"
echo "==> 已移除 remote 中的 token，当前 origin：$(git remote get-url origin)"
