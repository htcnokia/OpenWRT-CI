#!/bin/bash
# PRIVATE.sh - 自定义包与 Makefile 调整脚本

# ==================================================
# 1. X86_64 平台专属逻辑（已移除危险的 dockerd sed 替换）
# ==================================================
if [ "$WRT_CONFIG" = "X86" ] || grep -q "CONFIG_TARGET_x86_64=y" .config 2>/dev/null; then
  echo "🎯 检测到当前正在编译 X86_64 平台。"
fi

# ==================================================
# 2. IPQ60XX 平台专属：直接在编译时追加裁剪配置到 .config
# ==================================================
if [ "$WRT_CONFIG" = "IPQ60XX-WIFI-NO" ] || grep -q "CONFIG_TARGET_qualcommax_ipq60xx=y" .config 2>/dev/null; then
  echo "🎯 当前为 IPQ60XX 编译任务，正在注入专属精简配置..."
  
  {
    echo "# --- EXCLUSIVE OVERRIDE FOR IPQ60XX ---"
    # 压制剔除的组件
    for pkg in dockerd docker containerd docker-compose luci-app-dockerman luci-lib-docker luci-app-samba4 samba4-server samba4-libs ksmbd luci-app-ksmbd python3; do
      echo "CONFIG_PACKAGE_${pkg}=n"
      echo "# CONFIG_PACKAGE_${pkg} is not set"
    done
    # 额外增补的组件
    for pkg in conntrack dig ip-full ddns-scripts-services ddns-scripts luci-app-ddns luci-app-timecontrol luci-app-cpufreq ttyd luci-app-ttyd luci-i18n-ttyd-zh-cn kmod-nft-tproxy ca-bundle; do
      echo "CONFIG_PACKAGE_${pkg}=y"
    done
  } >> .config
fi

# ==================================================
# 3. 通用 UCI 配置注入（IPv6 & PPPoE）
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
