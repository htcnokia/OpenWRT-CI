#!/bin/bash
# ------ 你的独立私有扩展脚本（存放在 Scripts/PRIVATE.sh） ------

echo "🚀 开始执行用户自定义扩展脚本..."

# Actions 的 Ubuntu 环境使用 apt 安装基础组件
sudo apt-get update && sudo apt-get install -y conntrack

echo "🌐 正在清理旧插件 timecontrol..."
rm -rf ./luci-app-timecontrol
rm -rf ./package/luci-app-timecontrol
rm -rf ./package/feeds/luci/luci-app-timecontrol

# 1. 调用原作者的函数下载 gaobin89 的插件，分支精准指定为 "js"
UPDATE_PACKAGE "timecontrol" "gaobin89/luci-app-timecontrol" "js"

# 4. ====== 静态拉取 Metacubexd 面板到 /www/dashboard ======
echo "🌐 正在静态下载 Metacubexd 面板..."
mkdir -p files/www/dashboard
git clone --depth=1 -b gh-pages https://github.com/MetaCubeX/Metacubexd.git files/www/dashboard/tmp_meta
mv files/www/dashboard/tmp_meta/* files/www/dashboard/ 2>/dev/null || true
rm -rf files/www/dashboard/tmp_meta

# 5. ====== 【终极修复】强制开启 HomeProxy API 服务并解封 9090 面板 ======
mkdir -p files/etc/uci-defaults
cat << 'UCI_EOF' > files/etc/uci-defaults/99-homeproxy-dashboard-firewall
#!/bin/sh

# 1. 强行注入配置：点亮 API 开关、指定端口、指定全网段监听
# 这样固件首次开机时，sing-box 就会雷打不动地在后台把 9090 端口拉起来
uci set homeproxy.config.api_enable='1'
uci set homeproxy.config.api_port='9090'
uci set firewall.homeproxy_api_allow.target='ACCEPT'
uci set homeproxy.config.api_address='0.0.0.0'
uci set homeproxy.config.api_secret='' # 留空控制台密钥，方便你免密直接登录面板
uci commit homeproxy

# 2. 在 FW4 中添加一条规则，彻底对局域网放行 9090 端口
uci -q delete firewall.homeproxy_api_allow
uci set firewall.homeproxy_api_allow=rule
uci set firewall.homeproxy_api_allow.name='Allow-HomeProxy-API-LAN'
uci set firewall.homeproxy_api_allow.src='lan'
uci set firewall.homeproxy_api_allow.dest_port='9090'
uci set firewall.homeproxy_api_allow.target='ACCEPT'
uci commit firewall

# 3. 强行开启 Linux 内核对本地回环网卡的跨网转发许可（双保险）
echo "net.ipv4.conf.all.route_localnet=1" >> /etc/sysctl.conf
sysctl -p 2>/dev/null

exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/99-homeproxy-dashboard-firewall

# ====================================================================
# 【延迟配置】将所有依赖 .config 的配置修改操作，打包注入到 Settings.sh 的末尾
# ====================================================================
echo "📝 正在向 Settings.sh 注入延迟配置文件修改脚本..."
cat << 'SETTINGS_EOF' >> $GITHUB_WORKSPACE/Scripts/Settings.sh

echo "⚙️ 开始执行由 PRIVATE.sh 注入的配置改写操作..."

# 3. 强行开启你需要的其他自定义插件，并补齐 FW4 及测速依赖
# 【核心修复】将 luci-app-netspeedtest 补进开启列表
for app in luci-app-timecontrol luci-app-easytier luci-app-lucky luci-app-sqm luci-app-netspeedtest; do
  if grep -q "CONFIG_PACKAGE_${app}" ./.config 2>/dev/null; then
    sed -i "s/.*CONFIG_PACKAGE_${app}.*/CONFIG_PACKAGE_${app}=y/g" ./.config
  else
    echo "CONFIG_PACKAGE_${app}=y" >> ./.config
  fi
done
echo "CONFIG_PACKAGE_nftables-mod-filter=y" >> ./.config

# 【硬核补丁】欺骗/补充测速插件缺失的 Python3 依赖
# 现代 OpenWrt/ImmortalWrt 中，这几个包已经被整合进了 python3-light 或 python3-base
# 我们直接在 .config 中把它们点亮，或者通过强制依赖映射来解决警告
echo "CONFIG_PACKAGE_python3=y" >> ./.config
echo "CONFIG_PACKAGE_python3-light=y" >> ./.config
echo "CONFIG_PACKAGE_python3-base=y" >> ./.config

# 6. 阻止全局 inputs.PACKAGE 为空时的静默剔除
export WRT_PACKAGE="${WRT_PACKAGE} luci-app-timecontrol luci-app-easytier luci-app-lucky luci-app-sqm luci-app-netspeedtest"

echo "✅ 编译前点亮配置文件与依赖注入成功！"
SETTINGS_EOF

echo "✅ 自定义扩展脚本执行完毕，配置注入已准备就绪！"
