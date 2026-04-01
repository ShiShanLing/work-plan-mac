#!/usr/bin/env bash
# 本地 Release：用本机 Xcode 钥匙串签名构建 → 打成 zip → 通过 GitHub CLI 创建 Release（无需网页上传）。
#
# 前提：
#   brew install gh && gh auth login（能操作本仓库的 contents 权限即可）
#   本机已能像 ⌘B 一样正常签 Release（自动签名 + 已登录 Apple ID）
#
# 用法（仓库根目录）：
#   npm run release:local
#   bash scripts/release-local-gh.sh
#
# 说明：推送到 GitHub 的 tag + Release 由 gh 创建；请把仓库变量 USE_CLOUD_RELEASE 关掉（勿设为 true），
#       否则 tag 仍会触发云端 workflow（见 .github/workflows/release-macos.yml）。
# 产物目录：**仅清空本机 package/**（删除本地旧 .app / zip / sha256，只保留当次构建）；GitHub 上已有 Release **不会删除**。
# 若 VERSION 对应的 Release 已在 GitHub 存在，脚本会报错退出，请改用新版本号。

set -euo pipefail

# IDE / npm 启动的环境有时不带 Homebrew，导致已安装的 gh 找不到
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 旧版脚本可能把 zip 留在仓库根目录，一并清掉，避免与本机「只保留当前包」混淆
rm -f "$ROOT"/MiniTools-SwiftUI-v*.zip "$ROOT"/MiniTools-SwiftUI-v*.zip.sha256 2>/dev/null || true

# ======================== 可配置（每次发版只改这里） ========================
VERSION="v1.0.9"
COMMIT_MSG="github 打包错误问题处理"
BRANCH="dev"
# ==========================================================================

if [[ ! "$VERSION" =~ ^v[0-9] ]]; then
  echo "错误: VERSION 必须以 v 开头，例如 v1.0.8"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "错误: 未找到 GitHub CLI（gh）。请任选其一："
  echo "  1) brew install gh"
  echo "  2) 打开 https://cli.github.com 下载 macOS 安装包"
  echo "  安装后在终端执行: gh auth login"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "错误: gh 未登录。请执行: gh auth login"
  exit 1
fi

git add -A
if git diff --cached --quiet; then
  echo "提示: 工作区无新提交，跳过 commit。"
else
  git commit -m "$COMMIT_MSG"
fi

DERIVED="$ROOT/build/ReleaseDerived"
rm -rf "$DERIVED"
mkdir -p "$ROOT/build"

echo ">>> xcodebuild Release（使用本机签名；成功后再 push / 发 Release）…"
set -o pipefail
xcodebuild \
  -scheme MiniTools-SwiftUI \
  -project MiniTools-SwiftUI.xcodeproj \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  build | tee "$ROOT/build/last-local-release-xcodebuild.log"

APP="$(find "$DERIVED" -name 'MiniTools-SwiftUI.app' -type d | head -1)"
if [[ -z "$APP" ]] || [[ ! -d "$APP" ]]; then
  echo "错误: 未找到 MiniTools-SwiftUI.app，请查看 build/last-local-release-xcodebuild.log"
  exit 1
fi

# 安装包统一放在 package/：每次发版先清空，仅保留当前构建
PKGDIR="$ROOT/package"
rm -rf "$PKGDIR"
mkdir -p "$PKGDIR"

APP_IN_PKG="$PKGDIR/MiniTools-SwiftUI.app"
ditto "$APP" "$APP_IN_PKG"

ZIP="$PKGDIR/MiniTools-SwiftUI-${VERSION}.zip"
ditto -c -k --keepParent "$APP_IN_PKG" "$ZIP"
SHASUM="$PKGDIR/MiniTools-SwiftUI-${VERSION}.zip.sha256"
shasum -a 256 "$ZIP" | tee "$SHASUM"

git push origin "$BRANCH"

if gh release view "$VERSION" >/dev/null 2>&1; then
  echo "错误: GitHub 上已存在 Release $VERSION。为保留线上历史版本，本脚本不会删除旧 Release。"
  echo "请把脚本里的 VERSION 改为新版本号（例如 v1.0.10）后再执行。"
  exit 1
fi

echo ">>> 创建 GitHub Release 并上传 zip / checksum…"
gh release create "$VERSION" \
  "$ZIP" \
  "$SHASUM" \
  --target "$BRANCH" \
  --title "$VERSION" \
  --generate-notes \
  --latest

echo ""
echo "已完成: 本机安装包目录 $PKGDIR（.app + zip + sha256）；GitHub Releases 可下载 $VERSION。"
