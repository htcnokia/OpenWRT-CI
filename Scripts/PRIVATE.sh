#!/bin/bash
# PRIVATE.sh - 自定义包与动态配置调整脚本

# ==================================================
# 1. 动态判断平台并精准裁剪（只影响 QCA / IPQ60XX）
# ==================================================
if [ "$WRT_CONFIG" = "IPQ60XX-WIFI-NO" ] || grep -q "CONFIG_TARGET_qualcommax_ipq60xx=y" .config 2>/dev/null; then
  echo "=================================================="
  echo " 🎯 检测到当前为 IPQ60XX 编译任务，注入专属瘦身配置..."
  echo "=================================================="
  
  # 直接向当前生成的 .config 追加覆盖指令
  cat >> .config << 'EOF'

# --- EXCLUSIVE OVERRIDE FOR IPQ60XX ---
# 禁用大体积组件
CONFIG_PACKAGE_dockerd=n
# CONFIG_PACKAGE_dockerd is not set
CONFIG_PACKAGE_docker=n
# CONFIG_PACKAGE_docker is not set
CONFIG_PACKAGE_containerd=n
# CONFIG_PACKAGE_containerd is not set
CONFIG_PACKAGE_docker-compose=n
# CONFIG_PACKAGE_docker-compose is not set
CONFIG_PACKAGE_luci-app-dockerman=n
# CONFIG_PACKAGE_luci-app-dockerman is not set
CONFIG_PACKAGE_luci-lib-docker=n
# CONFIG_PACKAGE_luci-lib-docker is not set
CONFIG_PACKAGE_luci-app-samba4=n
# CONFIG_PACKAGE_luci-app-samba4 is not set
CONFIG_PACKAGE_samba4-server=n
# CONFIG_PACKAGE_samba4-server is not set
CONFIG_PACKAGE_samba4-libs=n
# CONFIG_PACKAGE_samba4-libs is not set
CONFIG_PACKAGE_ksmbd=n
# CONFIG_PACKAGE_ksmbd is not set
CONFIG_PACKAGE_luci-app-ksmbd=n
# CONFIG_PACKAGE_luci-app-ksmbd is not set
CONFIG_PACKAGE_python3=n
# CONFIG_PACKAGE_python3 is not set

# 增补实用小组件
CONFIG_PACKAGE_conntrack=y
CONFIG_PACKAGE_dig=y
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_tree=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ddns-scripts-services=y
CONFIG_PACKAGE_ddns-scripts=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-app-timecontrol=y
CONFIG_PACKAGE_luci-app-cpufreq=y
CONFIG_PACKAGE_ttyd=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_ca-bundle=y
EOF

  echo "✅ IPQ60XX 专属精简配置已成功注入 .config！"
else
  echo "=================================================="
  echo " 🎯 当前为 X86 或其他平台，跳过 IPQ60XX 裁剪，保持全量组件！"
  echo "=================================================="
fi

# ==================================================
# 2. 通用 UCI 配置注入（IPv6 & PPPoE）
# ==================================================
echo "=================================================="
echo " 寫入 IPv6 與 PPPoE 最佳化腳本                    "
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
echo " [Private] 所有配置完成！                          "
echo "=================================================="
