#!/bin/bash

echo "=========================================="
echo "    开始执行 [PRIVATE.sh] 源码清洗阶段    "
echo "=========================================="

# 1. 修复 netspeedtest 遗留的 Python3 致命依赖
NETSPEED_MAKE=$(find ./ -maxdepth 4 -type f -wholename "*/netspeedtest/luci-app-netspeedtest/Makefile" 2>/dev/null | head -n 1)
if [ -n "$NETSPEED_MAKE" ]; then
    echo "[成功] 找到 netspeedtest，开始清理过时 Python 依赖..."
    sed -i 's/+python3-pkg-resources//g' "$NETSPEED_MAKE"
    sed -i 's/+python3-email//g' "$NETSPEED_MAKE"
    sed -i 's/++/\+/g' "$NETSPEED_MAKE"
    sed -i 's/ \\/\\/g' "$NETSPEED_MAKE" 
fi

# 2. 修复 QModem 缺失的 5G 驱动依赖警告
QMODEM_MAKE=$(find ./ -maxdepth 4 -type f -wholename "*/QModem/application/qmodem/Makefile" 2>/dev/null | head -n 1)
if [ -n "$QMODEM_MAKE" ]; then
    echo "[成功] 找到 QModem 并清理未安装的 5G 驱动依赖..."
    sed -i 's/+kmod-mhi-wwan//g' "$QMODEM_MAKE"
    sed -i 's/+quectel-CM-5G//g' "$QMODEM_MAKE"
fi
echo "[清理] 正在清理 luci-app-timecontrol 源码..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[克隆] 正在克隆luci-app-timecontrol 源码..."
#git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-timecontroll.git  package/luci-app-timecontrol
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

TIMECTRL_MAKE=$(find ./package/luci-app-timecontrol -maxdepth 2 -type f -name "Makefile" | head -n 1)

if [ -n "$TIMECTRL_MAKE" ]; then
    echo "[成功] 找到 Makefile: $TIMECTRL_MAKE ，开始剥离旧防火墙依赖..."
    sed -i 's/+iptables-mod-ipopt//g' "$TIMECTRL_MAKE"
    sed -i 's/+iptables//g' "$TIMECTRL_MAKE"
    sed -i 's/+ip6tables//g' "$TIMECTRL_MAKE"
    sed -i 's/+kmod-ipt-core//g' "$TIMECTRL_MAKE"
    sed -i 's/++/\+/g' "$TIMECTRL_MAKE"
    sed -i 's/::=/:=/g' "$TIMECTRL_MAKE" 2>/dev/null
    echo "[完成] timecontrol 依赖链剥离成功！"
fi

echo "[克隆] 正在克隆 luci-app-lucky 源码..."
git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/luci-app-lucky

echo "[克隆] 正在克隆 luci-app-netspeedtest 源码..."
#git clone -b main --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest.git package/netspeedtest

echo "[克隆] 正在克隆 OpenAppFilter 源码..."
git clone -b master --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter

echo "[克隆] 正在克隆 openwrt-bandix 源码..."
#git clone -b master --depth=1 https://github.com/timsaya/openwrt-bandix.git package/openwrt-bandix

echo "[克隆] 正在克隆 luci-app-bandix 源码..."
#git clone -b master --depth=1 https://github.com/timsaya/luci-app-bandix.git package/bandix

echo "=========================================="
echo "    [PRIVATE.sh] 源码清洗阶段执行完毕      "
echo "=========================================="
