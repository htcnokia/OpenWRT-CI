#!/bin/bash
# ==============================================================================
# private.sh - OpenWrt 固件自訂補丁 (PassWall2 瘦身 + IPv6 最佳化)
# ==============================================================================

echo "=================================================="
echo " [1/4] 清理並更新第三方 LuCI 應用"
echo "=================================================="

# 1. 清理並重新複製 luci-app-timecontrol
echo "[+] 清理舊版 luci-app-timecontrol..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[+] 克隆 JS 版 luci-app-timecontrol..."
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

# 2. 清理官方/Feeds 中原有的 PassWall 與 PassWall2（避免選單重複衝突）
echo "[+] 清理舊版 PassWall / PassWall2 源码..."
rm -rf feeds/luci/applications/luci-app-passwall*
rm -rf feeds/packages/net/passwall*
rm -rf package/feeds/luci/luci-app-passwall*
rm -rf package/feeds/packages/passwall*
rm -rf package/luci-app-passwall*
rm -rf package/passwall_packages

echo "=================================================="
echo " [2/4] 克隆最新 PassWall2 與 依賴套件"
echo "=================================================="

# 拉取最新源碼至 package 目錄
git clone -b main --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall_packages
git clone -b main --depth=1 https://github.com/Openwrt-Passwall/luci-app-passwall2.git package/luci-app-passwall2

echo "=================================================="
echo " [3/4] 執行 PassWall2 & Xray-Core Slimming (REALITY)"
echo "=================================================="

# 1. 精簡 PassWall2 主包 Makefile 依賴
PASSWALL_MAKEFILES=$(find package/ -type f -name "Makefile" -path "*/luci-app-passwall2/*")
for mk in $PASSWALL_MAKEFILES; do
    echo "[+] Slimming PassWall2 Makefile: $mk"
    # 剔除可選組件依賴 (+luci-app-passwall2_INCLUDE_*)
    sed -i 's/+luci-app-passwall2_INCLUDE_[^ ]*/ /g' "$mk"
    # 強制收斂硬性依賴
    sed -i '/DEPENDS:=/c\  DEPENDS:=+xray-core +v2ray-geodata +dnsmasq-full +ip-full +ca-bundle +kmod-nft-tproxy +coreutils-timeout' "$mk"
done

# 2. 精簡 Xray-Core Makefile (注入 Go Tags 剔除 VMess/Trojan/SS)
XRAY_MAKEFILES=$(find package/ -type f -name "Makefile" -path "*/xray-core/*")
for xmk in $XRAY_MAKEFILES; do
    echo "[+] Slimming Xray-Core Makefile: $xmk"
    
    # 注入 GO_BUILD_TAGS，僅保留 VLESS + REALITY
    if ! grep -q "GO_BUILD_TAGS:=" "$xmk"; then
        sed -i '/PKG_NAME:=xray-core/a GO_BUILD_LDFLAGS:=-s -w -buildid=\nGO_BUILD_TAGS:=confonly,novmess,notrojan,noshadowsocks,nossr' "$xmk"
    fi
    
    # 修正 UPX 注入語法 (確保使用真正的 Tab 鍵，防止 Makefile 語法錯誤)
    if ! grep -q "upx" "$xmk"; then
        sed -i '/define Package\/xray-core\/install/a \t-upx --fast $(1)/usr/bin/xray || true' "$xmk"
    fi
done

# 3. 物理刪除多餘核心包目錄，防止 Buildroot 誤 compile
echo "[+] 移除無用的代理核心目錄..."
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
echo " [4/4] 寫入 IPv6 與 PPPoE 最佳化腳本"
echo "=================================================="

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-pppoe << 'EOF'
#!/bin/sh

# 1. WAN 撥號與 IPv6 啟動
uci set network.wan.proto='pppoe'
uci set network.wan.username='adsl'
uci set network.wan.password='password'
uci set network.wan.ipv6='1'
uci set network.wan.keepalive='5 3'
uci set network.wan.norelease='1'

# 2. 修正 WAN6 (綁定 pppoe-wan 介面，獲取 PD 前綴)
uci set network.wan6.device='pppoe-wan'
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.ipv6_pd='1'
uci set network.wan6.norelease='1'

# 3. LAN 側 IPv6 配置 (把前綴分配給 LAN)
uci set network.lan.ip6assign='64'
uci set network.lan.ip6ifaceid='eui64'
uci set network.lan.delegate='0'
uci del network.lan.ip6class 2>/dev/null
uci add_list network.lan.ip6class='wan6'

# 4. LAN RA 與 DHCPv6 服務
uci set dhcp.lan.ra='server'
uci set dhcp.lan.dhcpv6='server'

# 5. 清理 ULA 前綴，避免偽 IPv6 干擾
uci del network.globals.ula_prefix 2>/dev/null

uci commit network
uci commit dhcp
exit 0
EOF

chmod +x files/etc/uci-defaults/99-custom-pppoe

echo "=================================================="
echo " [Private] 所有自訂補丁與精簡作業處理完成！        "
echo "=================================================="
