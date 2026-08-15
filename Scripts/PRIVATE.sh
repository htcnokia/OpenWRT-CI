#!/bin/bash
# ==============================================================================
# private.sh - yichya/luci-app-xray + Xray-Core (VLESS + REALITY) 極致瘦身腳本
# ==============================================================================

echo "=================================================="
echo " [1/4] 清理並更新第三方 LuCI 應用"
echo "=================================================="

# 1.1 清理並重新複製 luci-app-timecontrol
echo "[+] 清理舊版 luci-app-timecontrol..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[+] 克隆 JS 版 luci-app-timecontrol..."
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

echo "=================================================="
echo " [2/4] 清理 PassWall & Docker 关联应用 "
echo "=================================================="

# 2.1. 彻底清理 PassWall2 与多余的核心套件
rm -rf feeds/luci/applications/luci-app-passwall*
rm -rf feeds/packages/net/passwall*
rm -rf package/feeds/luci/luci-app-passwall*
rm -rf package/luci-app-passwall*
rm -rf package/passwall_packages
rm -rf package/luci-app-xray

# 2.2 清理 Samba4 & NAS 关联
rm -rf feeds/luci/applications/luci-app-samba4
rm -rf feeds/packages/net/samba4
rm -rf feeds/luci/applications/luci-app-mini-diskmanager

# 2.3 清理 Docker 相关的 LuCI 界面（保留底层 feeds，避免 make 找不到规则报错）
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf package/feeds/luci/luci-app-dockerman

# 2.4. 删除无用的大型资料套件，防止误编译
find package/ -type d \( -name "sing-box" -o -name "v2ray-geodata" \) -exec rm -rf {} + 2>/dev/null || true

echo "=================================================="
echo " [4/4] 寫入 IPv6 與 PPPoE 最佳化腳本            "
echo "=================================================="

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-pppoe << 'EOF'
#!/bin/sh

uci set network.wan.proto='pppoe'
uci set network.wan.username='adsl'
uci set network.wan.password='password'
uci set network.wan.ipv6='auto'
uci set network.wan.keepalive='5 3'
uci set network.wan.norelease='auto'

uci set network.wan6.device='pppoe-wan'
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.ipv6_pd='auto'
uci set network.wan6.norelease='auto'

uci set network.lan.ip6assign='64'
uci del network.lan.ip6class 2>/dev/null
uci add_list network.lan.ip6class='wan6'

uci set dhcp.lan.ra='server'
uci set dhcp.lan.dhcpv6='server'

uci del network.globals.ula_prefix 2>/dev/null

uci commit network
uci commit dhcp
exit 0
EOF

chmod +x files/etc/uci-defaults/99-custom-pppoe

echo "=================================================="
echo " [Private] 所有配置與瘦身完成！                    "
echo "=================================================="
