#!/bin/bash

echo "=========================================="
echo "    开始执行 [PRIVATE.sh] APK+FW4 专属修复    "
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

# 3. 强力修复 timecontrol 防火墙与 APK 依赖冲突
TIMECTRL_MAKE=$(find ./ -maxdepth 4 -type f -wholename "*/luci-app-timecontrol/luci-app-timecontrol/Makefile" 2>/dev/null | head -n 1)
if [ -n "$TIMECTRL_MAKE" ]; then
    echo "[成功] 找到 timecontrol Makefile: $TIMECTRL_MAKE"
    echo "正在全面剥离旧版 iptables 依赖以适配 APK & FW4 环境..."
    
    # 彻底清除 Makefile 中各种旧版 iptables/ip6tables 包的强依赖声明
    sed -i 's/+iptables-mod-ipopt//g' "$TIMECTRL_MAKE"
    sed -i 's/+iptables//g' "$TIMECTRL_MAKE"
    sed -i 's/+ip6tables//g' "$TIMECTRL_MAKE"
    sed -i 's/+kmod-ipt-core//g' "$TIMECTRL_MAKE"
    
    # 清理可能导致的语法小尾巴（如 ++ 变 +）
    sed -i 's/++/\+/g' "$TIMECTRL_MAKE"
    sed -i 's/::=/:=/g' "$TIMECTRL_MAKE" 2>/dev/null # 兼容老旧 Makefile 赋值语法
    
    echo "[完成] timecontrol 依赖链强制放行成功！"
else
    echo "[警告] 未找到 timecontrol 的 Makefile，请确认克隆路径。"
fi

# =====================================================================
# 4. ====== 静态拉取 Metacubexd 面板到 /www/dashboard ======
# =====================================================================
echo "🌐 正在静态下载 Metacubexd 面板..."
# 确保清理旧残留，创建干净的面板目录
rm -rf files/www/dashboard
mkdir -p files/www/dashboard

# 克隆 gh-pages 分支（该分支是纯静态网页产物，直接放 www 就能用）
git clone --depth=1 -b gh-pages https://github.com/MetaCubeX/Metacubexd.git files/www/dashboard/tmp_meta

if [ -d "files/www/dashboard/tmp_meta" ]; then
    # 强力复制所有文件（包含隐藏文件）
    cp -r files/www/dashboard/tmp_meta/. files/www/dashboard/
    # 彻底抹除 git 痕迹，缩减固件体积
    rm -rf files/www/dashboard/tmp_meta
    rm -rf files/www/dashboard/.git
    echo "✅ Metacubexd 面板静态文件注入成功！"
else
    echo "❌ 警告：面板拉取失败，请检查 GitHub 网络连接！"
fi

# =====================================================================
# 5. ====== 【终极修复】强制开启 HomeProxy API 服务并解封 9090 面板 ======
# =====================================================================
mkdir -p files/etc/uci-defaults
cat << 'UCI_EOF' > files/etc/uci-defaults/99-homeproxy-dashboard-firewall
#!/bin/sh

# 1. 强行注入 HomeProxy 内核的 API 监听配置
uci set homeproxy.config.api_enable='1'
uci set homeproxy.config.api_port='9090'
uci set homeproxy.config.api_address='0.0.0.0'
uci set homeproxy.config.api_secret='' # 免密登录
uci commit homeproxy

# 2. 适配 FW4 (nftables) 的强力防火墙放行规则
uci -q delete firewall.homeproxy_api_allow
uci set firewall.homeproxy_api_allow=rule
uci set firewall.homeproxy_api_allow.name='Allow-HomeProxy-API-LAN'
uci set firewall.homeproxy_api_allow.src='lan'
uci set firewall.homeproxy_api_allow.proto='tcp'       # 补全：明确指定 TCP 协议，FW4 更稳定
uci set firewall.homeproxy_api_allow.dest_port='9090'
uci set firewall.homeproxy_api_allow.target='ACCEPT'
uci commit firewall

# 3. 强行开启 Linux 内核对本地回环网卡的跨网转发许可（双保险）
echo "net.ipv4.conf.all.route_localnet=1" >> /etc/sysctl.conf
sysctl -p 2>/dev/null

# 4. 补全：让防火墙和代理服务当场重载，确保首次开机进系统时 9090 端口直接就是通的
/etc/init.d/firewall reload 2>/dev/null
/etc/init.d/homeproxy restart 2>/dev/null

exit 0
UCI_EOF

chmod +x files/etc/uci-defaults/99-homeproxy-dashboard-firewall

echo "=========================================="
echo "    [PRIVATE.sh] APK+FW4 专属修复执行完毕   "
echo "=========================================="
