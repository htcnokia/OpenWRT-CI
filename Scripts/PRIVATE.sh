#!/bin/bash
# PRIVATE.sh - 自定义包与 Makefile 调整脚本

# ==================================================
# 1. X86_64 平台专属热补丁
# ==================================================
if [ "$WRT_CONFIG" = "X86" ] || grep -q "CONFIG_TARGET_x86_64=y" .config 2>/dev/null; then
  echo "🎯 检测到当前正在编译 X86_64 平台，准备应用 dockerd 热补丁..."

  # 直接在整个 package 和 feeds 目录下动态扫描 dockerd 的 Makefile
  DOCKERD_MAKEFILE=$(find feeds/ package/ -path "*/dockerd/Makefile" 2>/dev/null | head -n 1)

  if [ -n "$DOCKERD_MAKEFILE" ] && [ -f "$DOCKERD_MAKEFILE" ]; then
    echo "🛠️ 找到目标 Makefile: $DOCKERD_MAKEFILE"
    
    # 强行注入 -f 参数，容错 cp 拷贝空源路径的情况
    sed -i 's/cp -a/cp -af/g' "$DOCKERD_MAKEFILE"
    sed -i 's/cp -r/cp -rf/g' "$DOCKERD_MAKEFILE"
    
    echo "✅ 成功给 dockerd 注入热补丁！"
  fi
fi

# ==================================================
# 2. IPQ60XX 平台专属提示（瘦身逻辑已移至 Private-60xx.txt 处理）
# ==================================================
if [ "$WRT_CONFIG" = "IPQ60XX-WIFI-NO" ] || grep -q "CONFIG_TARGET_qualcommax_ipq60xx=y" .config 2>/dev/null; then
  echo "🎯 当前为 IPQ60XX 编译任务，跳过 Makefile 修改（由 Private-60xx.txt 处理精简）。"
fi

# ==================================================
# 3. 替换 HomeProxy Dashboard 为轻量版 (Yacd-Meta)
# ==================================================
echo "🎯 正在替换 HomeProxy 面板为轻量版 (Yacd)..."

HP_DASHBOARD_DIR=$(find package/ feeds/ -type d -path "*/homeproxy/root/etc/homeproxy/dashboard" 2>/dev/null | head -n 1)

if [ -n "$HP_DASHBOARD_DIR" ]; then
  # 清空原有的 6M 拖累面板
  rm -rf "$HP_DASHBOARD_DIR"/*
  
  # 下载并解压精简轻量版 Yacd
  TMP_DASH=$(mktemp -d)
  curl -fsSL -o "$TMP_DASH/yacd.zip" "https://codeload.github.com/MetaCubeX/Yacd-meta/zip/refs/heads/gh-pages"
  unzip -q "$TMP_DASH/yacd.zip" -d "$TMP_DASH"
  
  # 移动静态文件至 HomeProxy 目录
  EXTRACT_DIR=$(find "$TMP_DASH" -maxdepth 2 -type f -name "index.html" -exec dirname {} \;)
  if [ -n "$EXTRACT_DIR" ]; then
    cp -a "$EXTRACT_DIR/." "$HP_DASHBOARD_DIR/"
    echo "✅ HomeProxy 面板已成功替换为 Yacd（体积已减至 ~1.2M）！"
  fi
  rm -rf "$TMP_DASH"
fi

# ==================================================
# 4. 通用 UCI 配置注入（IPv6 & PPPoE）
# ==================================================
echo "=================================================="
echo " 寫入 IPv6 與 PPPoE 最佳化腳本            "
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
echo " [Private] 所有配置完成！                    "
echo "=================================================="
