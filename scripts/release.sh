#!/usr/bin/env bash
# 发布到 GitHub：推送当前分支 + 打版本标签（仅当仓库变量 USE_CLOUD_RELEASE=true 时才会跑云端构建）。
#
# 更推荐（本机构建 + 自动上传 Release）：npm run release:local → scripts/release-local-gh.sh
#
# 用法：
#   1. 只改下面 「可配置」 区域的 VERSION、COMMIT_MSG、BRANCH
#   2. 在仓库根目录执行其一：
#        npm run release
#        bash scripts/release.sh
#        ./scripts/release.sh
#
# 前提：已配置远程 origin。
# CI 发版：仓库需配置 workflow 注释中的 Secrets（含 App Store Connect API，见 release-macos.yml）。
# 若无 API 密钥 / CI 签名失败：勿依赖「推 tag 自动出包」；请在本地 Xcode 或 xcodebuild 打好 .app 后，
#   用 GitHub 网页在对应 Release 里上传 zip，或本机已登录 gh 时执行：
#   gh release upload "$VERSION" ./MiniTools-SwiftUI-"$VERSION".zip --clobber

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ======================== 可配置（每次发版只改这里） ========================
VERSION="v1.0.8"
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
