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
# DIY Part 2: 替換 PassWall2 為私人精簡倉庫
# =========================================================

# 1. 移除源碼中原有的 PassWall 與 PassWall2（避免重複衝突）
rm -rf feeds/luci/applications/luci-app-passwall*
rm -rf feeds/packages/net/passwall*
rm -rf package/feeds/luci/luci-app-passwall*
rm -rf package/luci-app-passwall*

echo "[修复] 正在应用 openwrt-passwall2 倉庫"
git clone -b main --depth=1 https://github.com/htcnokia/openwrt-passwall2.git package/luci-app-passwall2

# 3. 補裝 UPX 工具（編譯機需要）
sudo apt-get update && sudo apt-get install -y upx-ucl

# 4. 關鍵：執行 passwall2 內部的私有瘦身腳本
if [ -f "package/luci-app-passwall2/private.sh" ]; then
    chmod +x package/luci-app-passwall2/private.sh
    ./package/luci-app-passwall2/private.sh
else
    echo "[错误] 未找到 package/luci-app-passwall2/private.sh，请检查仓库结构！"
fi

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
