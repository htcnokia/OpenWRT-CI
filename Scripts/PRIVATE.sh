#!/bin/bash
echo "[+] 添加备份文件夹路径..."
mkdir -p files/etc
touch files/etc/sysupgrade.conf

if ! grep -qxF '/etc/homeproxy/private_srs' files/etc/sysupgrade.conf 2>/dev/null; then
  echo '/etc/homeproxy/private_srs' >> files/etc/sysupgrade.conf
fi
chmod 644 files/etc/sysupgrade.conf

# 1. 处理集客AC插件
echo "[+] 更换 luci-app-gecoosac..."
UPDATE_PACKAGE "luci-app-gecoosac" "laipeng668/luci-app-gecoosac" "main"

echo "[+] 更换 luci-app-timecontrol..."
UPDATE_PACKAGE "luci-app-timecontrol" "gaobin89/luci-app-timecontrol" "js"

# ==================================================
# 1. X86_64 平台专属：dockerd 嵌套二进制 cp 空变量报错终极修复
# ==================================================

IS_X86=false
if [ "$WRT_CONFIG" = "X86" ] || grep -qE "CONFIG_TARGET_x86_64=y|CONFIG_TARGET_x86=y" .config 2>/dev/null; then
  IS_X86=true
fi

if [ "$IS_X86" = true ]; then
  echo "[Private] 🎯 检测到当前正在编译 X86_64 平台，准备应用 dockerd 热补丁..."

  # 1. 全局查找 dockerd Makefile，给 hack/make.sh 调用环境传一个空数组防护/或过滤 empty cp
  DOCKERD_MAKEFILES=$(find /home/runner/work/ ./ ../ -name "Makefile" 2>/dev/null | grep -E "utils/dockerd/Makefile|dockerd/Makefile")

  if [ -n "$DOCKERD_MAKEFILES" ]; then
    for mk in $DOCKERD_MAKEFILES; do
      if [ -f "$mk" ]; then
        echo "[Private] 🛠️ 正在修复 dockerd Makefile: $mk"

        # 在 Makefile 的 Build/Compile 阶段，如果 DOCKER_DOCKERD_NESTED_EXECUTABLES 未定义，传一个占位符或规避 cp 空
        # 方法：修补 Makefile，使 hack/make/binary-daemon 里面的 cp 命令容错
        # 提示：OpenWrt 的 dockerd Makefile 通常会使用 patch 或直接调用 hack/make.sh
        
        # 修正 Makefile 中可能存在的 cp 逻辑
        sed -i 's/cp -a/cp -af/g' "$mk"
        
        # 如果 Makefile 中包含传递给 hack/make.sh 的环境变量，追加安全设置
        if grep -q "hack/make.sh" "$mk"; then
          # 拦截 hack/make/binary-daemon 中的 cp -a ${DOCKER_DOCKERD_NESTED_EXECUTABLES}
          # 直接在 Makefile 编译前注入 sed 指令，自动修改解压后的 hack/make/binary-daemon
          sed -i '/Build\/Compile/a \t[ -f $(PKG_BUILD_DIR)/hack/make/binary-daemon ] && sed -i '"'"'s/cp -a \$${DOCKER_DOCKERD_NESTED_EXECUTABLES}/[ -n "$${DOCKER_DOCKERD_NESTED_EXECUTABLES}" ] \&\& cp -a \$${DOCKER_DOCKERD_NESTED_EXECUTABLES}/g'"'"' $(PKG_BUILD_DIR)/hack/make/binary-daemon || true' "$mk"
        fi
      fi
    done
    echo "[Private] ✅ dockerd Makefile 注入完成！"
  fi

  # 2. 如果 build_dir 目录中已经存在解压好的 dockerd 源码，直接强刷 binary-daemon 脚本
  BUILD_BINARY_DAEMONS=$(find /home/runner/work/ ./ ../ -path "*/dockerd-*/hack/make/binary-daemon" 2>/dev/null)
  for bd in $BUILD_BINARY_DAEMONS; do
    if [ -f "$bd" ]; then
      echo "[Private] 🛠️ 直接修补已解压的 Docker 源码: $bd"
      sed -i 's/cp -a ${DOCKER_DOCKERD_NESTED_EXECUTABLES}/[ -n "${DOCKER_DOCKERD_NESTED_EXECUTABLES}" ] && cp -a ${DOCKER_DOCKERD_NESTED_EXECUTABLES}/g' "$bd"
      sed -i 's/cp -a "$DOCKER_DOCKERD_NESTED_EXECUTABLES"/[ -n "$DOCKER_DOCKERD_NESTED_EXECUTABLES" ] && cp -a "$DOCKER_DOCKERD_NESTED_EXECUTABLES"/g' "$bd"
    fi
  done

else
  echo "[Private] 🚀 当前任务无需 X86 热补丁。"
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

echo "=================================================="
echo " [Private] 所有配置完成！                    "
echo "=================================================="
