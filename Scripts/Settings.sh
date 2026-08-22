#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

# --- IPQ60XX_SYSCTL_1GB: 1GB RAM 专属内核优化与日志写内存 ---
if [[ "${WRT_CONFIG,,}" == *"ipq60xx"* ]]; then
  echo "🚀 正在为 IPQ60XX (1GB RAM) 注入内核参数与闪存保护配置..."
  SYSCTL_CONF="files/etc/sysctl.conf"
  mkdir -p "$(dirname "$SYSCTL_CONF")"
  touch "$SYSCTL_CONF"
  sed -i '/net.netfilter.nf_conntrack_max/d' "$SYSCTL_CONF" || true
  echo "net.netfilter.nf_conntrack_max=131072" >> "$SYSCTL_CONF"
  sed -i '/net.netfilter.nf_conntrack_tcp_timeout_established/d' "$SYSCTL_CONF" || true
  echo "net.netfilter.nf_conntrack_tcp_timeout_established=7400" >> "$SYSCTL_CONF"
  sed -i '/net.core.somaxconn/d' "$SYSCTL_CONF" || true
  echo "net.core.somaxconn=2048" >> "$SYSCTL_CONF"
  sed -i '/net.ipv4.tcp_fastopen/d' "$SYSCTL_CONF" || true
  echo "net.ipv4.tcp_fastopen=3" >> "$SYSCTL_CONF"
  sed -i '/vm.swappiness/d' "$SYSCTL_CONF" || true
  echo "vm.swappiness=10" >> "$SYSCTL_CONF"
  sed -i '/vm.dirty_ratio/d' "$SYSCTL_CONF" || true
  echo "vm.dirty_ratio=30" >> "$SYSCTL_CONF"
  sed -i '/vm.dirty_background_ratio/d' "$SYSCTL_CONF" || true
  echo "vm.dirty_background_ratio=10" >> "$SYSCTL_CONF"
  MODPROBE_CONF="files/etc/modprobe.d/nf_conntrack.conf"
  mkdir -p "$(dirname "$MODPROBE_CONF")"
  echo "options nf_conntrack hashsize=16384" > "$MODPROBE_CONF"
  echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> ./.config
  CFG_GEN="./package/base-files/files/bin/config_generate"
  if [ -f "$CFG_GEN" ]; then
    sed -i '/set system.@system\[-1\].log_file/d' "$CFG_GEN" || true
    sed -i '/set system.@system\[-1\].log_size/d' "$CFG_GEN" || true
    sed -i '/generate_system()/a \        set system.@system[-1].log_file=/tmp/system.log\n        set system.@system[-1].log_size=64' "$CFG_GEN"
  fi
  echo "✅ IPQ60XX (1GB RAM) 参数与闪存保护注入完成！"
fi
