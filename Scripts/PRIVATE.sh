#!/bin/bash
set -eu

TARGET_FILENAME="ibm-plex-mono-cyrillic-400-normal-BSMlKf0J.woff2"
ABS_RM="/etc/homeproxy/dashboard/assets/$TARGET_FILENAME"

# 统一使用当前执行目录（即 cd ./wrt/ 后的工作区）
SEARCH_ROOT="."

patched_any=0

echo "[patch] 开始搜索并清理 HomeProxy 资源文件..."

# 1) 删除当前目录下所有 dashboard/assets 里的目标静态文件
while IFS= read -r -d '' asset_file; do
  if rm -f "$asset_file"; then
    echo "[patch] [成功删除静态文件]: $asset_file"
    patched_any=1
  fi
done < <(find "$SEARCH_ROOT" \
  \( -type d \( -name "build_dir" -o -name "staging_dir" -o -name ".git" \) -prune \) -o \
  \( -type f -path "*/dashboard/assets/$TARGET_FILENAME" -print0 \) 2>/dev/null)

# 2) 查找 update_resources.sh 并注入指令（使用 < <(...) 保证 patched_any 生效）
while IFS= read -r -d '' script_path; do
  echo "[patch] 检查: $script_path"

  # 防重复注入
  if grep -qF "$ABS_RM" "$script_path" 2>/dev/null || grep -qF "$TARGET_FILENAME" "$script_path" 2>/dev/null; then
    echo "[patch] 已经存在, 跳过: $script_path"
    continue
  fi

  # awk 注入 rm 指令
  if awk -v rmline="    rm -rf $ABS_RM" '
    { print }
    !done && /mark_updated/ && /dashboard/ {
      print rmline
      done=1
    }
  ' "$script_path" > "${script_path}.tmp" 2>/dev/null; then

    if grep -qF "$ABS_RM" "${script_path}.tmp"; then
      chmod --reference="$script_path" "${script_path}.tmp" 2>/dev/null || true
      mv "${script_path}.tmp" "$script_path"
      echo "[patch] 注入应用于 $script_path"
      patched_any=1
    else
      rm -f "${script_path}.tmp"
      echo "[patch] 注入点未发现: $script_path; skipped."
    fi
  else
    echo "[patch] awk 处理失败: $script_path"
    rm -f "${script_path}.tmp"
  fi

  # 清理包内静态文件
  pkg_asset="${script_path%/scripts/update_resources.sh}/dashboard/assets/$TARGET_FILENAME"
  if [ -f "$pkg_asset" ]; then
    if rm -f "$pkg_asset"; then
      echo "[patch] 移除资源文件: $pkg_asset"
      patched_any=1
    fi
  fi
done < <(find "$SEARCH_ROOT" \
  \( -type d \( -name "build_dir" -o -name "staging_dir" -o -name ".git" \) -prune \) -o \
  \( -type f -path "*/luci-app-homeproxy/root/etc/homeproxy/scripts/update_resources.sh" -print0 \) 2>/dev/null)

# 3. 汇总输出
if [ "$patched_any" -eq 0 ]; then
  echo "[patch] 提示：未修改任何文件（可能已是最新状态或未找到目标文件）。"
else
  echo "[patch] 完成：成功对目标文件进行了补丁注入与资源清理！"
fi

echo "=================================================="
echo " [Private] 所有配置完成！                         "
echo "=================================================="
