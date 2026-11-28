#!/bin/bash
# ZN-PPE：构建前硬校验，任一不满足即中止（避免编出缺插件/版本不符的固件）
set -e

fail() { echo "ZN-PPE CHECK FAILED: $*" >&2; exit 1; }

#插件目录与包名
grep -q '^PKG_NAME:=luci-app-homeproxy' ./package/luci-app-homeproxy-pro/Makefile || fail "homeproxy-pro"
grep -q '^PKG_NAME:=luci-app-timecontrol' ./package/luci-app-timecontrol/luci-app-timecontrol/Makefile || fail "timecontrol"
[ -f ./feeds/packages/net/sqm-scripts/Makefile ] || fail "feed sqm-scripts missing"
[ -f ./feeds/luci/applications/luci-app-sqm/Makefile ] || fail "feed luci-app-sqm missing"

#feed 中不得残留另一份 homeproxy
[ -z "$(find ./feeds/luci ./feeds/packages -maxdepth 3 -type d -iname '*homeproxy*' 2>/dev/null)" ] || fail "feed homeproxy remains"

#sing-box 必须为 1.14.x（homeproxy-pro 硬要求 >=1.14，且仅针对 1.14 开发）
SB=$(find ./feeds/packages ./package -maxdepth 3 -type f -path '*/sing-box/Makefile' | head -n1)
[ -n "$SB" ] || fail "sing-box Makefile not found"
SBV=$(grep -m1 -oP '^PKG_VERSION:=\K[0-9]+\.[0-9]+' "$SB")
echo "sing-box: $SB => $SBV"
[ "$SBV" = "1.14" ] || fail "sing-box version is $SBV, expected 1.14"

echo "ZN-PPE checks passed."
