#!/bin/bash
# PRIVATE.sh - 自定义包与动态配置调整脚本

# ==================================================
# 1. 更换luci-app-timecontrol
# ==================================================
echo "[清理] 正在清理 luci-app-timecontrol 源码..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[克隆] 正在克隆luci-app-timecontrol 源码..."
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

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


# ==================================================
# 3. IPQ60XX 兜底：在构建期间确保 Config/Private-60xx.txt 被合并
#    并确保 homeproxy 的 update_resources 脚本中的面板替换也要成功
# ==================================================
# 说明：
# - 这个段落用于在构建环境中检测到 target 为 qualcommax/ipq60xx 时
#   强制合并 Config/Private-60xx.txt（优先使用 OpenWrt 的 merge_config.sh），
#   或在不可用时以安全方式删除冲突项后追加。
# - 同时对 files/etc/homeproxy/scripts/update_resources.sh 中的
#   HP_DASHBOARD_SOURCE 与 HP_DASHBOARD_VERSION_URL 做替换，
#   与 Handles.sh 中对 Dashboard 的替换保持一致，确保面板下载源一致。

echo "[Private] Running IPQ60XX fallback checks..."

# 只在存在 .config 的构建目录中运行
if [ -f ".config" ]; then
    # 更稳健的匹配（匹配有/无双引号的情况）
    if grep -qE '^CONFIG_TARGET_BOARD="?qualcommax"?' .config && grep -qE '^CONFIG_TARGET_SUBTARGET="?ipq60xx"?' .config; then
        echo "[Private] Detected target: qualcommax/ipq60xx — applying Private-60xx merge"

        if [ -f "Config/Private-60xx.txt" ]; then
            # 优先使用 merge_config.sh（若在 OpenWrt 源树中可用）
            if [ -x "scripts/kconfig/merge_config.sh" ]; then
                echo "[Private] Using scripts/kconfig/merge_config.sh to merge Private-60xx.txt"
                scripts/kconfig/merge_config.sh .config Config/Private-60xx.txt || echo "[Private] merge_config.sh failed — continuing"
            else
                echo "[Private] merge_config.sh not found — performing safe removal+append"
                # 删除可能已存在的冲突条目（disable 列表）以避免重复或覆盖问题
                DISABLE_PKGS="dockerd docker containerd docker-compose luci-app-dockerman luci-lib-docker luci-app-samba4 samba4-server samba4-libs ksmbd luci-app-ksmbd python3"
                for pkg in $DISABLE_PKGS; do
                    # 删除显式设置与注释形式的旧行
                    sed -i -E "/^CONFIG_PACKAGE_${pkg}=/d; /^# CONFIG_PACKAGE_${pkg} is not set/d" .config || true
                done
                # 追加补丁片段（若尚未追加）
                if ! grep -qF "# --- IPQ60XX EXCLUSIVE ---" .config; then
                    cat Config/Private-60xx.txt >> .config || echo "[Private] Failed to append Config/Private-60xx.txt"
                else
                    echo "[Private] Private-60xx already present in .config"
                fi
            fi
        else
            echo "[Private] Config/Private-60xx.txt not found — skipping merge"
        fi

        # 确保 homeproxy 更新脚本也替换了面板源（files 目录下的脚本）
        UPD_SH="files/etc/homeproxy/scripts/update_resources.sh"
        if [ -f "$UPD_SH" ]; then
            echo "[Private] Patching $UPD_SH dashboard sources"
            sed -i 's|HP_DASHBOARD_SOURCE=.*|HP_DASHBOARD_SOURCE="https://codeload.github.com/MetaCubeX/Yacd-meta/zip/refs/heads/gh-pages"|g' "$UPD_SH" || true
            sed -i 's|HP_DASHBOARD_VERSION_URL=.*|HP_DASHBOARD_VERSION_URL="https://github.com/MetaCubeX/Yacd-meta/commits/gh-pages.atom"|g' "$UPD_SH" || true
        else
            echo "[Private] $UPD_SH not present — skipping dashboard patch"
        fi

    else
        echo "[Private] Not an IPQ60XX build — skipping Private-60xx merge"
    fi
else
    echo "[Private] .config not found — skipping IPQ60XX fallback checks"
fi
