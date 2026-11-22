#!/usr/bin/env bash
# 一键把本仓库推送到 GitHub。
#
# 用法（token 只从环境变量读取，不写入文件、不进 git 历史）：
#   export GITHUB_TOKEN=ghp_xxxxxxxx
#   bash tools/push_to_github.sh
#
# 可选环境变量：
#   GITHUB_OWNER     默认 Lukasmo2013
#   GITHUB_REPO      默认 MiHome-HarmonyOS
#   GITHUB_PRIVATE   默认 true（私有仓库；填 false 则公开）
#   GITHUB_SKIP_CREATE  设为 1 时跳过 API 建仓（仓库已在网页手动创建时用）
#
# 说明：fine-grained token 无法通过 API 创建仓库（403），
#      此时请在网页手动新建空仓库，再用 GITHUB_SKIP_CREATE=1 运行本脚本。
set -euo pipefail

: "${GITHUB_TOKEN:?请先 export GITHUB_TOKEN=github_pat_xxx（不要写进命令行历史）}"
OWNER="${GITHUB_OWNER:-Lukasmo2013}"
REPO="${GITHUB_REPO:-MiHome-HarmonyOS}"
PRIVATE="${GITHUB_PRIVATE:-true}"
SKIP_CREATE="${GITHUB_SKIP_CREATE:-0}"
API="https://api.github.com"

cd "$(dirname "$0")/.."

mask() { sed 's/github_pat_[A-Za-z0-9_]*/<hidden>/g; s/gh[pousr]_[A-Za-z0-9_]*/<hidden>/g'; }

echo "==> 目标仓库：${OWNER}/${REPO}（private=${PRIVATE}）"

# ---------- 0. 推送前隐私复核 ----------
echo "==> 复核敏感文件未被跟踪"
if git ls-files | grep -iE '\.(p12|p7b|cer|pem|key|jks|keystore|csr)$|^signing/|^outputs/|^release/|\.hap$' >/tmp/gh_leak.txt; then
  echo "!! 检测到敏感文件已被跟踪，终止推送："; cat /tmp/gh_leak.txt; exit 1
fi
if git grep -qiE 'keystorePwd|storepass|keyPwd' HEAD -- . ':(exclude)tools/push_to_github.sh' 2>/dev/null; then
  echo "!! 提交内容包含签名口令字段，终止推送"; exit 1
fi
echo "    CLEAN"

# ---------- 1. 仓库是否存在 ----------
code=$(curl -sS -o /tmp/gh_repo.json -w '%{http_code}' \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${API}/repos/${OWNER}/${REPO}")

if [ "$code" = "200" ]; then
  echo "==> 仓库已存在"
elif [ "$SKIP_CREATE" != "1" ]; then
  code=$(curl -sS -o /tmp/gh_create.json -w '%{http_code}' \
    -X POST "${API}/user/repos" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"${REPO}\",\"private\":${PRIVATE},\"description\":\"MiHome - HarmonyOS NEXT 第三方米家客户端\"}")
  if [ "$code" = "201" ]; then
    echo "==> 已创建仓库"
  else
    echo "!! 建仓失败 HTTP ${code}（fine-grained token 无建仓权限）"
    echo "   请在 https://github.com/new?name=${REPO} 手动新建空仓库后，用："
    echo "   GITHUB_SKIP_CREATE=1 bash tools/push_to_github.sh"
    exit 1
  fi
else
  echo "!! 仓库不存在且已跳过建仓，请先在网页新建 ${OWNER}/${REPO}"; exit 1
fi

# ---------- 2. 推送 ----------
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER}/${REPO}.git"

if ! git push -u origin main 2>&1 | mask | tail -20; then
  echo "==> 常规推送被拒绝（远端可能有初始提交），改用强制覆盖"
  git push -u --force origin main 2>&1 | mask | tail -20
fi

# 立即清除 remote 中的 token
git remote set-url origin "https://github.com/${OWNER}/${REPO}.git"

echo "==> 推送完成：https://github.com/${OWNER}/${REPO}"
echo "==> 当前 origin：$(git remote get-url origin)"
