#!/usr/bin/env bash
# 发布到 GitHub：推送当前分支 + 打版本标签（触发 Actions 构建 Release 安装包）。
#
# 用法：
#   1. 只改下面 「可配置」 区域的 VERSION、COMMIT_MSG、BRANCH
#   2. 在仓库根目录执行其一：
#        npm run release
#        bash scripts/release.sh
#        ./scripts/release.sh
#
# 前提：已配置远程 origin；GitHub 上已设好签名相关 Secrets（见 .github/workflows/release-macos.yml 注释）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ======================== 可配置（每次发版只改这里） ========================
VERSION="v1.0.7"
COMMIT_MSG="github 打包错误问题处理"
BRANCH="dev"
# ==========================================================================

if [[ ! "$VERSION" =~ ^v[0-9] ]]; then
  echo "错误: VERSION 必须以 v 开头，例如 v1.0.6"
  exit 1
fi

if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "错误: 本地已存在标签 $VERSION。请改用新版本号，或先执行: git tag -d $VERSION"
  exit 1
fi

git add -A

if git diff --cached --quiet; then
  echo "提示: 没有新的变更需要提交，将直接推送分支并创建标签 $VERSION。"
else
  git commit -m "$COMMIT_MSG"
fi

git push origin "$BRANCH"

git tag "$VERSION"
git push origin "$VERSION"

echo ""
echo "已完成: 分支 $BRANCH 已推送，标签 $VERSION 已推送。"
echo "请到 GitHub → Actions 查看构建，→ Releases 下载 zip。"
