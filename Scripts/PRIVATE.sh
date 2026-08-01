#!/bin/bash

echo "[清理] 正在清理 luci-app-timecontrol 源码..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[克隆] 正在克隆luci-app-timecontrol 源码..."
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

echo "[克隆] 正在克隆 luci-app-lucky 源码..."
git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/lucky

echo "[修复] 正在应用ipv6补丁..."
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-pppoe << 'EOF'
#!/bin/sh
[ "$(uci -q get network.wan.proto)" = "pppoe" ] || exit 0
uci -q batch << 'UCI'
set network.wan.ipv6='0'
set network.wan.keepalive='5 3'
set network.wan.norelease='1'
commit network
UCI
exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-pppoe
