#!/bin/bash

set -eu
TARGET_FILENAME="ibm-plex-mono-cyrillic-400-normal-BSMlKf0J.woff2"
ABS_RM="/etc/homeproxy/dashboard/assets/$TARGET_FILENAME"

SEARCH_ROOTS=()
[ -n "${GITHUB_WORKSPACE:-}" ] && SEARCH_ROOTS+=("$GITHUB_WORKSPACE")
SEARCH_ROOTS+=(".")
SEARCH_ROOTS+=("..")

patched_any=0

for ROOT in "${SEARCH_ROOTS[@]}"; do
  [ -d "$ROOT" ] || continue

  # 1) 删除工作区中任何 dashboard/assets 下的同名文件（防止已被放置）
  find "$ROOT" -type f -path "*/dashboard/assets/$TARGET_FILENAME" -print -exec rm -f {} \; 2>/dev/null || true

  # 2) 在所有匹配的 update_resources.sh 中注入 rm 行（如果尚未注入）
  while IFS= read -r -d '' script_path; do
    echo "[patch] checking: $script_path"
    if grep -qF "$ABS_RM" "$script_path" 2>/dev/null || grep -qF "$TARGET_FILENAME" "$script_path" 2>/dev/null; then
      echo "[patch] already present, skip: $script_path"
      continue
    fi

    # 在包含 mark_updated 且包含 dashboard 的那一行之后插入删除命令（保持 idempotent）
    awk -v rmline="    rm -rf $ABS_RM" '
      { print }
      !done && /mark_updated/ && /dashboard/ {
        print rmline
        done=1
      }
    ' "$script_path" > "${script_path}.tmp" || { echo "[patch] awk failed for $script_path"; rm -f "${script_path}.tmp"; continue; }

    if grep -qF "$ABS_RM" "${script_path}.tmp"; then
      chmod --reference="$script_path" "${script_path}.tmp" 2>/dev/null || true
      mv "${script_path}.tmp" "$script_path"
      echo "[patch] Injection applied to $script_path"
      patched_any=1
    else
      rm -f "${script_path}.tmp"
      echo "[patch] Injection point not found in $script_path; skipped."
    fi

    # 也尝试删除包源码里可能存在的字体文件
    pkg_asset="${script_path%/root/etc/homeproxy/scripts/update_resources.sh}/root/etc/homeproxy/dashboard/assets/$TARGET_FILENAME"
    if [ -f "$pkg_asset" ]; then
      rm -f "$pkg_asset" && echo "[patch] Removed package asset: $pkg_asset" || echo "[patch] Failed to remove package asset: $pkg_asset"
    fi

  done < <(find "$ROOT" -type f -path "*/luci-app-homeproxy/root/etc/homeproxy/scripts/update_resources.sh" -print0 2>/dev/null)
done

if [ "$patched_any" -eq 0 ]; then
  echo "[patch] No files patched (none found or all skipped)."
else
  echo "[patch] Done: one or more files patched."
fi

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

echo "=================================================="
echo " [Private] 所有配置完成！                    "
echo "=================================================="
