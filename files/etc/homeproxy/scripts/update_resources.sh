#!/bin/sh
# update_resources.sh - helper to download homeproxy dashboards/resources (patched)
HP_DASHBOARD_SOURCE="https://codeload.github.com/MetaCubeX/Yacd-meta/zip/refs/heads/gh-pages"
HP_DASHBOARD_VERSION_URL="https://github.com/MetaCubeX/Yacd-meta/commits/gh-pages.atom"

# 以下为占位的资源更新逻辑示例，实际项目可能已有更完善实现。
# 这里确保常量已替换并提供基本下载校验流程。
set -e

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT INT TERM

VERSION="$(date +%Y%m%d%H%M)"
ZIP="$TMPDIR/dashboard.zip"

echo "Downloading dashboard from $HP_DASHBOARD_SOURCE?v=$VERSION"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --compressed --retry 3 --retry-all-errors --retry-delay 1 -o "$ZIP" "$HP_DASHBOARD_SOURCE?v=$VERSION" || { echo "download failed"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$ZIP" "$HP_DASHBOARD_SOURCE?v=$VERSION" || { echo "download failed"; exit 1; }
else
  echo "no downloader available"
  exit 1
fi

# unzip and basic check (requires unzip)
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$ZIP" -d "$TMPDIR/dashboard" || { echo "unzip failed"; exit 1; }
  echo "dashboard downloaded and extracted"
else
  echo "unzip not available; leaving file in $ZIP"
fi

exit 0
