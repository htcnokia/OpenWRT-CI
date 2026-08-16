#!/bin/bash
# PRIVATE.sh - 在 update & install feeds 之后执行

# ==================================================
# 1. X86_64 平台专属：dockerd Makefile 热补丁修复
# ==================================================

IS_X86=false
if [ "$WRT_CONFIG" = "X86" ] || grep -qE "CONFIG_TARGET_x86_64=y|CONFIG_TARGET_x86=y" .config 2>/dev/null; then
  IS_X86=true
fi

if [ "$IS_X86" = true ]; then
  echo "[Private] 🎯 检测到当前正在编译 X86_64 平台，准备应用 dockerd 热补丁..."

  # 寻找 feeds 或 package 中 dockerd 的 Makefile 路径
  DOCKERD_MAKEFILE=$(find ./ -path "*/dockerd/Makefile" 2>/dev/null | head -n 1)

  if [ -n "$DOCKERD_MAKEFILE" ] && [ -f "$DOCKERD_MAKEFILE" ]; then
    echo "[Private] 🛠️ 找到目标 Makefile: $DOCKERD_MAKEFILE"

    # 强行给 cp 命令加上 -f 容错，防止 cp 遇到空变量/空路径报错中断编译
    sed -i 's/cp -a/cp -af/g' "$DOCKERD_MAKEFILE"
    sed -i 's/cp -r/cp -rf/g' "$DOCKERD_MAKEFILE"
    sed -i 's/cp /cp -f /g' "$DOCKERD_MAKEFILE"
    sed -i 's/\$(CP) /\$(CP) -f /g' "$DOCKERD_MAKEFILE"

    echo "[Private] ✅ 成功给 dockerd 注入热补丁！"
  else
    echo "[Private] ⚠️ 未找到 dockerd Makefile，跳过补丁。"
  fi
else
  echo "[Private] 🚀 当前为 $WRT_CONFIG 编译任务，跳过 X86 热补丁。"
fi

# ==================================================
# 2. IPQ60XX 平台专属：动态搜寻并合并 Private-60xx.txt
# ==================================================

IS_IPQ60XX=false
if [ "$WRT_CONFIG" = "IPQ60XX-WIFI-NO" ] || [ "$WRT_CONFIG" = "IPQ60XX-WIFI-YES" ] || grep -q "CONFIG_TARGET_qualcommax" .config 2>/dev/null; then
  IS_IPQ60XX=true
fi

if [ "$IS_IPQ60XX" = true ]; then
  echo "[Private] 🎯 检测到当前正在编译 IPQ60XX 平台，准备应用 Private-60xx 合并..."

  # 优先找上级 Config 目录，找不到再全局搜索
  PRIVATE_60XX_PATH=""
  if [ -f "../Config/Private-60xx.txt" ]; then
    PRIVATE_60XX_PATH="../Config/Private-60xx.txt"
  elif [ -n "$GITHUB_WORKSPACE" ] && [ -f "$GITHUB_WORKSPACE/Config/Private-60xx.txt" ]; then
    PRIVATE_60XX_PATH="$GITHUB_WORKSPACE/Config/Private-60xx.txt"
  else
    PRIVATE_60XX_PATH=$(find /home/runner/work/ -type f -name "Private-60xx.txt" 2>/dev/null | head -n 1)
  fi

  if [ -n "$PRIVATE_60XX_PATH" ] && [ -f "$PRIVATE_60XX_PATH" ]; then
    echo "[Private] 🛠️ 成功找到配置文件: $PRIVATE_60XX_PATH"

    # 1. 删除需要剔除的组件
    DISABLE_PKGS="dockerd docker containerd docker-compose luci-app-dockerman luci-lib-docker luci-app-samba4 samba4-server samba4-libs ksmbd luci-app-ksmbd python3"
    for pkg in $DISABLE_PKGS; do
      sed -i -E "/^CONFIG_PACKAGE_${pkg}=/d; /^# CONFIG_PACKAGE_${pkg} is not set/d" .config 2>/dev/null || true
    done

    # 2. 追加合并 Private-60xx.txt
    if ! grep -qF "# --- IPQ60XX EXCLUSIVE ---" .config 2>/dev/null; then
      cat "$PRIVATE_60XX_PATH" >> .config
      echo "[Private] ✅ 成功追加合并 $PRIVATE_60XX_PATH 到 .config！"
    else
      echo "[Private] ℹ️ Private-60xx 配置已存在，跳过追加。"
    fi
  else
    echo "[Private] ⚠️ 未能找到 Private-60xx.txt 文件，跳过合并。"
  fi
else
  echo "[Private] 🚀 当前任务无需精简，跳过 IPQ60XX 逻辑。"
fi

# ==================================================
# 3. 通用 UCI 配置注入（IPv6 & PPPoE）
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
