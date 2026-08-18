#!/bin/bash
# 安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			echo "$FOUND_DIRS" | while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "./$REPO_NAME/" -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME/"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

echo "更换 gaobin89/luci-app-timecontrol"
UPDATE_PACKAGE "luci-app-timecontrol" "gaobin89/luci-app-timecontrol" "js" "" "luci-app-timecontrol"

echo "更换 laipeng668/luci-app-gecoosac"
UPDATE_PACKAGE "luci-app-gecoosac" "laipeng668/luci-app-gecoosac" "main" "" "luci-app-gecoosac"

# 1. 清理並重新複製 luci-app-gecoosac
echo "[+] 清理舊版 luci-app-gecoosac..."
rm -rf package/luci-app-gecoosac
rm -rf luci-app-gecoosac
rm -rf package/feeds/luci/luci-app-gecoosac
rm -rf package/feeds/packages/luci-app-gecoosac

echo "[+] 克隆 laipeng668 版 luci-app-gecoosac..."
git clone -b main  https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac

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
  echo '查找文件：dashboard/assets'
  # 1) 删除工作区中任何 dashboard/assets 下的同名文件
  find "$ROOT" -type f -path "*/dashboard/assets/$TARGET_FILENAME" -print -exec rm -f {} \; 2>/dev/null || true

  # 2) 在所有匹配的 update_resources.sh 中注入 rm 行
  find "$ROOT" -type f -path "*/luci-app-homeproxy/root/etc/homeproxy/scripts/update_resources.sh" -print0 2>/dev/null | while IFS= read -r -d '' script_path; do
    echo "[patch] checking: $script_path"
    if grep -qF "$ABS_RM" "$script_path" 2>/dev/null || grep -qF "$TARGET_FILENAME" "$script_path" 2>/dev/null; then
      echo "[patch] already present, skip: $script_path"
      continue
    fi

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

    pkg_asset="${script_path%/root/etc/homeproxy/scripts/update_resources.sh}/root/etc/homeproxy/dashboard/assets/$TARGET_FILENAME"
    if [ -f "$pkg_asset" ]; then
      rm -f "$pkg_asset" && echo "[patch] Removed package asset: $pkg_asset" || echo "[patch] Failed to remove package asset: $pkg_asset"
    fi
  done
done

if [ "$patched_any" -eq 0 ]; then
  echo "[patch] No files patched (none found or all skipped)."
else
  echo "[patch] Done: one or more files patched."
fi

# ==================================================
# 1. X86_64 平台专属修复
# ==================================================
IS_X86=false
if [ "${WRT_CONFIG:-}" = "X86" ] || grep -qE "CONFIG_TARGET_x86_64=y|CONFIG_TARGET_x86=y" .config 2>/dev/null; then
  IS_X86=true
fi

# 设置要查看的文件（如果脚本已有 mk 变量，则不需要这行）
mk="/mnt/build_wrt/feeds/packages/utils/dockerd/Makefile"

if [ -f "$mk" ]; then
  echo
  echo "===================== Dumping Makefile: $mk ====================="

  echo
  echo "1) Full file with line numbers:"
  nl -ba -w3 -s': ' "$mk" || true

  echo
  echo "2) Visible view (tabs -> <TAB>, spaces -> ·, CR -> <CR>) with line numbers:"
  sed -n '1,$p' "$mk" | sed -e $'s/\t/<TAB>/g' -e 's/ /·/g' -e 's/\r/<CR>/g' | nl -ba -w3 -s': ' || true

  echo
  echo "3) cat -v output (shows ^M for CRLF) with line numbers:"
  cat -v "$mk" | nl -ba -w3 -s': ' || true

  echo
  echo "4) Hex dump of file start (to check BOM/encoding):"
  head -c 64 "$mk" | od -An -tx1 || true

  echo
  echo "5) Lines that contain CR (Windows CRLF):"
  grep -n $'\r' "$mk" || echo "no CR found in $mk"

  echo "===================== End dump for: $mk ====================="
  echo
else
  echo "File not found: $mk"
fi

IS_X86=false
if [ "$IS_X86" = true ]; then
  echo "[Private] 🎯 检测到当前正在编译 X86_64 平台..."
  DOCKERD_MAKEFILES=$(find /home/runner/work/ ./ ../ -name "Makefile" 2>/dev/null | grep -E "utils/dockerd/Makefile|dockerd/Makefile")

  if [ -n "$DOCKERD_MAKEFILES" ]; then
    for mk in $DOCKERD_MAKEFILES; do
      if [ -f "$mk" ]; then
        echo "[Private] 🛠️ 正在修复 dockerd Makefile: $mk"
        sed -i 's/cp -a/cp -af/g' "$mk"
        if grep -q "hack/make.sh" "$mk"; then
          sed -i '/Build\/Compile/a 	[ -f $(PKG_BUILD_DIR)/hack/make/binary-daemon ] && sed -i '"'"'s/cp -a \\$\\${DOCKER_DOCKERD_NESTED_EXECUTABLES}/[ -n "\\$\\${DOCKER_DOCKERD_NESTED_EXECUTABLES}" ] \\&\\& cp -a \\$\\${DOCKER_DOCKERD_NESTED_EXECUTABLES}/g'"'"' $(PKG_BUILD_DIR)/hack/make/binary-daemon || true' "$mk"
        fi
      fi
    done
    echo "[Private] ✅ dockerd Makefile 注入完成！"
  fi

  BUILD_BINARY_DAEMONS=$(find /home/runner/work/ ./ ../ -path "*/dockerd-*/hack/make/binary-daemon" 2>/dev/null)
  for bd in $BUILD_BINARY_DAEMONS; do
    if [ -f "$bd" ]; then
      echo "[Private] 🛠️ 直接修补已解压的 Docker 源码: $bd"
      sed -i 's/cp -a ${DOCKER_DOCKERD_NESTED_EXECUTABLES}/[ -n "${DOCKER_DOCKERD_NESTED_EXECUTABLES}" ] \&\& cp -a ${DOCKER_DOCKERD_NESTED_EXECUTABLES}/g' "$bd"
      sed -i 's/cp -a "$DOCKER_DOCKERD_NESTED_EXECUTABLES"/[ -n "$DOCKER_DOCKERD_NESTED_EXECUTABLES" ] \&\& cp -a "$DOCKER_DOCKERD_NESTED_EXECUTABLES"/g' "$bd"
    fi
  done
else
  echo "[Private] 🚀 当前任务无需 X86 热补丁。"
fi

echo "=================================================="
echo " [Private] 所有配置完成！                    "
echo "=================================================="
