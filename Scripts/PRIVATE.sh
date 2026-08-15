#!/bin/bash

#!/bin/bash
# PRIVATE.sh - 在 update & install feeds 之后执行

# 1. 判断当前是不是在编译 x86_64
if grep -q "CONFIG_TARGET_x86_64=y" .config 2>/dev/null || [ "$1" = "X86" ]; then
  echo "🎯 检测到当前正在编译 X86_64 平台，准备应用 dockerd 热补丁..."

  # 2. 找到 feeds 中 dockerd 的 Makefile 路径（可能在 feeds/packages 或 package/feeds/packages）
  DOCKERD_MAKEFILE=$(find feeds/packages/ package/feeds/packages/ -path "*/dockerd/Makefile" 2>/dev/null | head -n 1)

  if [ -n "$DOCKERD_MAKEFILE" ] && [ -f "$DOCKERD_MAKEFILE" ]; then
    echo "🛠️ 找到目标 Makefile: $DOCKERD_MAKEFILE"
    
    # 3. 强行给 cp 命令加上 -f 容错，或者将报错的那行 cp 容错处理
    sed -i 's/cp -a/cp -af/g' "$DOCKERD_MAKEFILE"
    sed -i 's/cp -r/cp -rf/g' "$DOCKERD_MAKEFILE"
    
    echo "✅ 成功给 dockerd 注入热补丁！"
  else
    echo "⚠️ 未找到 dockerd Makefile，跳过补丁。"
  fi
fi

# 仅在编译 IPQ60XX 时执行局部瘦身

# 1. 检查当前编译的目标平台是否为 IPQ60XX (通过 .config 文件判断)
if grep -q "CONFIG_TARGET_qualcommax_ipq60xx=y" .config 2>/dev/null || grep -q "IPQ60XX" .config 2>/dev/null; then
  echo "🎯 检测到当前正在编译 IPQ60XX 平台，准备执行专属瘦身..."

  # 需要强制剔除的组件列表
  DISABLE_PKGS=(
    "dockerd"
    "docker"
    "containerd"
    "docker-compose"
    "luci-app-dockerman"
    "luci-lib-docker"
    "luci-app-samba4"
    "samba4-server"
    "samba4-libs"
    "ksmbd"
    "luci-app-ksmbd"
    "python3"
  )

  # 强制把最终合并生成的 .config 里的这些配置强制删掉并设为 =n
  for pkg in "${DISABLE_PKGS[@]}"; do
    # 先删掉原来的 =y (包含 GENERAL.txt 合进来的)
    sed -i "/CONFIG_PACKAGE_${pkg}=/d" .config
    # 强制写入 =n
    echo "CONFIG_PACKAGE_${pkg}=n" >> .config
  done

  echo "✅ IPQ60XX 专属精简处理完毕，Samba4 与 Docker 已成功裁剪！"
fi
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
