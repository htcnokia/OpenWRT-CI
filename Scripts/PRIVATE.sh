#!/bin/bash
# ==============================================================================
# private.sh - OpenWrt 固件自訂補丁 ( + IPv6 最佳化)
# ==============================================================================

echo "=================================================="
echo " [1/2] 清理並更新第三方 LuCI 應用"
echo "=================================================="

# 1. 清理並重新複製 luci-app-timecontrol
echo "[+] 清理舊版 luci-app-timecontrol..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[+] 克隆 JS 版 luci-app-timecontrol..."
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol


    # 修正 UPX 注入語法 (確保使用真正的 Tab 鍵，防止 Makefile 語法錯誤)
    if ! grep -q "upx" "$xmk"; then
        sed -i '/define Package\/xray-core\/install/a \t-upx --fast $(1)/usr/bin/xray || true' "$xmk"
    fi
done

echo "=================================================="
echo " [2/2] 寫入 IPv6 與 PPPoE 最佳化腳本"
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
echo " [Private] 所有自訂補丁作業處理完成！        "
echo "=================================================="
