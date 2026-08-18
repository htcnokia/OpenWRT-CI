#!/bin/bash
echo "[+] 添加备份文件夹路径..."
mkdir -p files/etc
touch files/etc/sysupgrade.conf

if ! grep -qxF '/etc/homeproxy/private_srs' files/etc/sysupgrade.conf 2>/dev/null; then
  echo '/etc/homeproxy/private_srs' >> files/etc/sysupgrade.conf
fi
chmod 644 files/etc/sysupgrade.conf

#安装和更新软件包
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
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not fonud directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git"

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f $REPO_NAME $PKG_NAME
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现cor[...]

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name，可选，pkg为从大杂烩中单独提取包名插件；name为重命名为包名"

# 1. 处理集客AC插件
echo "[+] 更换 luci-app-gecoosac..."
UPDATE_PACKAGE "luci-app-gecoosac" "laipeng668/luci-app-gecoosac" "main" "" "luci-app-gecoosac gecoosac"

echo "[+] 更换 luci-app-timecontrol..."
UPDATE_PACKAGE "luci-app-timecontrol" "gaobin89/luci-app-timecontrol" "js" "" "luci-app-timecontrol"

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
