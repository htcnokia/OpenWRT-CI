#!/bin/bash

echo "[清理] 正在清理 luci-app-timecontrol 源码..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[克隆] 正在克隆luci-app-timecontrol 源码..."
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

#echo "[克隆] 正在克隆 luci-app-lucky 源码..."
#git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/lucky

# ==========================================
# 加入 PassWall 及其依賴包 (Xray-core / sing-box 等)
# ==========================================
# 1. 移除 openwrt feeds 自帶的核心庫與過時核心
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# 2. 移除 openwrt feeds 中過時的 PassWall 1 與 PassWall 2 luci 介面
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-passwall2

# 3. 拉取最新的 PassWall 核心套件包 (包含最新版的 Xray-core)
git clone -b main --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 4. 拉取 PassWall 2 主程式
git clone -b main --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/passwall2

# 3. (可選) 移除預設/重複的某些舊依賴，避免編譯衝突
# rm -rf package/feeds/packages/v2ray-geodata

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
