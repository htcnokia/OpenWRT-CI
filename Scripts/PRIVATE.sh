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

# =====================================================================
# 3. ====== 强力超度旧 timecontrol，物理克隆 gaobin89 版 ======
# =====================================================================
# echo "[强力清理] 正在物理粉碎所有可能重名的 timecontrol 目录..."
# rm -rf package/luci-app-timecontrol
# rm -rf luci-app-timecontrol
# rm -rf package/feeds/luci/luci-app-timecontrol
# rm -rf package/feeds/packages/luci-app-timecontrol

# echo "[克隆] 正在标准克隆 gaobin89 纯 FW4 源码..."
# git clone --depth=1 -b js https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

echo "[克隆] 正在克隆sirpdbo luci-app-timecontrol 源码..."
git clone -b main https://github.com/sirpdboy/luci-app-timecontroll.git  package/luci-app-timecontrol

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
git clone -b main https://github.com/sirpdboy/luci-app-lucky.git package/luci-app-lucky

echo "[克隆] 正在克隆 luci-app-netspeedtest 源码..."
git clone https://github.com/sirpdboy/luci-app-netspeedtest package/netspeedtest


# =====================================================================
# 4. ====== 静态拉取 Metacubexd 面板到 /www/dashboard ======
# =====================================================================
echo "🌐 正在静态下载 Metacubexd 面板..."
rm -rf files/www/dashboard
mkdir -p files/www/dashboard
git clone --depth=1 -b gh-pages https://github.com/MetaCubeX/Metacubexd.git files/www/dashboard/tmp_meta
if [ -d "files/www/dashboard/tmp_meta" ]; then
    cp -r files/www/dashboard/tmp_meta/. files/www/dashboard/
    rm -rf files/www/dashboard/tmp_meta
    rm -rf files/www/dashboard/.git
    echo "✅ Metacubexd 面板静态文件注入成功！"
fi

# =====================================================================
# 5.  ====== 预置HomeProxy数据解封 9090 面板 ======
# =====================================================================
PKG_PATH="$GITHUB_WORKSPACE/wrt/package/"

#预置HomeProxy数据
if [ -d *"homeproxy"* ]; then
	echo " "

	HP_RULE="surge"
	HP_PATH="homeproxy/root/etc/homeproxy"
	HP_CONFIG_DIR="homeproxy/root/etc/config"
	HP_DEFAULTS_DIR="homeproxy/root/etc/uci-defaults"

	rm -rf ./$HP_PATH/resources/*

	git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULE/
	cd ./$HP_RULE/ && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

	echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
	sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
	mv -f ./{china_*,gfw_list}.{ver,txt} ../$HP_PATH/resources/

	cd .. && rm -rf ./$HP_RULE/

	# 1. 预置 HomeProxy 自身 UCI 配置
	if [ -f "$HP_CONFIG_DIR/homeproxy" ]; then
		echo "Setting HomeProxy UCI defaults..."
		uci -c "$HP_CONFIG_DIR" set homeproxy.config.api_enable='1'
		uci -c "$HP_CONFIG_DIR" set homeproxy.config.api_port='9090'
		uci -c "$HP_CONFIG_DIR" set homeproxy.config.api_address='0.0.0.0'
		uci -c "$HP_CONFIG_DIR" set homeproxy.config.api_secret=''
		uci -c "$HP_CONFIG_DIR" commit homeproxy
	fi

	# 2. 预置防火墙 UCI 规则
	echo "Creating firewall uci-defaults script..."
	mkdir -p "$HP_DEFAULTS_DIR"
	cat << 'EOF' > "$HP_DEFAULTS_DIR/99-homeproxy-firewall"
#!/bin/sh

uci -q delete firewall.homeproxy_api_allow
uci set firewall.homeproxy_api_allow=rule
uci set firewall.homeproxy_api_allow.name='Allow-HomeProxy-API-LAN'
uci set firewall.homeproxy_api_allow.src='lan'
uci set firewall.homeproxy_api_allow.proto='tcp'       
uci set firewall.homeproxy_api_allow.dest_port='9090'
uci set firewall.homeproxy_api_allow.target='ACCEPT'
uci commit firewall

exit 0
EOF
	chmod +x "$HP_DEFAULTS_DIR/99-homeproxy-firewall"

	cd $PKG_PATH && echo "homeproxy data, UCI, and firewall configs have been updated!"
fi

echo "=========================================="
echo "    [PRIVATE.sh] 源码清洗阶段执行完毕      "
echo "=========================================="
