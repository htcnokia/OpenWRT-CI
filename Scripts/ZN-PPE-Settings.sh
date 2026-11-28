#!/bin/bash
# ZN-PPE：纯有线主路由设置
set -e

#移除 luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题（bootstrap 即源码默认，无需替换）
if [ "$WRT_THEME" != "bootstrap" ]; then
	find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
fi
#修改 immortalwrt.lan 关联 IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +
#添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认 IP 与主机名
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件追加
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无 WIFI：切换 Q6 保留内存区（ipq6018-nowifi.dtsi 位于源码 files/arch/arm64/boot/dts/qcom/）
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* && "${WRT_CONFIG^^}" == *"WIRED"* ]]; then
	find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
	grep -q 'ipq6018-nowifi.dtsi' "$DTS_PATH/ipq6000-cmiot.dtsi" || { echo "nowifi dtsi switch FAILED" >&2; exit 1; }
	echo "qualcommax set up nowifi successfully!"
fi

#SQM(cake) 与 PPE 硬件流量卸载冲突：被 PPE 卸载的流不再经过 CPU，cake 无法整形。
#源码 firewall4 补丁默认 flow_offloading_hw=1，这里首次开机关闭硬件卸载（保留软件 flow offloading）。
mkdir -p ./files/etc/uci-defaults
cat > ./files/etc/uci-defaults/99-zn-ppe-wired <<'UCI'
#!/bin/sh
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='0'
uci -q commit firewall
#RPS：源码中 packet_steering 未设置时等同模式1；实测模式1(CPU1-3)在 CPU0 软中断占用与延迟稳定性上优于关闭，故显式写入
uci -q set network.globals.packet_steering='1'
uci -q commit network
exit 0
UCI
chmod +x ./files/etc/uci-defaults/99-zn-ppe-wired

# ============================================================
# 固化到固件：IPv6 管理脚本
# 放在 uci-defaults 之后；缺文件只告警不中断（set -e 下 return 1 会让整个构建失败，并丢掉后面的设置）
# ============================================================
ZN_BAKE() {
    # ZN_BAKE <源文件名> <目标路径> <权限>
    local name="$1" dst="$2" mode="$3" src="" d
    for d in "$GITHUB_WORKSPACE/Scripts" "$GITHUB_WORKSPACE"; do
        if [ -s "$d/$name" ]; then src="$d/$name"; break; fi
    done
    if [ -z "$src" ]; then
        src="$(find "$GITHUB_WORKSPACE" -maxdepth 3 -type f -name "$name" -size +0 -not -path "$GITHUB_WORKSPACE/wrt/*" 2>/dev/null | head -n1)"
    fi
    if [ -z "$src" ]; then
        echo "::warning title=ZN-Settings::找不到 $name（GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-未设置}），未能固化到固件"
        ls -la "$GITHUB_WORKSPACE" "$GITHUB_WORKSPACE/Scripts" 2>&1 | head -40
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    chmod "$mode" "$dst"
    echo "固化: $src -> ${dst#./files}"
    ls -l "$dst"
}

ZN_BAKE "ZN-manage_ipv6.sh" "./files/usr/bin/manage_ipv6.sh" 0755
ZN_BAKE "ZN-bench.sh" "./files/usr/bin/zn-bench.sh" 0755
