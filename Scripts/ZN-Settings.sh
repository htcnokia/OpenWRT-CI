#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
# OpenWRT-CI/Scripts/ZN-Settings.sh

# 移除 luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")

# 修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")

# 修改 immortalwrt.lan 关联 IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")

# 添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

if [ -f "$WIFI_SH" ]; then
    # 修改 WIFI 名称
    sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"
    # 修改 WIFI 密码
    sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"
elif [ -f "$WIFI_UC" ]; then
    # 修改 WIFI 名称
    sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" "$WIFI_UC"
    # 修改 WIFI 密码
    sed -i "s/key='.*'/key='$WRT_WORD'/g" "$WIFI_UC"
fi

CFG_FILE="./package/base-files/files/bin/config_generate"

# 修改默认 IP 地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"

# 修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"

# 配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

# ========================================================
# HomeProxy 私有规则集：保留配置 + 预置目录
# ========================================================

# 1. 刷机（保留配置）时保留 ruleset
mkdir -p ./files/etc
touch ./files/etc/sysupgrade.conf

grep -qxF "/etc/homeproxy/ruleset/" ./files/etc/sysupgrade.conf \
    || echo "/etc/homeproxy/ruleset/" >> ./files/etc/sysupgrade.conf

# 2. 预置目录，保证全新刷机后目录存在
mkdir -p ./files/etc/homeproxy/ruleset
touch ./files/etc/homeproxy/ruleset/.keep

echo "HomeProxy ruleset preserved:"
cat ./files/etc/sysupgrade.conf

# 引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
    echo "Applying private configurations from PRIVATE.txt..."
    cat "$GITHUB_WORKSPACE/Config/PRIVATE.txt" >> ./.config
fi

# 手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" >> ./.config
fi

# ZN-M2 有线版无 WIFI
if [[ "${WRT_CONFIG^^}" == "ZN-M2-WIRED" ]]; then
    echo "WRT_WIFI=wifi-no" >> "$GITHUB_ENV"
fi

# ========================================================
# 高通平台调整
# ========================================================

DTS_PATH="./target/linux/qualcommax/dts/"

if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    # ZN-M2 有线版使用无 WIFI DTS
    if [[ "${WRT_CONFIG^^}" == "ZN-M2-WIRED" ]]; then
        find "$DTS_PATH" -type f ! -iname '*nowifi*' \
            -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +

        echo "ZN-M2-WIRED: qualcommax set up nowifi successfully!"
    fi
fi

# ============================================================
# 固化到固件：IPv6 管理脚本
# ============================================================

ZN_BAKE_SRC="$GITHUB_WORKSPACE/Scripts"

ZN_BAKE() {
    # ZN_BAKE <源文件名> <目标路径> <权限>
    if [ -s "$ZN_BAKE_SRC/$1" ]; then
        mkdir -p "$(dirname "$2")"
        cp -f "$ZN_BAKE_SRC/$1" "$2"
        chmod "$3" "$2"
        echo "固化: $1 -> ${2#./files}"
    else
        echo "::warning title=ZN-Settings::缺少 Scripts/$1，未能固化到固件"
        return 1
    fi
}

ZN_BAKE "ZN-manage_ipv6.sh" "./files/usr/bin/manage_ipv6.sh" 0755

exit 0

#以下放弃上游owrt分支的ppe qos，原因异常导致网站js下载奇慢

# ========================================================
# ZN-M2-WIRED：专用 SQM Layer Cake + PPE QoS
#
# 不修改上游 sqm-scripts 源码
# 不修改上游 sqm-scripts Makefile
# PPE APPLY 只负责 PPE 规则重应用
# SQM 初始化和开机启用由 UCI Defaults 负责
# ========================================================

if [[ "${WRT_CONFIG^^}" == "ZN-M2-WIRED" ]] &&
   [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then

    echo "===== ZN-PPE-SQM BUILD INTEGRATION ====="

    ZN_SQM_DIR="./files/usr/lib/sqm"
    ZN_BIN_DIR="./files/usr/bin"
    ZN_HOTPLUG_DIR="./files/etc/hotplug.d/iface"
    ZN_UCI_DIR="./files/etc/uci-defaults"

    mkdir -p "$ZN_SQM_DIR" "$ZN_BIN_DIR" \
        "$ZN_HOTPLUG_DIR" "$ZN_UCI_DIR"

    # 1. 安装 ZN 专用 Layer Cake
    ZN_BAKE "ZN-Layer-Cake.qos" \
        "$ZN_SQM_DIR/ZN-Layer-Cake.qos" 0755 || exit 1

    ZN_BAKE "ZN-Layer-Cake.qos.help" \
        "$ZN_SQM_DIR/ZN-Layer-Cake.qos.help" 0644 || exit 1

    # 2. 安装 PPE/SQM 辅助脚本
    ZN_BAKE "ZN-PPE-SQM-APPLY.sh" \
        "$ZN_BIN_DIR/ZN-PPE-SQM-APPLY.sh" 0755 || exit 1

    # 3. 首次启动时设置 ZN Layer Cake 并确保 SQM 开机启动
    cat > "$ZN_UCI_DIR/99-ZN-PPE-SQM" <<'ZN_SQM_UCI_EOF'
#!/bin/sh

[ -x /usr/bin/uci ] || exit 0
[ -f /etc/config/sqm ] || exit 0
[ -x /etc/init.d/sqm ] || exit 0

if uci -q get sqm.eth1 >/dev/null 2>&1; then
    uci set sqm.eth1.script='ZN-Layer-Cake.qos' || exit 0
    uci commit sqm || exit 0

    /etc/init.d/sqm enable

    logger -t ZN-PPE-SQM \
        "SQM enabled with ZN-Layer-Cake.qos"
fi

exit 0
ZN_SQM_UCI_EOF

    chmod 0755 "$ZN_UCI_DIR/99-ZN-PPE-SQM"

    # 4. PPE iface hotplug：兼容 qcom_ppe 和 qca_ppe
    cat > "$ZN_HOTPLUG_DIR/20-qca-ppe-qos" <<'ZN_PPE_HOTPLUG_EOF'
#!/bin/sh

case "$ACTION" in
    ifup|ifupdate) ;;
    *) exit 0 ;;
esac

[ -d /sys/bus/platform/drivers/qcom_ppe ] ||
[ -d /sys/bus/platform/drivers/qca-ppe ] || exit 0

[ -x /etc/init.d/qca-ppe-qos ] || exit 0
/etc/init.d/qca-ppe-qos enabled || exit 0

/etc/init.d/qca-ppe-qos reload
ZN_PPE_HOTPLUG_EOF

    chmod 0755 "$ZN_HOTPLUG_DIR/20-qca-ppe-qos"

    # 5. 安装文件检查
    test -s "$ZN_SQM_DIR/ZN-Layer-Cake.qos" || exit 1
    test -s "$ZN_SQM_DIR/ZN-Layer-Cake.qos.help" || exit 1
    test -x "$ZN_BIN_DIR/ZN-PPE-SQM-APPLY.sh" || exit 1
    test -x "$ZN_UCI_DIR/99-ZN-PPE-SQM" || exit 1
    test -x "$ZN_HOTPLUG_DIR/20-qca-ppe-qos" || exit 1

    echo "ZN-PPE-SQM: BUILD INSTALL PASS"
    echo "SQM script: ZN-Layer-Cake.qos"
    echo "PPE helper: /usr/bin/ZN-PPE-SQM-APPLY.sh"
    echo "PPE hotplug: qcom_ppe + qca_ppe"
fi
