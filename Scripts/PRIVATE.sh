#!/bin/bash
# ==============================================================================
# private.sh - yichya/luci-app-xray + Xray-Core (VLESS + REALITY) 極致瘦身腳本
# ==============================================================================

echo "=================================================="
echo " [1/4] 清理並更新第三方 LuCI 應用"
echo "=================================================="

# 1. 清理並重新複製 luci-app-timecontrol
echo "[+] 清理舊版 luci-app-timecontrol..."
rm -rf package/luci-app-timecontrol
rm -rf luci-app-timecontrol
rm -rf package/feeds/luci/luci-app-timecontrol
rm -rf package/feeds/packages/luci-app-timecontrol

echo "[+] 克隆 JS 版 luci-app-timecontrol..."
git clone -b js --depth=1 https://github.com/gaobin89/luci-app-timecontrol.git package/luci-app-timecontrol

echo "=================================================="
echo " [2/4] 清理 PassWall2 並導入 yichya/luci-app-xray "
echo "=================================================="

# 1. 徹底清理 PassWall2 與多餘的核心套件
rm -rf feeds/luci/applications/luci-app-passwall*
rm -rf feeds/packages/net/passwall*
rm -rf package/feeds/luci/luci-app-passwall*
rm -rf package/luci-app-passwall*
rm -rf package/passwall_packages
rm -rf package/luci-app-xray

# 2. 拉取 yichya/luci-app-xray
echo "[+] 克隆 yichya/luci-app-xray 源碼..."
git clone -b master --depth=1 https://github.com/yichya/luci-app-xray.git package/luci-app-xray

# =========================================================
# 2.0 清理 Samba4 & NAS 相關源碼（防止殘留依賴拉入 Python）
# =========================================================
rm -rf feeds/luci/applications/luci-app-samba4
rm -rf feeds/packages/net/samba4
rm -rf feeds/luci/applications/luci-app-mini-diskmanager

# =========================================================
# 2.1. 解決 Docker (dockerd) 編譯報錯：直接從 packages 中移除 dockerd
# =========================================================
rm -rf feeds/packages/utils/dockerd
rm -rf feeds/packages/utils/docker
rm -rf feeds/packages/utils/containerd

echo "=================================================="
echo " [3/4] 執行 Xray-Core UPX 瘦身與協議精簡        "
echo "=================================================="

# 3. 對 Xray-Core Makefile 進行 UPX 瘦身與協議裁剪
# 3.1. 搜尋 feeds 與 package 目錄下所有的 xray-core Makefile
XRAY_MAKEFILES=$(find . -type f -name "Makefile" -path "*/xray-core/*")

# 3.2. 注入 UPX 瘦身指令
for xmk in $XRAY_MAKEFILES; do
  echo "[+] 找到 xray-core Makefile: $xmk"
  if ! grep -q "upx --fast" "$xmk"; then
      sed -i '/define Build\/Compile/a \	upx --fast $(PKG_BUILD_DIR)/xray || true' "$xmk"
      echo "[+] 成功注入 UPX 壓縮指令！"
  fi
done

# 4. 刪除無用的大型資料套件，防止誤編譯
find package/ -type d \( -name "sing-box" -o -name "v2ray-geodata" \) -exec rm -rf {} + 2>/dev/null || true

echo "=================================================="
echo " [4/4] 寫入 IPv6 與 PPPoE 最佳化腳本            "
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
echo " [Private] 所有配置與瘦身完成！                   "
echo "=================================================="
