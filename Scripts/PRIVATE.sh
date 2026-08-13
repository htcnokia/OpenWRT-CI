#!/bin/bash

echo "[清理] 正在清理 luci-app-timecontrol 源码..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[克隆] 正在克隆luci-app-timecontrol 源码..."
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

#!/bin/bash

#echo "[克隆] 正在克隆 luci-app-lucky 源码..."
#git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/lucky

# =========================================================
#  PassWall2
# =========================================================

# 1. 移除源碼中原有的 PassWall 與 PassWall2（避免重複衝突）
rm -rf feeds/luci/applications/luci-app-passwall*
rm -rf feeds/packages/net/passwall*
rm -rf package/feeds/luci/luci-app-passwall*
rm -rf package/luci-app-passwall*

# ==============================================================================
# private.sh - PassWall2 & Xray-Core (VLESS + REALITY 極致瘦身腳本)
# 適用對象：OpenWrt 固件全系統編譯 / OpenWrt SDK 單獨套件編譯
# ==============================================================================

# 1. 拉取 PassWall 依賴套件 (xray-core, v2ray-geodata 等)
git clone -b main --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall_packages

# 2. 拉取 PassWall2 主套件
git clone -b main --depth=1 https://github.com/Openwrt-Passwall/luci-app-passwall2.git package/luci-app-passwall2

echo "=================================================="
echo " [Private] Starting PassWall2 Slimming (REALITY)  "
echo "=================================================="

# 1. 精簡 PassWall2 主包 Makefile
# 僅修剪依賴項，保留 Package/luci-app-passwall2 與 i18n 語系構建定義
PASSWALL_MAKEFILES=$(find package/ -type f -name "Makefile" -path "*/luci-app-passwall2/*")

for mk in $PASSWALL_MAKEFILES; do
    echo "[+] Processing PassWall2 Makefile: $mk"
    
    # 剔除可選組件依賴 (+luci-app-passwall2_INCLUDE_*)
    sed -i 's/+luci-app-passwall2_INCLUDE_[^ ]*/ /g' "$mk"
    
    # 重寫硬性依賴：僅保留 Xray、Geodata、Dnsmasq 和基礎網路組件 (含斷線超時必備 coreutils-timeout)
    sed -i '/DEPENDS:=/c\  DEPENDS:=+xray-core +v2ray-geodata +dnsmasq-full +ip-full +ca-bundle +kmod-nft-tproxy +coreutils-timeout' "$mk"
done

# 2. 精簡 Xray-Core Makefile (注入 Go Build Tags 剔除不必要協議)
XRAY_MAKEFILES=$(find package/ -type f -name "Makefile" -path "*/xray-core/*")

for xmk in $XRAY_MAKEFILES; do
    echo "[+] Slimming Xray-Core Makefile: $xmk"
    
    # 注入編譯標籤：剔除 VMess, Trojan, Shadowsocks, SSR (僅保留 VLESS + REALITY + TLS/uTLS)
    if ! grep -q "GO_BUILD_TAGS:=" "$xmk"; then
        sed -i '/PKG_NAME:=xray-core/a GO_BUILD_LDFLAGS:=-s -w -buildid=\nGO_BUILD_TAGS:=confonly,novmess,notrojan,noshadowsocks,nossr' "$xmk"
    fi
    
    # 加入 UPX 安全壓縮 (--fast 防止 ARM64 架構記憶體頁加載崩潰)
    if ! grep -q "upx" "$xmk"; then
        sed -i '/define Package\/xray-core\/install/a \	upx --fast $(1)/usr/bin/xray || true' "$xmk"
    fi
done

# 3. 徹底清理源碼樹中多餘的第三方核心包 (防止 OpenWrt Buildroot 誤 compile)
echo "[+] Removing redundant core package directories..."
find package/ -type d \( \
    -name "sing-box" -o \
    -name "v2ray-core" -o \
    -name "v2ray-plugin" -o \
    -name "hysteria" -o \
    -name "trojan*" -o \
    -name "naiveproxy" -o \
    -name "chinadns-ng" \
\) -exec rm -rf {} + 2>/dev/null || true

echo "=================================================="
echo " [Private] Slimming Completed Successfully!       "
echo "=================================================="

echo "[修复] 正在应用 IPv6 最佳实践补丁..."
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-pppoe << 'EOF'
#!/bin/sh

# 1. 补全 WAN 拨号与 IPv6 勾选
uci set network.wan.proto='pppoe'
uci set network.wan.username='adsl'
uci set network.wan.password='password'
uci set network.wan.ipv6='1'
uci set network.wan.keepalive='5 3'
uci set network.wan.norelease='1'

# 2. 修正 WAN6 (绑定 pppoe-wan 接口，允许获取 PD 前缀)
uci set network.wan6.device='pppoe-wan'
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.ipv6_pd='1'
uci set network.wan6.norelease='1'

# 3. 修正 LAN 侧 IPv6 绑定 (关键：将前缀精准分配给 LAN)
uci set network.lan.ip6assign='64'
uci set network.lan.ip6ifaceid='eui64'
uci set network.lan.delegate='0'
uci del network.lan.ip6class 2>/dev/null
uci add_list network.lan.ip6class='wan6'

# 4. 确保 LAN 的 RA 与 DHCPv6 通告正常下发
uci set dhcp.lan.ra='server'
uci set dhcp.lan.dhcpv6='server'

# 5. 清除 ULA 本地前缀，避免伪 IPv6 路由干扰
uci del network.globals.ula_prefix 2>/dev/null

uci commit network
uci commit dhcp
exit 0
EOF

chmod +x files/etc/uci-defaults/99-custom-pppoe
