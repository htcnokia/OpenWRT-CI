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

echo "[修复] 正在应用 IPv6 最佳实践补丁..."
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-pppoe << 'EOF'
#!/bin/sh

# 1. 配置 WAN (PPPoE 基础拨号)
uci set network.wan=interface
uci set network.wan.device='wan'
uci set network.wan.proto='pppoe'
uci set network.wan.username='adsl'
uci set network.wan.password='password'
uci set network.wan.ipv6='1'
uci set network.wan.keepalive='5 3'
uci set network.wan.norelease='1'

# 2. 重建 WAN6 (绑定 pppoe-wan，明确请求 /60 大前缀)
uci -q delete network.wan6
uci -q delete network.WAN6
uci set network.wan6=interface
uci set network.wan6.device='pppoe-wan'
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci set network.wan6.ip6assign='60'
uci set network.wan6.norelease='1'

# 3. LAN 侧 IPv6：分配 /64 子网给局域网
uci set network.lan.ip6assign='64'
uci set network.lan.ip6ifaceid='eui64'

# 4. DHCP / RA：下发 IPv6 地址与路由宣告
uci set dhcp.lan.ra='server'
uci set dhcp.lan.dhcpv6='server'
uci set dhcp.lan.ra_default='1'

uci commit network
uci commit dhcp
EOF

chmod +x files/etc/uci-defaults/99-custom-pppoe
