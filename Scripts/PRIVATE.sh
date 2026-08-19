#!/bin/bash
set -eu

TARGET_FILENAME="ibm-plex-mono-cyrillic-400-normal-BSMlKf0J.woff2"
ABS_RM="/etc/homeproxy/dashboard/assets/$TARGET_FILENAME"

# 1. 自动去重定位根目录，避免重复递归扫描
SEARCH_ROOT="${GITHUB_WORKSPACE:-.}"

patched_any=0

echo "[patch] 开始搜索并清理 HomeProxy 资源文件..."

# 2. 删除源码树中已存在的静态字体文件（排除编译缓存大目录以提升性能）
while IFS= read -r -d '' asset_file; do
  if rm -f "$asset_file"; then
    echo "[patch] [成功删除静态文件]: $asset_file"
    patched_any=1
  fi
done < <(find "$SEARCH_ROOT" \( -path "*/build_dir" -o -path "*/staging_dir" -o -path "*/.git" \) -prune -o \
  -type f -path "*/dashboard/assets/$TARGET_FILENAME" -print0 2>/dev/null)

# 3. 采用进程替换 '< <(find...)' 替代管道，防止 while 处于子 Shell 导致 patched_any 变量失效
while IFS= read -r -d '' script_path; do
  echo "[patch] 正在检查脚本: $script_path"

  # 检查是否已注入
  if grep -qF "$ABS_RM" "$script_path" 2>/dev/null || grep -qF "$TARGET_FILENAME" "$script_path" 2>/dev/null; then
    echo "[patch] 该文件已完成过修补，跳过: $script_path"
    continue
  fi

  # 使用 awk 注入 rm 指令
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
      echo "[patch] [成功注入修改]: $script_path"
      patched_any=1
    else
      rm -f "${script_path}.tmp"
      echo "[patch] 未找到注入锚点，跳过: $script_path"
    fi
  else
    echo "[patch] awk 处理失败: $script_path"
    rm -f "${script_path}.tmp"
  fi

  # 顺带清理同包下的关联静态资源
  pkg_asset="${script_path%/scripts/update_resources.sh}/dashboard/assets/$TARGET_FILENAME"
  if [ -f "$pkg_asset" ]; then
    if rm -f "$pkg_asset"; then
      echo "[patch] [成功删除包内关联资源]: $pkg_asset"
      patched_any=1
    else
      echo "[patch] 删除关联资源失败: $pkg_asset"
    fi
  fi
done < <(find "$SEARCH_ROOT" \( -path "*/build_dir" -o -path "*/staging_dir" -o -path "*/.git" \) -prune -o \
  -type f -path "*/etc/homeproxy/scripts/update_resources.sh" -print0 2>/dev/null)

# 4. 汇总结果输出
if [ "$patched_any" -eq 0 ]; then
  echo "[patch] 提示：未修改任何文件（可能已是最新状态或未找到目标文件）。"
else
  echo "[patch] 完成：成功对目标文件进行了补丁注入与资源清理！"
fi

echo "=================================================="
echo " [Private] 所有配置完成！                         "
echo "=================================================="
