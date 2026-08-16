#!/bin/bash
# PRIVATE.sh - 自定义包与动态配置调整脚本

# ==================================================
# 1.通用 UCI 配置注入（IPv6 & PPPoE）
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

# === PRIVATE: 注入到 update_resources.sh 的逻辑（幂等） ===
UPDATE_SCRIPT="files/etc/homeproxy/scripts/update_resources.sh"

if [ -f "$UPDATE_SCRIPT" ]; then
    # 已注入标记（用于幂等）
    if grep -q 'PRIVATE: remove bundled noto-color-emoji' "$UPDATE_SCRIPT"; then
        echo "[Private] Emoji-removal already injected into $UPDATE_SCRIPT"
    else
        echo "[Private] Injecting emoji-removal into $UPDATE_SCRIPT"
        tmp="$(mktemp)"
        awk 'BEGIN{done=0}
        {
            print
        }
        $0 ~ /if mv "\$DASHBOARD_STAGE" "\$DASHBOARD_DIR"; then/ && done==0 {
            # print the original matching line has already been printed above,
            # so insert our removal block right after it
            print "            # PRIVATE: remove bundled noto-color-emoji woff2 files to save space"
            print "            if [ -d \"\$DASHBOARD_DIR/assets\" ]; then"
            print "                rm -f \"\$DASHBOARD_DIR/assets\"/noto-color-emoji*.woff2 && \\"
            print "                    log \"[dashboard] PRIVATE: removed bundled noto-color-emoji font(s)\" || \\"
            print "                    log \"[dashboard] PRIVATE: no noto-color-emoji font found or removal failed.\""
            print "            fi"
            done=1
        }' "$UPDATE_SCRIPT" > "$tmp" && mv "$tmp" "$UPDATE_SCRIPT" && chmod a+rx "$UPDATE_SCRIPT"

        if [ $? -eq 0 ]; then
            echo "[Private] Injection succeeded: $UPDATE_SCRIPT updated"
        else
            echo "[Private] Injection failed: could not update $UPDATE_SCRIPT" >&2
            [ -f "$tmp" ] && rm -f "$tmp"
        fi
    fi
else
    echo "[Private] $UPDATE_SCRIPT not found; skipping injection"
fi

# 可选：同时删除任何其他可能被打包到 dashboard 子目录的同类字体（更宽松的匹配）
# find "$DASHBOARD_DIR" -type f -iname 'noto-color-emoji*.woff2' -exec rm -f {} \; -exec sh -c 'log "[dashboard] Removed {}"' \; 2>/dev/null || true


# ==================================================
# 2. IPQ60XX 兜底：在构建期间确保 Config/Private-60xx.txt 被合并
# ==================================================

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
    else
        echo "[Private] Not an IPQ60XX build — skipping Private-60xx merge"
    fi
else
    echo "[Private] .config not found — skipping IPQ60XX fallback checks"
fi
